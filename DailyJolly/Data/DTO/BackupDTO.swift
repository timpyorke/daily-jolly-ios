import Foundation

struct BackupDocument: Codable {
    let schemaVersion: Int
    let createdAt: Date
    let appVersion: String
    let customUnits: [CustomUnitDTO]
    let inventory: [InventoryDTO]
    let recipes: [RecipeDTO]
    let manufacturing: [ManufacturingDTO]

    init(
        customUnits: [CustomUnitDTO],
        inventory: [InventoryDTO],
        recipes: [RecipeDTO],
        manufacturing: [ManufacturingDTO]
    ) {
        self.schemaVersion = 1
        self.createdAt = Date.now
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        self.customUnits = customUnits
        self.inventory = inventory
        self.recipes = recipes
        self.manufacturing = manufacturing
    }
}

struct CustomUnitDTO: Codable {
    let backupId: String
    let symbol: String
    let name: String
    let createdAt: Date
}

struct InventoryDTO: Codable {
    let backupId: String
    let name: String
    let category: String?
    let unitSymbol: String
    let unitPrice: Double
    let stock: Double
    let minStock: Double
    let phValue: Double?
    let createdAt: Date
}

struct RecipeDTO: Codable {
    let backupId: String
    let name: String
    let note: String
    let category: String?
    let isFavorite: Bool
    let batchSize: Int
    let batchUnit: String
    let templateTypeRawValue: String?
    let createdAt: Date
    let steps: [RecipeStepDTO]
    let ingredients: [IngredientDTO]
}

struct RecipeStepDTO: Codable {
    let backupId: String
    let title: String
    let note: String
    let time: Int
    let isTimerRequired: Bool
    let order: Int
    let requiredMeasurementRawValues: [String]
    let lineIdentifier: String?
    let dependencyBackupIds: [String]
}

struct IngredientDTO: Codable {
    let backupId: String
    let quantity: Double
    let unitSymbol: String
    let note: String?
    let batchPhValue: Double?
    let inventoryBackupId: String
}

struct ManufacturingDTO: Codable {
    let backupId: String
    let batchNumber: String
    let statusRawValue: String
    let currentStepIndex: Int
    let completedStepIndices: [Int]
    let quantity: Int
    let startedAt: Date
    let completedAt: Date?
    let stepCompletionTimes: [Date]
    let stepNotes: [String]
    let actualOutput: Double?
    let recipeBackupId: String
    let stepLogs: [StepLogDTO]
    let measurements: [MeasurementLogDTO]
    // Optional so backups made before photos were included still decode
    let images: [ManufacturingImageDTO]?
}

struct StepLogDTO: Codable {
    let backupId: String
    let stepIndex: Int
    let note: String
    let startedAt: Date?
    let completedAt: Date?
    let createdAt: Date
}

struct ManufacturingImageDTO: Codable {
    let backupId: String
    let imageData: Data
    let stepIndex: Int?
    let createdAt: Date
}

struct MeasurementLogDTO: Codable {
    let backupId: String
    let typeRawValue: String
    let value: Double
    let timestamp: Date
    let stepIndex: Int
}
