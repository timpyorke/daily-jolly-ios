import Foundation
import SwiftUI
import Observation
import SwiftData

@Observable
@MainActor
final class RecipeEditViewModel {

    // MARK: - State Properties

    private(set) var recipe: RecipeEntity?
    var name: String = ""
    var note: String = ""
    var category: String = ""
    var batchSize: Int = 1
    var batchUnit: String = "pcs"
    var templateType: GellingAgentType?
    var steps: [StepInput] = []
    var ingredients: [IngredientInput] = []

    // MARK: - UI State

    var isAddingStep: Bool = false
    var isAddingIngredient: Bool = false
    var showDeleteAlert: Bool = false
    var isLoading = false
    var isSaving = false
    var isDeleting = false
    var errorMessage: String?
    var showError = false

    // MARK: - Dependencies

    private var repository: RecipeRepository?
    private var inventoryRepository: InventoryRepository?

    // MARK: - Computed Properties

    var isEditing: Bool { recipe != nil }

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var totalCost: Double {
        calculateTotalCost()
    }

    // MARK: - Setup

    func setup(modelContext: ModelContext, recipeId: PersistentIdentifier?) {
        self.repository = RecipeRepository(modelContext: modelContext)
        self.inventoryRepository = InventoryRepository(modelContext: modelContext)

        if let id = recipeId {
            loadRecipe(id: id)
        }
    }

    // MARK: - Actions

    func loadRecipe(id: PersistentIdentifier) {
        guard let repository else { return }

        isLoading = true
        defer { isLoading = false }

        switch repository.fetch(by: id) {
        case .success(let fetchedRecipe):
            recipe = fetchedRecipe
            name = fetchedRecipe.name
            note = fetchedRecipe.note
            category = fetchedRecipe.category ?? ""
            batchSize = fetchedRecipe.batchSize
            batchUnit = fetchedRecipe.batchUnit
            templateType = fetchedRecipe.templateType
            steps = fetchedRecipe.sortedSteps.map { step in
                StepInput(
                    title: step.title,
                    note: step.note,
                    time: step.time,
                    isTimerRequired: step.isTimerRequired || step.time > 0,
                    requiredMeasurements: step.requiredMeasurements,
                    lineIdentifier: step.lineIdentifier
                )
            }
            ingredients = fetchedRecipe.ingredients.map { ingredient in
                IngredientInput(
                    inventoryId: ingredient.inventoryItem.persistentModelID,
                    inventoryName: ingredient.inventoryItem.name,
                    quantity: ingredient.quantity,
                    unitSymbol: ingredient.unitSymbol,
                    note: ingredient.note ?? ""
                )
            }
        case .failure(let error):
            print("[RecipeEditViewModel] Failed to load recipe: \(error)")
            recipe = nil
        }
    }

    func saveRecipe(onComplete: () -> Void) {
        guard !AppSettings.shared.isRecipeEditLocked else { return }
        guard let repository, let inventoryRepository else { return }

        isSaving = true
        defer { isSaving = false }

        if let recipe {
            // Rebuild relationships first: it can refuse the edit (batch in
            // progress), and nothing should be saved in that case.
            let recipeSteps = steps.map { step in
                RecipeStepInput(
                    title: step.title,
                    note: step.note,
                    time: step.time,
                    isTimerRequired: step.isTimerRequired,
                    requiredMeasurements: step.requiredMeasurements,
                    lineIdentifier: step.lineIdentifier
                )
            }
            let recipeIngredients = ingredients.map { ingredient in
                RecipeIngredientInput(
                    inventoryId: ingredient.inventoryId,
                    quantity: ingredient.quantity,
                    unitSymbol: ingredient.unitSymbol,
                    note: ingredient.note.isEmpty ? nil : ingredient.note
                )
            }

            if case .failure(let error) = repository.rebuildRelationships(recipe, steps: recipeSteps, ingredients: recipeIngredients) {
                handleError(error)
                return
            }

            switch repository.updateBasicInfo(
                recipe,
                name: name,
                note: note,
                category: category.isEmpty ? nil : category,
                batchSize: batchSize,
                batchUnit: batchUnit,
                templateType: templateType
            ) {
            case .success:
                onComplete()
            case .failure(let error):
                handleError(error)
            }
        } else {
            // Create new recipe
            let newRecipe = RecipeEntity(
                name: name.trimmingCharacters(in: .whitespaces),
                note: note,
                category: category.isEmpty ? nil : category.trimmingCharacters(in: .whitespaces),
                batchSize: batchSize,
                batchUnit: batchUnit.isEmpty ? "pcs" : batchUnit.trimmingCharacters(in: .whitespaces),
                templateType: templateType
            )

            // Add steps
            for (index, stepInput) in steps.enumerated() {
                let step = RecipeStepEntity(
                    title: stepInput.title,
                    note: stepInput.note,
                    time: stepInput.time,
                    isTimerRequired: stepInput.isTimerRequired,
                    order: index,
                    requiredMeasurements: stepInput.requiredMeasurements,
                    lineIdentifier: stepInput.lineIdentifier
                )
                step.recipe = newRecipe
                newRecipe.steps.append(step)
            }

            // Add ingredients
            for ingredientInput in ingredients {
                switch inventoryRepository.fetch(by: ingredientInput.inventoryId) {
                case .success(let inventory):
                    let ingredient = IngredientEntity(
                        inventoryItem: inventory,
                        quantity: ingredientInput.quantity,
                        unitSymbol: ingredientInput.unitSymbol,
                        note: ingredientInput.note.isEmpty ? nil : ingredientInput.note,
                        recipe: newRecipe
                    )
                    newRecipe.ingredients.append(ingredient)
                case .failure(let error):
                    handleError(error)
                    return
                }
            }

            switch repository.create(newRecipe) {
            case .success:
                // Force a context save to ensure the new recipe has a permanent ID
                // before the view dismisses and triggers a refresh in the list view.
                onComplete()
            case .failure(let error):
                handleError(error)
            }
        }
    }

    func deleteRecipe(onComplete: () -> Void) {
        guard let recipe, let repository else { return }

        isDeleting = true
        defer { isDeleting = false }

        switch repository.delete(recipe) {
        case .success:
            onComplete()
        case .failure(let error):
            handleError(error)
        }
    }

    func addStep(_ step: StepInput) {
        steps.append(step)
    }

    func updateStep(_ step: StepInput) {
        if let index = steps.firstIndex(where: { $0.id == step.id }) {
            steps[index] = step
        }
    }

    func removeStep(_ step: StepInput) {
        steps.removeAll { $0.id == step.id }
    }

    func moveSteps(from: IndexSet, to: Int) {
        steps.move(fromOffsets: from, toOffset: to)
    }

    func applyTemplate(_ template: GellingAgentType) {
        let templateSteps = ProductionTemplateService.shared.getSteps(for: template)
        steps = templateSteps.map { step in
            StepInput(
                title: step.title,
                note: step.note,
                time: step.time,
                isTimerRequired: step.isTimerRequired || step.time > 0,
                requiredMeasurements: step.requiredMeasurements,
                lineIdentifier: step.lineIdentifier
            )
        }
    }

    func addIngredient(_ ingredient: IngredientInput) {
        ingredients.append(ingredient)
    }

    func removeIngredient(_ ingredient: IngredientInput) {
        ingredients.removeAll { $0.id == ingredient.id }
    }

    // MARK: - Private Helpers

    private func calculateTotalCost() -> Double {
        guard let inventoryRepository else { return 0.0 }

        return ingredients.reduce(0.0) { total, ingredient in
            switch inventoryRepository.fetch(by: ingredient.inventoryId) {
            case .success(let inventory):
                // Try to convert if both are built-in units
                var quantityInBaseUnit = ingredient.quantity
                if let fromUnit = InventoryUnit(rawValue: ingredient.unitSymbol.lowercased()),
                   let toUnit = inventory.builtInUnit,
                   let converted = fromUnit.convert(ingredient.quantity, to: toUnit) {
                    quantityInBaseUnit = converted
                }
                return total + (quantityInBaseUnit * inventory.unitPrice)
            case .failure:
                return total
            }
        }
    }

    // MARK: - Error Handling

    private func handleError(_ error: AppError) {
        errorMessage = error.localizedDescription
        showError = true
    }
}
