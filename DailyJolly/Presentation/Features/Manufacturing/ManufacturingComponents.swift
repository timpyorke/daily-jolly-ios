import SwiftUI
import SwiftData
import PhotosUI
import Combine

// MARK: - Parallel Step Row

struct ParallelStepRow: View {
    let index: Int
    let step: RecipeStepEntity
    let manufacturing: ManufacturingEntity
    let viewModel: ManufacturingViewModel
    @Binding var note: String
    
    // Bindings for Photo Section
    @Binding var previewImage: Data?
    @Binding var showCamera: Bool
    @Binding var showPhotoLibrary: Bool
    @Binding var selectedPhotos: [PhotosPickerItem]
    @Binding var currentStepIndexForPhoto: Int?
    
    var isCompleted: Bool { manufacturing.isStepCompleted(at: index) }
    var canComplete: Bool { manufacturing.canCompleteStep(at: index) }
    var isStarted: Bool { manufacturing.isStepStarted(at: index) }
    var recordedTime: Date? { manufacturing.stepCompletionTime(at: index) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(step.title)
                    .font(.headline)
                    .foregroundStyle(isCompleted ? .secondary : .primary)
                
                if !step.note.isEmpty {
                    Text(step.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Step Photos
                StepPhotoSection(
                    index: index,
                    manufacturing: manufacturing,
                    viewModel: viewModel,
                    previewImage: $previewImage,
                    showCamera: $showCamera,
                    showPhotoLibrary: $showPhotoLibrary,
                    selectedPhotos: $selectedPhotos,
                    currentStepIndexForPhoto: $currentStepIndexForPhoto,
                    isCompact: true
                )

                if isCompleted {
                    if let stepNote = manufacturing.stepNote(at: index) {
                        Text(stepNote)
                            .font(.caption)
                            .foregroundStyle(.blue)
                            .padding(6)
                            .background(.blue.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                } else {
                    TextField(String(localized: "Add note..."), text: $note)
                        .font(.caption)
                        .textFieldStyle(.roundedBorder)
                }

                // Timer & Record Section
                if !isCompleted && step.isTimerRequired {
                    HStack {
                        if !isStarted {
                            Button {
                                viewModel.startStep(at: index)
                            } label: {
                                Label(String(localized: "Start Timer"), systemImage: "play.fill")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .tint(.green)
                        } else if isCompleted || recordedTime != nil {
                            let duration = manufacturing.stepDuration(at: index)
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                Text(TimeFormatter.formatDuration(duration))
                            }
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.green.opacity(0.1))
                            .clipShape(Capsule())
                        } else {
                            StepTimerView(startTime: manufacturing.getStepStartTime(at: index) ?? Date.now)
                            
                            Button {
                                viewModel.recordStepTime(at: index)
                            } label: {
                                Label(String(localized: "Record Time"), systemImage: "stopwatch.fill")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)
                        }
                    }
                }

                // Measurement inputs
                if !isCompleted && !step.requiredMeasurements.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(step.requiredMeasurements) { measurement in
                            let loggedValue = manufacturing.getMeasurements(at: index)
                                .first(where: { $0.type == measurement })?.value
                            
                            MeasurementInputView(
                                type: measurement,
                                value: .constant(loggedValue),
                                onSave: { newValue in
                                    viewModel.logMeasurement(at: index, type: measurement, value: newValue)
                                }
                            )
                            .scaleEffect(0.8)
                            .frame(height: 25)
                        }
                    }
                    .padding(.top, 4)
                }
            }

            Spacer()

            if isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                let hasQC = manufacturing.hasRequiredMeasurements(at: index)
                let isTimeRecorded = recordedTime != nil
                let timerRequired = step.isTimerRequired
                
                Button(canComplete ? (hasQC ? (!timerRequired || isTimeRecorded ? String(localized: "Complete") : String(localized: "Need Time")) : String(localized: "Need QC")) : String(localized: "Waiting")) {
                    viewModel.completeStep(at: index, note: note)
                }
                .buttonStyle(.bordered)
                .disabled(!canComplete || !hasQC || (timerRequired && !isTimeRecorded))
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Step Photo Section

struct StepPhotoSection: View {
    let index: Int
    let manufacturing: ManufacturingEntity
    let viewModel: ManufacturingViewModel
    @Binding var previewImage: Data?
    @Binding var showCamera: Bool
    @Binding var showPhotoLibrary: Bool
    @Binding var selectedPhotos: [PhotosPickerItem]
    @Binding var currentStepIndexForPhoto: Int?
    var isCompact: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "Step Photos"))
                    .font(isCompact ? .caption.bold() : .subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if !manufacturing.isStepCompleted(at: index) {
                    Menu {
                        #if !targetEnvironment(simulator)
                        Button {
                            currentStepIndexForPhoto = index
                            showCamera = true
                        } label: {
                            Label(String(localized: "Take Photo"), systemImage: "camera")
                        }
                        #endif
                        
                        Button {
                            currentStepIndexForPhoto = index
                            showPhotoLibrary = true
                        } label: {
                            Label(String(localized: "Choose from Library"), systemImage: "photo.on.rectangle")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                            Text(String(localized: "Add Photo"))
                        }
                        .font(.caption)
                    }
                }
            }

            let stepImages = manufacturing.images.filter { $0.stepIndex == index }
            if !stepImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(stepImages.sorted(by: { $0.createdAt < $1.createdAt })) { imageEntity in
                            StepPhotoThumbnail(
                                imageEntity: imageEntity,
                                isCompact: isCompact,
                                onPreview: { previewImage = imageEntity.imageData },
                                onDelete: { viewModel.removeImage(imageEntity) },
                                showDelete: !manufacturing.isStepCompleted(at: index)
                            )
                        }
                    }
                }
            } else if !isCompact && !manufacturing.isStepCompleted(at: index) {
                Text(String(localized: "No photos added for this step"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            }
        }
        .onChange(of: selectedPhotos) { _, newValue in
            if currentStepIndexForPhoto == index {
                Task {
                    for item in newValue {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            viewModel.addImageData(data, stepIndex: index)
                        }
                    }
                    selectedPhotos = []
                    currentStepIndexForPhoto = nil
                }
            }
        }
    }
}

struct StepPhotoThumbnail: View {
    let imageEntity: ManufacturingImageEntity
    let isCompact: Bool
    let onPreview: () -> Void
    let onDelete: () -> Void
    let showDelete: Bool

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        if let uiImage = ImageDownsampler.image(from: imageEntity.imageData, maxPixelSize: isCompact ? 60 : 100, scale: displayScale) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: isCompact ? 60 : 100, height: isCompact ? 60 : 100)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
                .onTapGesture(perform: onPreview)
                .overlay(alignment: .topTrailing) {
                    if showDelete {
                        Button(action: onDelete) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.white, .red)
                                .font(isCompact ? .caption : .subheadline)
                        }
                        .padding(2)
                    }
                }
        }
    }
}

// MARK: - Step Timer Component

struct StepTimerView: View {
    let startTime: Date
    @State private var elapsed: TimeInterval = 0
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(formatDuration(elapsed))
            .font(.caption.monospacedDigit())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.fill.tertiary)
            .clipShape(Capsule())
            .onReceive(timer) { _ in
                elapsed = Date.now.timeIntervalSince(startTime)
            }
            .onAppear {
                elapsed = Date.now.timeIntervalSince(startTime)
            }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}
