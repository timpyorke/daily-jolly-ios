import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class ManufacturingViewModel {

    // MARK: - State

    private(set) var manufacturing: ManufacturingEntity?

    // MARK: - UI State

    var showCancelAlert = false
    var isLoading = false
    var errorMessage: String?
    var showError = false

    // MARK: - Dependencies

    private var repository: ManufacturingRepository?
    private var pendingNoteSave: Task<Void, Never>?

    // MARK: - Setup

    func setup(modelContext: ModelContext, id: PersistentIdentifier) {
        self.repository = ManufacturingRepository(modelContext: modelContext)
        loadManufacturing(id: id)
    }

    // MARK: - Actions

    func loadManufacturing(id: PersistentIdentifier) {
        guard let repository else { return }

        isLoading = true
        defer { isLoading = false }

        switch repository.fetch(by: id) {
        case .success(let item):
            manufacturing = item
        case .failure(let error):
            print("[ManufacturingViewModel] Failed to load manufacturing: \(error)")
            manufacturing = nil
        }
    }

    func completeStep(at index: Int, note: String = "") {
        guard let manufacturing = manufacturing, let repository = repository else {
            print("[ManufacturingViewModel] ERROR: missing manufacturing or repository")
            return
        }

        print("[ManufacturingViewModel] Completing step \(index) with note: \(note)")

        manufacturing.completeStep(at: index, note: note)

        let isCompleted = manufacturing.isCompleted
        print("[ManufacturingViewModel] After completion - isCompleted: \(isCompleted)")

        // Deduct inventory if completed
        if isCompleted {
            deductInventory(for: manufacturing)
        }

        // Save the changes to the database
        switch repository.update() {
        case .success:
            print("[ManufacturingViewModel] ✅ Successfully saved to database")
        case .failure(let error):
            print("[ManufacturingViewModel] ❌ Failed to save: \(error)")
            handleError(error)
        }
    }

    func completeCurrentStep(note: String = "") {
        guard let manufacturing else { return }
        completeStep(at: manufacturing.currentStepIndex, note: note)
    }

    func updateStepNote(at index: Int, note: String) {
        guard let manufacturing else { return }
        manufacturing.setStepNote(at: index, note: note)

        // Called on every keystroke; batch the disk writes
        pendingNoteSave?.cancel()
        pendingNoteSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            _ = self?.repository?.update()
        }
    }

    func startStep(at index: Int) {
        guard let manufacturing, let repository else { return }
        manufacturing.startStep(at: index)
        _ = repository.update()
    }

    func recordStepTime(at index: Int) {
        guard let manufacturing, let repository else { return }
        manufacturing.recordStepTime(at: index)
        _ = repository.update()
    }

    func logMeasurement(at stepIndex: Int, type: MeasurementType, value: Double) {
        guard let manufacturing, let repository else { return }
        manufacturing.logMeasurement(type: type, value: value, stepIndex: stepIndex)
        _ = repository.update()
    }

    func updateActualOutput(_ value: Double) {
        guard let manufacturing, let repository else { return }
        manufacturing.actualOutput = value
        _ = repository.update()
    }

    func addImageData(_ data: Data, stepIndex: Int? = nil) {
        guard let manufacturing, let repository else { return }
        // Library/camera photos can be 10+ MB; store a bounded JPEG instead
        let storedData = ImageDownsampler.storageJPEG(from: data) ?? data
        manufacturing.addImage(storedData, stepIndex: stepIndex)
        _ = repository.update()
    }

    func removeImage(_ image: ManufacturingImageEntity) {
        guard let manufacturing, let repository else { return }
        manufacturing.images.removeAll { $0.persistentModelID == image.persistentModelID }
        _ = repository.update()
    }

    private func deductInventory(for manufacturing: ManufacturingEntity) {
        print("[ManufacturingViewModel] 📦 Deducting inventory for \(manufacturing.quantity) batch(es)")

        let recipe = manufacturing.recipe
        for ingredient in recipe.ingredients {
            let quantityToDeduct = ingredient.quantityInBaseUnit * Double(manufacturing.quantity)
            let inventoryItem = ingredient.inventoryItem
            let oldStock = inventoryItem.stock

            // Prevent stock from dropping below 0
            inventoryItem.stock = max(0, inventoryItem.stock - quantityToDeduct)

            print("[ManufacturingViewModel]   - \(inventoryItem.name): \(oldStock) → \(inventoryItem.stock) \(inventoryItem.displaySymbol) (-\(quantityToDeduct))")
        }

        print("[ManufacturingViewModel] ✅ Inventory deducted successfully")
    }

    func cancelManufacturing(onComplete: () -> Void) {
        guard let manufacturing, let repository else { return }
        manufacturing.status = .cancelled

        // Save the changes to the database
        switch repository.update() {
        case .success:
            onComplete()
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
