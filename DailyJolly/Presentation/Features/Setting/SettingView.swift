import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = SettingViewModel()

    @Query(sort: \CustomUnitEntity.name)
    private var customUnits: [CustomUnitEntity]

    @State private var showPinSetup = false
    @State private var showPinVerify = false
    @State private var showInventoryPicker = false
    @State private var showRecipePicker = false

    var body: some View {
        Form {
            appearanceSection
            languageSection
            permissionsSection
            customUnitsSection
            importSection
            exportSection
            cloudBackupSection
            dataSection
        }
        .fileImporter(
            isPresented: $showInventoryPicker,
            allowedContentTypes: [.commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task {
                        // Files already inside the sandbox return false here but are
                        // still readable, so import either way and let errors surface
                        let isAccessing = url.startAccessingSecurityScopedResource()
                        defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }
                        viewModel.importInventory(from: url, modelContext: modelContext)
                    }
                }
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
                viewModel.showError = true
            }
        }
        .fileImporter(
            isPresented: $showRecipePicker,
            allowedContentTypes: [.commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task {
                        // Files already inside the sandbox return false here but are
                        // still readable, so import either way and let errors surface
                        let isAccessing = url.startAccessingSecurityScopedResource()
                        defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }
                        viewModel.importRecipes(from: url, modelContext: modelContext)
                    }
                }
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
                viewModel.showError = true
            }
        }
        .alert(String(localized: "Import Result"), isPresented: $viewModel.showImportSuccess) {
            Button(String(localized: "OK")) { }
        } message: {
            if viewModel.skippedCount > 0 {
                Text(String(localized: "Successfully imported \(viewModel.importCount) items.\nSkipped \(viewModel.skippedCount) invalid rows."))
            } else {
                Text(String(localized: "Successfully imported \(viewModel.importCount) items."))
            }
        }
        .sheet(isPresented: $showPinSetup) {
            PinEntryView(mode: .setup) { newPin in
                viewModel.settings.recipePin = newPin
                viewModel.settings.isRecipeEditLocked = true
            }
        }
        .sheet(isPresented: $showPinVerify) {
            PinEntryView(mode: .verify) { _ in
                // Success is handled inside PinEntryView for simplicity in this implementation
                // but we can also use the callback to toggle the state
                viewModel.settings.isRecipeEditLocked = false
            }
        }
        .sheet(isPresented: $viewModel.showExportSheet) {
            if let url = viewModel.exportURL {
                ShareSheet(items: [url])
            }
        }
        .sheet(isPresented: $viewModel.showAddUnitSheet) {
            AddCustomUnitSheet()
        }
        .alert(String(localized: "Clear All Data"), isPresented: $viewModel.showClearDataAlert) {
            Button(String(localized: "Cancel"), role: .cancel) { }
            Button(String(localized: "Clear"), role: .destructive) {
                viewModel.clearAllData()
            }
        } message: {
            Text(String(localized: "This will delete all recipes, inventory, and manufacturing data. This action cannot be undone."))
        }
        .alert(String(localized: "Restart Required"), isPresented: $viewModel.showRestartAlert) {
            Button(String(localized: "OK")) { }
        } message: {
            Text(String(localized: "Please restart the app to apply the language change."))
        }
        .onAppear {
            viewModel.setup(modelContext: modelContext)
        }
    }

    // MARK: - Appearance Section

    private var appearanceSection: some View {
        Section {
            Picker(selection: Bindable(viewModel.settings).theme) {
                ForEach(AppTheme.allCases) { theme in
                    Label(theme.displayName, systemImage: theme.icon)
                        .tag(theme)
                }
            } label: {
                Label(String(localized: "Theme"), systemImage: "paintbrush.fill")
            }
        } header: {
            Text(String(localized: "Appearance"))
        }
    }

    // MARK: - Language Section

    private var languageSection: some View {
        Section {
            Picker(selection: Bindable(viewModel.settings).language) {
                ForEach(AppLanguage.allCases) { lang in
                    Text("\(lang.flag) \(lang.displayName)")
                        .tag(lang)
                }
            } label: {
                Label(String(localized: "Language"), systemImage: "globe")
            }
            .onChange(of: viewModel.settings.language) { _, _ in
                viewModel.showRestartAlert = true
            }
        } header: {
            Text(String(localized: "Language"))
        } footer: {
            Text(String(localized: "Restart required to apply language change"))
        }
    }

    // MARK: - Permissions Section

    private var permissionsSection: some View {
        Section {
            Button {
                if viewModel.settings.isRecipeEditLocked {
                    showPinVerify = true
                } else {
                    if viewModel.settings.recipePin == nil {
                        showPinSetup = true
                    } else {
                        viewModel.settings.isRecipeEditLocked = true
                    }
                }
            } label: {
                HStack {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "Lock Recipe Editing"))
                            Text(String(localized: "Prevent accidental changes to recipes"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: viewModel.settings.isRecipeEditLocked ? "lock.fill" : "lock.open.fill")
                            .foregroundStyle(viewModel.settings.isRecipeEditLocked ? .orange : .green)
                    }
                    
                    Spacer()
                    
                    Text(viewModel.settings.isRecipeEditLocked ? String(localized: "Locked") : String(localized: "Unlocked"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)

            if !viewModel.settings.isRecipeEditLocked && viewModel.settings.recipePin != nil {
                Button {
                    showPinSetup = true
                } label: {
                    Label(String(localized: "Change PIN"), systemImage: "key.fill")
                }
            }
        } header: {
            Text(String(localized: "Permissions"))
        }
    }

    // MARK: - Custom Units Section

    private var customUnitsSection: some View {
        Section {
            ForEach(customUnits, id: \.persistentModelID) { unit in
                HStack {
                    Text(unit.name)
                    Spacer()
                    Text(unit.symbol.uppercased())
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .onDelete { offsets in
                viewModel.deleteUnits(at: offsets, from: customUnits)
            }

            Button {
                viewModel.showAddUnitSheet = true
            } label: {
                Label(String(localized: "Add Custom Unit"), systemImage: "plus.circle.fill")
            }
        } header: {
            Text(String(localized: "Custom Units"))
        } footer: {
            Text(String(localized: "Add custom measurement units for your inventory"))
        }
    }

    // MARK: - Import Section

    private var importSection: some View {
        Section {
            Button {
                showInventoryPicker = true
            } label: {
                Label(String(localized: "Import Inventory (CSV)"), systemImage: "square.and.arrow.down")
            }

            Button {
                showRecipePicker = true
            } label: {
                Label(String(localized: "Import Recipes (CSV)"), systemImage: "book.closed.fill")
            }
        } header: {
            Text(String(localized: "Import"))
        } footer: {
            Text(String(localized: "Import items from CSV files. The first row must contain headers like Name, Category, etc."))
        }
    }

    // MARK: - Export Section

    private var exportSection: some View {
        Section {
            Button {
                viewModel.exportManufacturingData()
            } label: {
                Label(String(localized: "Export Manufacturing Data"), systemImage: "tablecells")
            }

            Button {
                viewModel.exportInventoryData()
            } label: {
                Label(String(localized: "Export Inventory Data"), systemImage: "shippingbox")
            }

            Button {
                viewModel.exportRecipeData()
            } label: {
                Label(String(localized: "Export Recipe Data"), systemImage: "book")
            }
        } header: {
            Text(String(localized: "Export"))
        } footer: {
            Text(String(localized: "Export data as CSV for Google Sheets or Excel"))
        }
    }

    // MARK: - Cloud Backup Section

    private var cloudBackupSection: some View {
        Section {
            NavigationLink {
                BackupSyncView()
            } label: {
                Label(String(localized: "Google Drive Backup"), systemImage: "icloud.and.arrow.up.fill")
            }
        } header: {
            Text(String(localized: "Cloud Backup"))
        }
    }

    // MARK: - Data Section

    private var dataSection: some View {
        Section {
            Button(role: .destructive) {
                viewModel.showClearDataAlert = true
            } label: {
                Label(String(localized: "Clear All Data"), systemImage: "trash.fill")
            }
        } header: {
            Text(String(localized: "Data Management"))
        } footer: {
            Text(String(localized: "Permanently delete all app data"))
        }
    }
}

// MARK: - Add Custom Unit Sheet

private struct AddCustomUnitSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var symbol = ""
    @State private var name = ""

    private var canSave: Bool {
        !symbol.trimmingCharacters(in: .whitespaces).isEmpty &&
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Symbol (e.g., cup, tbsp)"), text: $symbol)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField(String(localized: "Name (e.g., Cup, Tablespoon)"), text: $name)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text(String(localized: "Unit Details"))
                } footer: {
                    Text(String(localized: "Symbol will be displayed in uppercase"))
                }
            }
            .navigationTitle(String(localized: "Add Custom Unit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        saveUnit()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
        }
    }

    private func saveUnit() {
        let unit = CustomUnitEntity(
            symbol: symbol.trimmingCharacters(in: .whitespaces),
            name: name.trimmingCharacters(in: .whitespaces)
        )
        modelContext.insert(unit)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        SettingView()
    }
    .modelContainer(AppModelContainer.make())
}
