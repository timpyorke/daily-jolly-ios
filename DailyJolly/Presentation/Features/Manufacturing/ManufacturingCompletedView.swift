import SwiftUI
import SwiftData
import PhotosUI

struct ManufacturingCompletedView: View {
    @Environment(\.displayScale) private var displayScale
    let manufacturing: ManufacturingEntity
    let viewModel: ManufacturingViewModel
    @Binding var previewImage: Data?
    @Binding var showCamera: Bool
    @Binding var showPhotoLibrary: Bool
    @Binding var selectedPhotos: [PhotosPickerItem]
    @Binding var currentStepIndexForPhoto: Int?
    let stackRouter: StackRouter

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.green)

                VStack(spacing: 8) {
                    Text(String(localized: "Manufacturing Complete!"))
                        .font(.title.bold())

                    Text(manufacturing.recipe.name)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                // Flexible Output Section
                VStack(spacing: 12) {
                    Text(String(localized: "Total Units Produced"))
                        .font(.subheadline.bold())
                    
                    HStack {
                        TextField("0", value: Binding(
                            get: { manufacturing.actualOutput ?? Double(manufacturing.totalUnits) },
                            set: { viewModel.updateActualOutput($0) }
                        ), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .font(.title2.bold())
                        .frame(width: 120)
                        .textFieldStyle(.roundedBorder)
                        
                        Text(manufacturing.recipe.batchUnit)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text(String(localized: "Expected: \(manufacturing.totalUnits) \(manufacturing.recipe.batchUnit)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .liquidGlassMaterial(cornerRadius: 16)

                // Photo Section (Final Result)
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "Work Result Photo"))
                        .font(.headline)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .center, spacing: 12) {
                            let finalImages = manufacturing.images.filter { $0.stepIndex == nil }
                            
                            ForEach(finalImages.sorted(by: { $0.createdAt < $1.createdAt })) { imageEntity in
                                if let uiImage = ImageDownsampler.image(from: imageEntity.imageData, maxPixelSize: 150, scale: displayScale) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 150, height: 150)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            previewImage = imageEntity.imageData
                                        }
                                        .overlay(alignment: .topTrailing) {
                                            Button {
                                                viewModel.removeImage(imageEntity)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundStyle(.white, .red)
                                                    .font(.title2)
                                            }
                                            .padding(4)
                                        }
                                }
                            }
                            
                            Menu {
                                #if !targetEnvironment(simulator)
                                Button {
                                    showCamera = true
                                } label: {
                                    Label(String(localized: "Take Photo"), systemImage: "camera")
                                }
                                #endif
                                
                                Button {
                                    showPhotoLibrary = true
                                } label: {
                                    Label(String(localized: "Choose from Library"), systemImage: "photo.on.rectangle")
                                }
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title)
                                    Text(String(localized: "Add Photo"))
                                        .font(.caption)
                                }
                                .frame(width: 150, height: 150)
                                .liquidGlassMaterial(cornerRadius: 12)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5]))
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)

                // Step Photos Summary
                let allStepImages = manufacturing.images.filter { $0.stepIndex != nil }
                if !allStepImages.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(String(localized: "Step Photos Summary"))
                            .font(.headline)
                        
                        VStack(spacing: 16) {
                            let sortedSteps = manufacturing.recipe.sortedSteps
                            ForEach(Array(sortedSteps.enumerated()), id: \.offset) { index, step in
                                let stepImages = allStepImages.filter { $0.stepIndex == index }
                                if !stepImages.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text("\(index + 1). \(step.title)")
                                                .font(.subheadline.bold())
                                            
                                            Spacer()
                                            
                                            if manufacturing.stepCompletionTime(at: index) != nil {
                                                Text(TimeFormatter.formatDuration(manufacturing.stepDuration(at: index)))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 8) {
                                                ForEach(stepImages.sorted(by: { $0.createdAt < $1.createdAt })) { imageEntity in
                                                    StepPhotoThumbnail(
                                                        imageEntity: imageEntity,
                                                        isCompact: true,
                                                        onPreview: { previewImage = imageEntity.imageData },
                                                        onDelete: { },
                                                        showDelete: false
                                                    )
                                                }
                                            }
                                        }
                                    }
                                    
                                    if index < sortedSteps.count - 1 {
                                        Divider()
                                    }
                                }
                            }
                        }
                        .padding()
                        .liquidGlassMaterial(cornerRadius: 12)
                    }
                    .padding(.horizontal)
                }

                // Completed Measurements Summary
                if !manufacturing.measurements.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "Quality Control Log"))
                            .font(.headline)
                            .padding(.bottom, 4)
                        
                        let sortedMeasurements = manufacturing.measurements.sorted(by: { $0.timestamp < $1.timestamp })
                        let steps = manufacturing.recipe.sortedSteps
                        
                        ForEach(sortedMeasurements) { log in
                            let stepTitle = log.stepIndex < steps.count ? steps[log.stepIndex].title : "Step \(log.stepIndex + 1)"
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(stepTitle).font(.caption).foregroundStyle(.secondary)
                                    Text(log.type.rawValue).font(.subheadline)
                                }
                                Spacer()
                                Text("\(AppNumberFormatter.format(log.value)) \(log.type.symbol)")
                                    .font(.headline)
                            }
                            Divider()
                        }
                    }
                    .padding()
                    .liquidGlassMaterial(cornerRadius: 12)
                    .padding(.horizontal)
                }

                if let completedAt = manufacturing.completedAt {
                    VStack(spacing: 4) {
                        Text(String(localized: "Completed"))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(completedAt, style: .date)
                            .font(.subheadline)

                        Text(completedAt, style: .time)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding()
        }
    }
}
