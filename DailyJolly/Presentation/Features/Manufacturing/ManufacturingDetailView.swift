import SwiftUI
import SwiftData

struct ManufacturingDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(StackRouter.self) private var stackRouter
    @Environment(\.displayScale) private var displayScale

    let id: PersistentIdentifier

    @State private var viewModel = ManufacturingDetailViewModel()
    @State private var previewImage: Data?

    var body: some View {
        Group {
            if viewModel.isDeleting {
                ProgressView(String(localized: "Deleting..."))
                    .frame(maxHeight: .infinity)
            } else if let manufacturing = viewModel.manufacturing {
                contentView(manufacturing)
            } else {
                ContentUnavailableView("Not Found", systemImage: "exclamationmark.triangle")
            }
        }
        .navigationTitle(viewModel.manufacturingName.isEmpty ? String(localized: "Manufacturing") : viewModel.manufacturingName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        viewModel.exportData()
                    } label: {
                        Label("Export to Sheets", systemImage: "tablecells")
                    }

                    Divider()

                    Button(role: .destructive) {
                        viewModel.showDeleteAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Delete Manufacturing", isPresented: $viewModel.showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                viewModel.deleteManufacturing {
                    stackRouter.pop()
                }
            }
        } message: {
            Text("Are you sure you want to delete this manufacturing record?")
        }
        .sheet(isPresented: $viewModel.showShareSheet) {
            if let url = viewModel.exportURL {
                ShareSheet(items: [url])
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") { }
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred")
        }
        .onAppear {
            viewModel.setup(modelContext: modelContext, id: id)
        }
        .overlay {
            if let imageData = previewImage, let uiImage = UIImage(data: imageData) {
                ZStack {
                    Color.black.ignoresSafeArea()
                    
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .ignoresSafeArea()
                    
                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                previewImage = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.title2.bold())
                                    .foregroundStyle(.white)
                                    .padding()
                                    .background(.black.opacity(0.5))
                                    .clipShape(Circle())
                            }
                        }
                        Spacer()
                    }
                    .padding()
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .animation(.easeInOut, value: previewImage != nil)
    }

    // MARK: - Content

    private func contentView(_ manufacturing: ManufacturingEntity) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Summary Header
                summaryHeader(manufacturing)

                // Photo Result
                if !manufacturing.images.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Work Result Photos")
                            .font(.title3.bold())
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(manufacturing.images.sorted(by: { $0.createdAt < $1.createdAt })) { imageEntity in
                                    if let uiImage = ImageDownsampler.image(from: imageEntity.imageData, maxPixelSize: 200, scale: displayScale) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 200, height: 200)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                previewImage = imageEntity.imageData
                                            }
                                    }
                                }
                            }
                        }
                    }
                }

                // Process Visualization
                VStack(alignment: .leading, spacing: 12) {
                    Text("Process Analysis")
                        .font(.title3.bold())
                    
                    ManufacturingProcessVisualizer(manufacturing: manufacturing)
                }

                // Time Summary
                if !manufacturing.recipe.steps.isEmpty {
                    timeSummary(manufacturing)
                }

                // Quality Control Summary
                if !manufacturing.measurements.isEmpty {
                    qcSummary(manufacturing)
                }

                // Steps List
                if !manufacturing.recipe.steps.isEmpty {
                    stepsSection(manufacturing)
                }

                // Ingredients Used
                if !manufacturing.recipe.ingredients.isEmpty {
                    ingredientsSection(manufacturing.recipe)
                }
            }
            .padding()
        }
    }

    private func summaryHeader(_ manufacturing: ManufacturingEntity) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Batch Number Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Batch Number")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("#\(manufacturing.batchNumber)")
                        .font(.title2.bold().monospaced())
                        .foregroundStyle(Color.accentColor)
                }

                Spacer()

                Image(systemName: manufacturing.isCompleted ? "checkmark.circle.fill" : "clock.fill")
                    .foregroundStyle(manufacturing.isCompleted ? .green : .orange)
                    .font(.title)
            }

            Divider()

            HStack {
                Text(manufacturing.isCompleted ? "Completed" : "In Progress")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(manufacturing.isCompleted ? .green : .orange)

                Spacer()

                if let category = manufacturing.recipe.category {
                    Text(category)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.fill.tertiary)
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 16) {
                Label {
                    Text("Started: \(manufacturing.startedAt, format: .dateTime.month().day().hour().minute())")
                } icon: {
                    Image(systemName: "play.circle")
                }

                if let completedAt = manufacturing.completedAt {
                    Label {
                        Text("Ended: \(completedAt, format: .dateTime.hour().minute())")
                    } icon: {
                        Image(systemName: "stop.circle")
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Batch & Cost Info
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Batches")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(manufacturing.quantity)x")
                        .font(.headline)
                }

                Divider()
                    .frame(height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Produced")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let actual = manufacturing.actualOutput {
                        Text("\(AppNumberFormatter.format(actual)) \(manufacturing.recipe.batchUnit)")
                            .font(.headline)
                            .foregroundStyle(.green)
                    } else {
                        Text("\(manufacturing.totalUnits) \(manufacturing.recipe.batchUnit)")
                            .font(.headline)
                    }
                }

                Divider()
                    .frame(height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Cost")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(CurrencyFormatter.format(manufacturing.totalCost))
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Per Unit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let actual = manufacturing.actualOutput, actual > 0 {
                        let actualPerUnit = manufacturing.totalCost / actual
                        Text(CurrencyFormatter.format(actualPerUnit))
                            .font(.headline)
                            .foregroundStyle(.green)
                    } else {
                        Text(CurrencyFormatter.format(manufacturing.costPerUnit))
                            .font(.headline)
                            .foregroundStyle(.green)
                    }
                }
            }
            .padding(.top, 8)
        }
        .padding()
        .background(.fill.quinary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func timeSummary(_ manufacturing: ManufacturingEntity) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Time Summary")
                .font(.title3.bold())

            HStack(spacing: 16) {
                // Total Duration
                VStack(spacing: 4) {
                    Text(TimeFormatter.formatDuration(manufacturing.totalDuration))
                        .font(.title2.bold())
                        .foregroundStyle(Color.accentColor)
                    Text("Total Time")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.fill.quinary)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Steps Count
                VStack(spacing: 4) {
                    Text("\(manufacturing.totalSteps)")
                        .font(.title2.bold())
                    Text("Steps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.fill.quinary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func qcSummary(_ manufacturing: ManufacturingEntity) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quality Control Summary")
                .font(.title3.bold())

            VStack(alignment: .leading, spacing: 0) {
                let sortedMeasurements = manufacturing.measurements.sorted(by: { $0.timestamp < $1.timestamp })
                let steps = manufacturing.recipe.sortedSteps
                
                ForEach(Array(sortedMeasurements.enumerated()), id: \.element.persistentModelID) { index, log in
                    let stepTitle = log.stepIndex < steps.count ? steps[log.stepIndex].title : "Step \(log.stepIndex + 1)"
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stepTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(log.type.rawValue)
                                .font(.subheadline.weight(.medium))
                        }
                        
                        Spacer()
                        
                        Text("\(AppNumberFormatter.format(log.value)) \(log.type.symbol)")
                            .font(.headline)
                            .foregroundStyle(Color.accentColor)
                    }
                    .padding(.vertical, 8)
                    
                    if index < sortedMeasurements.count - 1 {
                        Divider()
                    }
                }
            }
            .padding()
            .background(.fill.quinary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func stepsSection(_ manufacturing: ManufacturingEntity) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Steps")
                .font(.title3.bold())

            VStack(spacing: 0) {
                ForEach(Array(manufacturing.recipe.sortedSteps.enumerated()), id: \.element.persistentModelID) { index, step in
                    stepRow(step, index: index, manufacturing: manufacturing)

                    if index < manufacturing.recipe.steps.count - 1 {
                        Divider()
                            .padding(.leading, 44)
                    }
                }
            }
            .padding()
            .background(.fill.quinary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func stepRow(_ step: RecipeStepEntity, index: Int, manufacturing: ManufacturingEntity) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Step Number
            let isCompleted = manufacturing.isStepCompleted(at: index)
            ZStack {
                Circle()
                    .fill(isCompleted ? Color.green : Color.secondary.opacity(0.3))
                    .frame(width: 32, height: 32)

                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                } else {
                    Text("\(index + 1)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                // Step Title
                Text(step.title)
                    .font(.headline)

                // Step Note
                if !step.note.isEmpty {
                    Text(step.note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Time Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 16) {
                        // Actual duration
                        if isCompleted {
                            let duration = manufacturing.stepDuration(at: index)
                            Label("Actual: \(TimeFormatter.formatDuration(duration))", systemImage: "stopwatch")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }

                    if isCompleted, let log = manufacturing.getLog(at: index) {
                        HStack(spacing: 8) {
                            if let start = log.startedAt {
                                Text("Started: \(start, format: .dateTime.hour().minute())")
                            }
                            if let end = log.completedAt {
                                Text("Ended: \(end, format: .dateTime.hour().minute())")
                            }
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    }
                }

                // Measurements
                let measurements = manufacturing.getMeasurements(at: index)
                if !measurements.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(measurements) { measurement in
                            HStack {
                                Image(systemName: "gauge.with.needle")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                Text("\(measurement.type.rawValue):")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(AppNumberFormatter.format(measurement.value)) \(measurement.type.symbol)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    .padding(8)
                    .background(.fill.tertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Step Note (user entered during manufacturing)
                if let stepNote = manufacturing.stepNote(at: index) {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "note.text")
                            .font(.caption)
                            .foregroundStyle(.blue)
                        Text(stepNote)
                            .font(.caption)
                            .foregroundStyle(.primary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }

    private func ingredientsSection(_ recipe: RecipeEntity) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Ingredients Used")
                    .font(.title3.bold())

                Spacer()

                if recipe.totalCost > 0 {
                    Text(CurrencyFormatter.format(recipe.totalCost))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(recipe.ingredients, id: \.persistentModelID) { ingredient in
                    HStack {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(.secondary)

                        Text(ingredient.inventoryItem.name)

                        Spacer()

                        Text("\(AppNumberFormatter.format(ingredient.quantity)) \(ingredient.displaySymbol)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(.fill.quinary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack {
        Text("Manufacturing Detail Preview")
    }
    .modelContainer(AppModelContainer.make())
}
