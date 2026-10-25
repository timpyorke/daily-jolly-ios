import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class HomeViewModel {

    // MARK: - State

    // Home stays alive in the TabView while other screens delete records
    // (recipe delete cascade, clear all data, backup restore). Rendering a
    // deleted model crashes SwiftData, so the public accessors drop any model
    // that has been detached from its context.
    private var loadedActiveManufacturing: [ManufacturingEntity] = []
    private var loadedCompletedManufacturing: [ManufacturingEntity] = []
    private var loadedInventory: [InventoryEntity] = []

    var activeManufacturing: [ManufacturingEntity] { loadedActiveManufacturing.filter(\.isAlive) }
    var completedManufacturing: [ManufacturingEntity] { loadedCompletedManufacturing.filter(\.isAlive) }
    var allInventory: [InventoryEntity] { loadedInventory.filter(\.isAlive) }
    var selectedRecipe: RecipeEntity?

    // MARK: - UI State

    var showRecipeSelection = false
    var showInsufficientAlert = false
    var isLoading = false
    var isSaving = false
    var errorMessage: String?
    var showError = false

    // MARK: - Dependencies

    private var manufacturingRepository: ManufacturingRepository?
    private var inventoryRepository: InventoryRepository?
    private(set) var isSetup = false

    // MARK: - Computed

    var lowStockItems: [InventoryEntity] {
        allInventory.filter { $0.isLowStock }.sorted { $0.stockLevel < $1.stockLevel }
    }

    var totalBatches: Int {
        activeManufacturing.count + completedManufacturing.count
    }

    var activeBatchesCount: Int {
        activeManufacturing.count
    }

    var completedBatchesCount: Int {
        completedManufacturing.count
    }

    var totalInventoryItems: Int {
        allInventory.count
    }

    var totalInventoryValue: Double {
        allInventory.reduce(0) { $0 + ($1.stock * $1.unitPrice) }
    }

    var lowStockItemsCount: Int {
        lowStockItems.count
    }

    var totalActiveBatchesCost: Double {
        activeManufacturing.reduce(0) { $0 + $1.totalCost }
    }

    var totalCompletedBatchesCost: Double {
        completedManufacturing.reduce(0) { $0 + $1.totalCost }
    }

    var totalBatchesCost: Double {
        totalActiveBatchesCost + totalCompletedBatchesCost
    }

    // MARK: - Setup

    func setup(modelContext: ModelContext) {
        self.manufacturingRepository = ManufacturingRepository(modelContext: modelContext)
        self.inventoryRepository = InventoryRepository(modelContext: modelContext)
        self.isSetup = true
        loadData()
    }

    // MARK: - Actions

    func loadData() {
        print("[HomeViewModel] 🔄 Loading data...")
        isLoading = true
        defer { isLoading = false }

        // Fetch active manufacturing (silent fail on error)
        if let result = manufacturingRepository?.fetchActive() {
            switch result {
            case .success(let items):
                loadedActiveManufacturing = items
                print("[HomeViewModel] ✅ Loaded \(items.count) active manufacturing")
            case .failure(let error):
                print("[HomeViewModel] ❌ Failed to load active manufacturing: \(error)")
                loadedActiveManufacturing = []
            }
        }

        // Fetch completed manufacturing (silent fail on error)
        if let result = manufacturingRepository?.fetchCompleted() {
            switch result {
            case .success(let items):
                loadedCompletedManufacturing = items
                print("[HomeViewModel] ✅ Loaded \(items.count) completed manufacturing")
            case .failure(let error):
                print("[HomeViewModel] ❌ Failed to load completed manufacturing: \(error)")
                loadedCompletedManufacturing = []
            }
        }

        // Fetch inventory (silent fail on error)
        if let result = inventoryRepository?.fetchAll() {
            switch result {
            case .success(let items):
                loadedInventory = items
                print("[HomeViewModel] ✅ Loaded \(items.count) inventory items")
            case .failure(let error):
                print("[HomeViewModel] ❌ Failed to load inventory: \(error)")
                loadedInventory = []
            }
        }

        print("[HomeViewModel] 📊 Summary - Active: \(activeManufacturing.count), Completed: \(completedManufacturing.count), Inventory: \(allInventory.count)")
    }

    func handleRecipeSelection(_ recipe: RecipeEntity) -> Bool {
        if recipe.hasEnoughInventory {
            return true  // Proceed
        } else {
            selectedRecipe = recipe
            return false  // Show warning
        }
    }

    func startManufacturing(with recipe: RecipeEntity) -> PersistentIdentifier? {
        guard let manufacturingRepository else { return nil }

        isSaving = true
        defer { isSaving = false }

        // Include cancelled batches so their numbers are never reused
        let existingBatches = (try? manufacturingRepository.fetchAll().get())
            ?? (activeManufacturing + completedManufacturing)
        let batchNumber = ManufacturingEntity.generateBatchNumber(
            existingBatches: existingBatches
        )
        let manufacturing = ManufacturingEntity(recipe: recipe, batchNumber: batchNumber)

        switch manufacturingRepository.create(manufacturing) {
        case .success:
            loadData()
            return manufacturing.persistentModelID
        case .failure(let error):
            handleError(error)
            return nil
        }
    }

    // MARK: - Error Handling

    private func handleError(_ error: AppError) {
        errorMessage = error.localizedDescription
        showError = true
    }
}
