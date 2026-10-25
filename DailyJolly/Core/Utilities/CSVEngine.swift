import Foundation

/// Shared utility for CSV parsing and formatting.
final class CSVEngine {
    
    static let shared = CSVEngine()
    private init() {}
    
    /// Read a CSV file as text. Handles UTF-8 (with or without BOM), UTF-16 with BOM,
    /// and Thai Windows/TIS-620 files as saved by Excel.
    func readText(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)

        let text: String?
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            text = String(data: data, encoding: .utf16)
        } else {
            let thaiEncoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.dosThai.rawValue)
            ))
            text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: thaiEncoding)
        }

        guard var text else {
            throw AppError.validationError(String(localized: "Unsupported file encoding. Please save the CSV as UTF-8."))
        }
        // A UTF-8 BOM would otherwise end up glued to the first header name
        if text.hasPrefix("\u{FEFF}") {
            text.removeFirst()
        }
        return text
    }

    /// Parse a CSV string into rows and columns.
    /// Quoted fields may contain commas, escaped quotes ("") and line breaks.
    func parse(_ data: String) -> [[String]] {
        var result: [[String]] = []
        var columns: [String] = []
        var currentColumn = ""
        var insideQuotes = false

        func endRow() {
            columns.append(currentColumn)
            // Skip blank lines
            if !(columns.count == 1 && columns[0].trimmingCharacters(in: .whitespaces).isEmpty) {
                result.append(columns)
            }
            columns = []
            currentColumn = ""
        }

        // Iterate unicode scalars so "\r\n" is seen as two separate characters
        let scalars = Array(data.unicodeScalars)
        var i = 0
        while i < scalars.count {
            let char = scalars[i]

            if insideQuotes {
                if char == "\"" {
                    if i + 1 < scalars.count && scalars[i + 1] == "\"" {
                        currentColumn.unicodeScalars.append("\"")
                        i += 1
                    } else {
                        insideQuotes = false
                    }
                } else {
                    currentColumn.unicodeScalars.append(char)
                }
            } else if char == "\"" {
                insideQuotes = true
            } else if char == "," {
                columns.append(currentColumn)
                currentColumn = ""
            } else if char == "\n" || char == "\r" {
                if char == "\r" && i + 1 < scalars.count && scalars[i + 1] == "\n" {
                    i += 1
                }
                endRow()
            } else {
                currentColumn.unicodeScalars.append(char)
            }
            i += 1
        }

        if !currentColumn.isEmpty || !columns.isEmpty {
            endRow()
        }

        return result
    }
    
    /// Format a row of values into a CSV line
    func formatRow(_ values: [String]) -> String {
        values.map { escape($0) }.joined(separator: ",")
    }
    
    /// Escape a single value for CSV
    func escape(_ text: String) -> String {
        var escaped = text.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") || escaped.contains("\r") {
            escaped = "\"\(escaped)\""
        }
        return escaped
    }
}
