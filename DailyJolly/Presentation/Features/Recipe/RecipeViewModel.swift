import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class RecipeViewModel {

    // MARK: - State

    private(set) var recipes: [RecipeEntity] = []
    var searchText: String = ""

    // MARK: - UI State

    var isLoading = false
    var isDeleting = false
    var errorMessage: String?
    var showError = false

    // MARK: - Dependencies

    private var repository: RecipeRepository?

    // MARK: - Computed

    var filteredRecipes: [RecipeEntity] {
        if searchText.isEmpty {
            return recipes
        }
        return recipes.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: - Setup

    func setup(modelContext: ModelContext) {
        self.repository = RecipeRepository(modelContext: modelContext)
        loadRecipes()
    }

    // MARK: - Actions

    func loadRecipes() {
        guard let repository else { return }

        isLoading = true
        defer { isLoading = false }

        switch repository.fetchAll() {
        case .success(let items):
            recipes = items
        case .failure(let error):
            print("[RecipeViewModel] Failed to load recipes: \(error)")
            recipes = []
        }
    }

    func toggleFavorite(_ recipe: RecipeEntity) {
        recipe.isFavorite.toggle()
        loadRecipes()
    }

    func duplicateRecipe(_ recipe: RecipeEntity) {
        guard let repository else { return }

        isLoading = true
        defer { isLoading = false }

        switch repository.duplicate(recipe) {
        case .success:
            loadRecipes()
        case .failure(let error):
            handleError(error)
        }
    }

    func deleteRecipe(_ recipe: RecipeEntity) {
        guard let repository else { return }

        isDeleting = true
        defer { isDeleting = false }

        switch repository.delete(recipe) {
        case .success:
            loadRecipes()
        case .failure(let error):
            handleError(error)
        }
    }

    // MARK: - Error Handling

    private func handleError(_ error: AppError) {
        errorMessage = error.localizedDescription
        showError = true
    }
}
