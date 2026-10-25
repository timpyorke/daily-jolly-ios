import Foundation
import SwiftData

@MainActor
final class CSVImportService {
    static let shared = CSVImportService()
    
    private init() {}
    
    /// Import inventory from CSV
    func importInventory(from url: URL, modelContext: ModelContext) -> Result<(Int, Int), AppError> {
        do {
            let data = try CSVEngine.shared.readText(from: url)
            let rows = CSVEngine.shared.parse(data)
            
            guard rows.count > 1 else { return .success((0, 0)) }
            
            let headers = rows[0].map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
            var importCount = 0
            var skippedCount = 0
            
            for i in 1..<rows.count {
                let row = rows[i]
                
                var name = ""
                var category: String?
                var unitSymbol = "g"
                var stock: Double = 0
                var minStock: Double = 0
                var unitPrice: Double = 0
                var phValue: Double?
                
                for (index, header) in headers.enumerated() {
                    guard index < row.count else { break }
                    let value = row[index].trimmingCharacters(in: .whitespaces)
                    
                    switch header {
                    case "name": name = value
                    case "category": category = value.isEmpty || value == "-" ? nil : value
                    case "unit": unitSymbol = value
                    case "stock": stock = Double(value) ?? 0
                    case "min stock": minStock = Double(value) ?? 0
                    case "unit price", "price": 
                        let cleanPrice = value.replacingOccurrences(of: "฿", with: "").replacingOccurrences(of: ",", with: "")
                        if let price = Double(cleanPrice) {
                            unitPrice = price
                        }
                    case "ph": 
                        if let ph = Double(value) {
                            phValue = ph
                        }
                    default: break
                    }
                }
                
                if !name.isEmpty {
                    let item = InventoryEntity(
                        name: name,
                        category: category,
                        unitSymbol: unitSymbol,
                        unitPrice: unitPrice,
                        stock: stock,
                        minStock: minStock,
                        phValue: phValue
                    )
                    modelContext.insert(item)
                    importCount += 1
                } else {
                    skippedCount += 1
                }
            }
            
            // Promote IDs by saving
            try modelContext.save()
            print("[CSVImportService] Imported \(importCount) inventory items. Skipped \(skippedCount) invalid rows.")
            return .success((importCount, skippedCount))
            
        } catch {
            // Don't leave half an import pending for autosave
            modelContext.rollback()
            return .failure(.databaseError("Import failed: \(error.localizedDescription)"))
        }
    }
    
    /// Import recipes from CSV (Basic info only)
    func importRecipes(from url: URL, modelContext: ModelContext) -> Result<(Int, Int), AppError> {
        do {
            let data = try CSVEngine.shared.readText(from: url)
            let rows = CSVEngine.shared.parse(data)
            
            guard rows.count > 1 else { return .success((0, 0)) }
            
            let headers = rows[0].map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
            var importCount = 0
            var skippedCount = 0
            
            for i in 1..<rows.count {
                let row = rows[i]
                
                var name = ""
                var category: String?
                var batchSize = 1
                var batchUnit = "pcs"
                
                for (index, header) in headers.enumerated() {
                    guard index < row.count else { break }
                    let value = row[index].trimmingCharacters(in: .whitespaces)
                    
                    switch header {
                    case "name": name = value
                    case "category": category = value.isEmpty || value == "-" ? nil : value
                    case "batch size": batchSize = Int(value) ?? 1
                    case "batch unit": batchUnit = value
                    default: break
                    }
                }
                
                if !name.isEmpty {
                    let recipe = RecipeEntity(
                        name: name,
                        category: category,
                        batchSize: batchSize,
                        batchUnit: batchUnit
                    )
                    modelContext.insert(recipe)
                    importCount += 1
                } else {
                    skippedCount += 1
                }
            }
            
            try modelContext.save()
            print("[CSVImportService] Imported \(importCount) recipes. Skipped \(skippedCount) invalid rows.")
            return .success((importCount, skippedCount))
            
        } catch {
            // Don't leave half an import pending for autosave
            modelContext.rollback()
            return .failure(.databaseError("Import failed: \(error.localizedDescription)"))
        }
    }
}
