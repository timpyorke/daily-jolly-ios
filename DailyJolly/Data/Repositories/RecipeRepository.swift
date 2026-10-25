import SwiftData
import Foundation

@MainActor
protocol RecipeRepositoryProtocol {
    func fetchAll() -> Result<[RecipeEntity], AppError>
    func fetch(by id: PersistentIdentifier) -> Result<RecipeEntity, AppError>
    func search(name: String) -> Result<[RecipeEntity], AppError>
    func fetchFavorites() -> Result<[RecipeEntity], AppError>
    func fetchByCategory(_ category: String) -> Result<[RecipeEntity], AppError>
    func create(_ recipe: RecipeEntity) -> Result<Void, AppError>
    func delete(_ recipe: RecipeEntity) -> Result<Void, AppError>
    func updateBasicInfo(_ recipe: RecipeEntity, name: String, note: String, category: String?, batchSize: Int, batchUnit: String, templateType: GellingAgentType?) -> Result<Void, AppError>
    func rebuildRelationships(_ recipe: RecipeEntity, steps: [RecipeStepInput], ingredients: [RecipeIngredientInput]) -> Result<Void, AppError>
    func duplicate(_ recipe: RecipeEntity) -> Result<RecipeEntity, AppError>
}

// MARK: - Input Models for Recipe Updates

struct RecipeStepInput {
    let title: String
    let note: String
    let time: Int
    let isTimerRequired: Bool
    let requiredMeasurements: [MeasurementType]
    let lineIdentifier: String?
}

struct RecipeIngredientInput {
    let inventoryId: PersistentIdentifier
    let quantity: Double
    let unitSymbol: String
    let note: String?
}

@MainActor
final class RecipeRepository: RecipeRepositoryProtocol {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Fetch

    func fetchAll() -> Result<[RecipeEntity], AppError> {
        do {
            let descriptor = FetchDescriptor<RecipeEntity>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            let recipes = try modelContext.fetch(descriptor)
            return .success(recipes)
        } catch {
            return .failure(.databaseError("Failed to fetch recipes"))
        }
    }

    func fetch(by id: PersistentIdentifier) -> Result<RecipeEntity, AppError> {
        guard let recipe = modelContext.model(for: id) as? RecipeEntity else {
            return .failure(.notFound("Recipe"))
        }
        return .success(recipe)
    }

    func search(name: String) -> Result<[RecipeEntity], AppError> {
        do {
            let descriptor = FetchDescriptor<RecipeEntity>(
                predicate: #Predicate { $0.name.localizedStandardContains(name) },
                sortBy: [SortDescriptor(\.name)]
            )
            let recipes = try modelContext.fetch(descriptor)
            return .success(recipes)
        } catch {
            return .failure(.databaseError("Failed to search recipes"))
        }
    }

    func fetchFavorites() -> Result<[RecipeEntity], AppError> {
        do {
            let descriptor = FetchDescriptor<RecipeEntity>(
                predicate: #Predicate { $0.isFavorite },
                sortBy: [SortDescriptor(\.name)]
            )
            let recipes = try modelContext.fetch(descriptor)
            return .success(recipes)
        } catch {
            return .failure(.databaseError("Failed to fetch favorite recipes"))
        }
    }

    func fetchByCategory(_ category: String) -> Result<[RecipeEntity], AppError> {
        do {
            let descriptor = FetchDescriptor<RecipeEntity>(
                predicate: #Predicate { $0.category == category },
                sortBy: [SortDescriptor(\.name)]
            )
            let recipes = try modelContext.fetch(descriptor)
            return .success(recipes)
        } catch {
            return .failure(.databaseError("Failed to fetch recipes by category"))
        }
    }

    // MARK: - Create & Delete

    func create(_ recipe: RecipeEntity) -> Result<Void, AppError> {
        modelContext.insert(recipe)
        return save()
    }

    func delete(_ recipe: RecipeEntity) -> Result<Void, AppError> {
        // Deleting cascades to manufacturing records; never take down a batch
        // that is still being produced.
        if recipe.hasInProgressManufacturing {
            return .failure(.validationError(String(localized: "This recipe has a batch in progress. Complete or cancel it first.")))
        }
        modelContext.delete(recipe)
        return save()
    }

    // MARK: - Update

    func updateBasicInfo(_ recipe: RecipeEntity, name: String, note: String, category: String?, batchSize: Int, batchUnit: String, templateType: GellingAgentType?) -> Result<Void, AppError> {
        recipe.name = name.trimmingCharacters(in: .whitespaces)
        recipe.note = note
        recipe.category = category?.isEmpty == false ? category?.trimmingCharacters(in: .whitespaces) : nil
        recipe.batchSize = batchSize
        recipe.batchUnit = batchUnit.isEmpty ? "pcs" : batchUnit.trimmingCharacters(in: .whitespaces)
        recipe.templateType = templateType
        return save()
    }

    func rebuildRelationships(_ recipe: RecipeEntity, steps: [RecipeStepInput], ingredients: [RecipeIngredientInput]) -> Result<Void, AppError> {
        // --- 1. Update Steps ---
        // RecipeStepInput has no IDs, so changed steps are recreated by order.
        // Manufacturing records reference steps by index, so only rebuild when
        // the steps actually changed (this also keeps dependencies/backupIds),
        // and never while a batch is mid-production.
        let stepsChanged = !Self.stepsMatch(recipe.sortedSteps, steps)
        if stepsChanged && recipe.hasInProgressManufacturing {
            return .failure(.validationError(String(localized: "Steps can't be changed while a batch is in progress. Complete or cancel it first.")))
        }

        if stepsChanged {
            // Remove old steps from context
            let oldSteps = recipe.steps
            for step in oldSteps {
                modelContext.delete(step)
            }
            recipe.steps.removeAll()
        }

        // Add new steps
        for (index, stepInput) in steps.enumerated() where stepsChanged {
            let step = RecipeStepEntity(
                title: stepInput.title,
                note: stepInput.note,
                time: stepInput.time,
                isTimerRequired: stepInput.isTimerRequired,
                order: index,
                requiredMeasurements: stepInput.requiredMeasurements,
                lineIdentifier: stepInput.lineIdentifier
            )
            step.recipe = recipe
            recipe.steps.append(step)
        }

        // --- 2. Update Ingredients ---
        // Remove old ingredients from context
        let oldIngredients = recipe.ingredients
        for ingredient in oldIngredients {
            modelContext.delete(ingredient)
        }
        recipe.ingredients.removeAll()

        // Add new ingredients
        for ingredientInput in ingredients {
            if let inventory = modelContext.model(for: ingredientInput.inventoryId) as? InventoryEntity {
                let ingredient = IngredientEntity(
                    inventoryItem: inventory,
                    quantity: ingredientInput.quantity,
                    unitSymbol: ingredientInput.unitSymbol,
                    note: ingredientInput.note,
                    recipe: recipe
                )
                recipe.ingredients.append(ingredient)
            }
        }

        // --- 3. Save Context ---
        // Explicitly saving here is CRITICAL to ensure temporary IDs are promoted
        // to permanent IDs before the UI tries to re-render.
        return save()
    }

    func duplicate(_ recipe: RecipeEntity) -> Result<RecipeEntity, AppError> {
        let newRecipe = recipe.clone(into: modelContext)

        switch save() {
        case .success:
            return .success(newRecipe)
        case .failure(let error):
            return .failure(error)
        }
    }

    // MARK: - Private

    private static func stepsMatch(_ existing: [RecipeStepEntity], _ inputs: [RecipeStepInput]) -> Bool {
        guard existing.count == inputs.count else { return false }
        return zip(existing, inputs).allSatisfy { step, input in
            step.title == input.title
                && step.note == input.note
                && step.time == input.time
                // RecipeEditViewModel loads isTimerRequired as `isTimerRequired || time > 0`
                && (step.isTimerRequired || step.time > 0) == input.isTimerRequired
                && step.requiredMeasurements == input.requiredMeasurements
                && step.lineIdentifier == input.lineIdentifier
        }
    }

    private func save() -> Result<Void, AppError> {
        do {
            try modelContext.save()
            return .success(())
        } catch {
            return .failure(.databaseError("Failed to save changes: \(error.localizedDescription)"))
        }
    }
}
