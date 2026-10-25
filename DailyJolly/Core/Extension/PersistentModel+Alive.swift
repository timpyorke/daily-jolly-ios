import SwiftData

extension PersistentModel {
    /// False once the model has been deleted (and saved) or detached from its context.
    /// Reading attributes of such a model crashes SwiftData, so check this before rendering
    /// models held outside of `@Query`.
    var isAlive: Bool {
        modelContext != nil && !isDeleted
    }
}
