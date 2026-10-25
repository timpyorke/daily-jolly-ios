import Foundation
import SwiftData

@MainActor
final class BackupSerializationService {
    static let shared = BackupSerializationService()
    private init() {}

    // MARK: - Encode

    func encode(modelContext: ModelContext) throws -> BackupDocument {
        let customUnits = try fetchAll(CustomUnitEntity.self, context: modelContext)
        let inventory = try fetchAll(InventoryEntity.self, context: modelContext)
        let recipes = try fetchAll(RecipeEntity.self, context: modelContext)
        let manufacturing = try fetchAll(ManufacturingEntity.self, context: modelContext)

        for e in customUnits where e.backupId.isEmpty { e.backupId = UUID().uuidString }
        for e in inventory where e.backupId.isEmpty { e.backupId = UUID().uuidString }
        for e in recipes {
            if e.backupId.isEmpty { e.backupId = UUID().uuidString }
            for s in e.steps where s.backupId.isEmpty { s.backupId = UUID().uuidString }
            for i in e.ingredients where i.backupId.isEmpty { i.backupId = UUID().uuidString }
        }
        for m in manufacturing {
            if m.backupId.isEmpty { m.backupId = UUID().uuidString }
            for l in m.stepLogs where l.backupId.isEmpty { l.backupId = UUID().uuidString }
            for meas in m.measurements where meas.backupId.isEmpty { meas.backupId = UUID().uuidString }
            for img in m.images where img.backupId.isEmpty { img.backupId = UUID().uuidString }
        }

        try modelContext.save()

        return BackupDocument(
            customUnits: customUnits.map(\.dto),
            inventory: inventory.map(\.dto),
            recipes: recipes.map(\.dto),
            manufacturing: manufacturing.map(\.dto)
        )
    }

    // MARK: - Restore

    func restore(from document: BackupDocument, modelContext: ModelContext) throws {
        guard document.schemaVersion == 1 else {
            throw AppError.backupError("Unsupported backup version: \(document.schemaVersion)")
        }

        // clearAll only marks deletions; if anything below throws, those pending
        // deletions would otherwise be autosaved later and wipe the user's data.
        do {
            try clearAll(modelContext: modelContext)
            try insertAll(from: document, modelContext: modelContext)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func insertAll(from document: BackupDocument, modelContext: ModelContext) throws {
        // Pass 1: root entities with no cross-references
        var inventoryMap: [String: InventoryEntity] = [:]
        for dto in document.customUnits {
            let entity = CustomUnitEntity(symbol: dto.symbol, name: dto.name)
            entity.backupId = dto.backupId
            entity.createdAt = dto.createdAt
            modelContext.insert(entity)
        }
        for dto in document.inventory {
            let entity = InventoryEntity(
                name: dto.name,
                category: dto.category,
                unitSymbol: dto.unitSymbol,
                unitPrice: dto.unitPrice,
                stock: dto.stock,
                minStock: dto.minStock,
                phValue: dto.phValue
            )
            entity.backupId = dto.backupId
            entity.createdAt = dto.createdAt
            modelContext.insert(entity)
            inventoryMap[dto.backupId] = entity
        }

        // Pass 2: recipes + steps (first shell, then wire dependencies)
        var stepMap: [String: RecipeStepEntity] = [:]
        var recipeMap: [String: RecipeEntity] = [:]
        for dto in document.recipes {
            let recipe = RecipeEntity(
                name: dto.name,
                note: dto.note,
                category: dto.category,
                batchSize: dto.batchSize,
                batchUnit: dto.batchUnit
            )
            recipe.backupId = dto.backupId
            recipe.isFavorite = dto.isFavorite
            recipe.templateTypeRawValue = dto.templateTypeRawValue
            recipe.createdAt = dto.createdAt
            modelContext.insert(recipe)
            recipeMap[dto.backupId] = recipe

            // Create steps
            for stepDTO in dto.steps {
                let step = RecipeStepEntity(
                    title: stepDTO.title,
                    note: stepDTO.note,
                    time: stepDTO.time,
                    isTimerRequired: stepDTO.isTimerRequired,
                    order: stepDTO.order,
                    requiredMeasurements: stepDTO.requiredMeasurementRawValues.compactMap { MeasurementType(rawValue: $0) },
                    lineIdentifier: stepDTO.lineIdentifier
                )
                step.backupId = stepDTO.backupId
                step.recipe = recipe
                recipe.steps.append(step)
                stepMap[stepDTO.backupId] = step
            }

            // Create ingredients
            for ingDTO in dto.ingredients {
                guard let inventoryItem = inventoryMap[ingDTO.inventoryBackupId] else { continue }
                let ingredient = IngredientEntity(
                    inventoryItem: inventoryItem,
                    quantity: ingDTO.quantity,
                    unitSymbol: ingDTO.unitSymbol,
                    note: ingDTO.note,
                    batchPhValue: ingDTO.batchPhValue,
                    recipe: recipe
                )
                ingredient.backupId = ingDTO.backupId
                recipe.ingredients.append(ingredient)
            }
        }

        // Pass 3: wire step dependencies (self-referential)
        for recipeDTO in document.recipes {
            for stepDTO in recipeDTO.steps {
                guard let step = stepMap[stepDTO.backupId] else { continue }
                step.dependencies = stepDTO.dependencyBackupIds.compactMap { stepMap[$0] }
            }
        }

        // Pass 4: manufacturing records
        for dto in document.manufacturing {
            guard let recipe = recipeMap[dto.recipeBackupId] else { continue }
            let m = ManufacturingEntity(
                recipe: recipe,
                quantity: dto.quantity,
                batchNumber: dto.batchNumber
            )
            m.backupId = dto.backupId
            m.status = ManufacturingStatus(rawValue: dto.statusRawValue) ?? .completed
            m.currentStepIndex = dto.currentStepIndex
            m.completedStepIndices = dto.completedStepIndices
            m.startedAt = dto.startedAt
            m.completedAt = dto.completedAt
            m.stepCompletionTimes = dto.stepCompletionTimes
            m.stepNotes = dto.stepNotes
            m.actualOutput = dto.actualOutput
            modelContext.insert(m)

            for logDTO in dto.stepLogs {
                let log = ManufacturingStepLogEntity(
                    stepIndex: logDTO.stepIndex,
                    note: logDTO.note,
                    startedAt: logDTO.startedAt,
                    completedAt: logDTO.completedAt,
                    manufacturing: m
                )
                log.backupId = logDTO.backupId
                log.createdAt = logDTO.createdAt
                m.stepLogs.append(log)
            }

            for measDTO in dto.measurements {
                let meas = MeasurementLogEntity(
                    type: MeasurementType(rawValue: measDTO.typeRawValue) ?? .temp,
                    value: measDTO.value,
                    stepIndex: measDTO.stepIndex,
                    manufacturing: m
                )
                meas.backupId = measDTO.backupId
                meas.timestamp = measDTO.timestamp
                m.measurements.append(meas)
            }

            for imageDTO in dto.images ?? [] {
                let image = ManufacturingImageEntity(
                    imageData: imageDTO.imageData,
                    stepIndex: imageDTO.stepIndex,
                    manufacturing: m
                )
                image.backupId = imageDTO.backupId
                image.createdAt = imageDTO.createdAt
                m.images.append(image)
            }
        }
    }

    // MARK: - Helpers

    private func fetchAll<T: PersistentModel>(_ type: T.Type, context: ModelContext) throws -> [T] {
        let descriptor = FetchDescriptor<T>()
        return try context.fetch(descriptor)
    }

    private func clearAll(modelContext: ModelContext) throws {
        let manufacturing = try fetchAll(ManufacturingEntity.self, context: modelContext)
        for m in manufacturing { modelContext.delete(m) }

        let recipes = try fetchAll(RecipeEntity.self, context: modelContext)
        for r in recipes { modelContext.delete(r) }

        let inventory = try fetchAll(InventoryEntity.self, context: modelContext)
        for i in inventory { modelContext.delete(i) }

        let units = try fetchAll(CustomUnitEntity.self, context: modelContext)
        for u in units { modelContext.delete(u) }
    }
}

// MARK: - DTO Conversions

private extension CustomUnitEntity {
    var dto: CustomUnitDTO {
        CustomUnitDTO(backupId: backupId, symbol: symbol, name: name, createdAt: createdAt)
    }
}

private extension InventoryEntity {
    var dto: InventoryDTO {
        InventoryDTO(
            backupId: backupId,
            name: name,
            category: category,
            unitSymbol: unitSymbol,
            unitPrice: unitPrice,
            stock: stock,
            minStock: minStock,
            phValue: phValue,
            createdAt: createdAt
        )
    }
}

private extension RecipeEntity {
    var dto: RecipeDTO {
        RecipeDTO(
            backupId: backupId,
            name: name,
            note: note,
            category: category,
            isFavorite: isFavorite,
            batchSize: batchSize,
            batchUnit: batchUnit,
            templateTypeRawValue: templateTypeRawValue,
            createdAt: createdAt,
            steps: steps.map(\.dto),
            ingredients: ingredients.map(\.dto)
        )
    }
}

private extension RecipeStepEntity {
    var dto: RecipeStepDTO {
        RecipeStepDTO(
            backupId: backupId,
            title: title,
            note: note,
            time: time,
            isTimerRequired: isTimerRequired,
            order: order,
            requiredMeasurementRawValues: requiredMeasurementRawValues,
            lineIdentifier: lineIdentifier,
            dependencyBackupIds: dependencies.map(\.backupId)
        )
    }
}

private extension IngredientEntity {
    var dto: IngredientDTO {
        IngredientDTO(
            backupId: backupId,
            quantity: quantity,
            unitSymbol: unitSymbol,
            note: note,
            batchPhValue: batchPhValue,
            inventoryBackupId: inventoryItem.backupId
        )
    }
}

private extension ManufacturingEntity {
    var dto: ManufacturingDTO {
        ManufacturingDTO(
            backupId: backupId,
            batchNumber: batchNumber,
            statusRawValue: status.rawValue,
            currentStepIndex: currentStepIndex,
            completedStepIndices: completedStepIndices,
            quantity: quantity,
            startedAt: startedAt,
            completedAt: completedAt,
            stepCompletionTimes: stepCompletionTimes,
            stepNotes: stepNotes,
            actualOutput: actualOutput,
            recipeBackupId: recipe.backupId,
            stepLogs: stepLogs.map(\.dto),
            measurements: measurements.map(\.dto),
            images: images.map(\.dto)
        )
    }
}

private extension ManufacturingStepLogEntity {
    var dto: StepLogDTO {
        StepLogDTO(
            backupId: backupId,
            stepIndex: stepIndex,
            note: note,
            startedAt: startedAt,
            completedAt: completedAt,
            createdAt: createdAt
        )
    }
}

private extension ManufacturingImageEntity {
    var dto: ManufacturingImageDTO {
        ManufacturingImageDTO(
            backupId: backupId,
            imageData: imageData,
            stepIndex: stepIndex,
            createdAt: createdAt
        )
    }
}

private extension MeasurementLogEntity {
    var dto: MeasurementLogDTO {
        MeasurementLogDTO(
            backupId: backupId,
            typeRawValue: typeRawValue,
            value: value,
            timestamp: timestamp,
            stepIndex: stepIndex
        )
    }
}
