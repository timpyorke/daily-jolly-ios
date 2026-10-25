import Foundation
import SwiftData
import UIKit

@Observable
@MainActor
final class BackupSyncViewModel {

    // MARK: - State

    private(set) var isSignedIn = false
    private(set) var userEmail: String?
    private(set) var availableBackups: [DriveFile] = []
    private(set) var isBackingUp = false
    private(set) var isRestoring = false
    private(set) var isLoadingBackups = false
    var showRestoreConfirmation = false
    private(set) var selectedBackupForRestore: DriveFile?
    var errorMessage: String?
    var showError = false
    var showRestoreSuccess = false

    var lastBackupDate: Date? {
        AppSettings.shared.lastBackupDate
    }

    var autoBackupOnLaunch: Bool {
        get { AppSettings.shared.autoBackupOnLaunch }
        set { AppSettings.shared.autoBackupOnLaunch = newValue }
    }

    // MARK: - Dependencies

    private var modelContext: ModelContext?
    private let backupService = BackupService.shared

    // MARK: - Setup

    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
        refreshSignInState()
        if isSignedIn {
            Task { await loadAvailableBackups() }
        }
    }

    // MARK: - Auth

    func signIn() {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
              let rootVC = windowScene.windows.first?.rootViewController else { return }

        Task {
            do {
                try await backupService.signIn(presentingViewController: rootVC)
                refreshSignInState()
                await loadAvailableBackups()
            } catch {
                handleError(error)
            }
        }
    }

    func signOut() {
        backupService.signOut()
        refreshSignInState()
        availableBackups = []
    }

    private func refreshSignInState() {
        isSignedIn = backupService.isSignedIn
        userEmail = backupService.currentUserEmail
    }

    // MARK: - Backup

    func performBackup() {
        guard let modelContext, !isBackingUp else { return }
        isBackingUp = true
        Task {
            defer { isBackingUp = false }
            do {
                _ = try await backupService.performBackup(modelContext: modelContext)
                await loadAvailableBackups()
            } catch {
                handleError(error)
            }
        }
    }

    // MARK: - List Backups

    func loadAvailableBackups() async {
        guard isSignedIn, !isLoadingBackups else { return }
        isLoadingBackups = true
        defer { isLoadingBackups = false }
        do {
            availableBackups = try await backupService.listBackups()
        } catch {
            handleError(error)
        }
    }

    // MARK: - Restore

    func selectBackupForRestore(_ file: DriveFile) {
        selectedBackupForRestore = file
        showRestoreConfirmation = true
    }

    func confirmRestore() {
        guard let modelContext, let file = selectedBackupForRestore, !isRestoring else { return }
        isRestoring = true
        Task {
            defer { isRestoring = false }
            do {
                try await backupService.performRestore(fileId: file.id, modelContext: modelContext)
                showRestoreSuccess = true
            } catch {
                handleError(error)
            }
        }
    }

    // MARK: - Error Handling

    private func handleError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
}
