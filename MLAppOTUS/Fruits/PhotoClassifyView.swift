import PhotosUI
import SwiftUI
import UIKit

struct PhotoClassifyView: View {
    @State private var model = PhotoClassifyViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                FruitPalette.background.ignoresSafeArea()

                VStack(spacing: 16) {
                    imageCard
                    ResultBanner(result: model.result)
                    samplesRow
                    actions
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .navigationTitle("Фото")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(FruitPalette.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .photosPicker(isPresented: $model.showGallery, selection: $model.pickerItem, matching: .images)
            .onChange(of: model.pickerItem) { _, item in
                Task { await model.load(item) }
            }
            .fullScreenCover(isPresented: $model.showCamera) {
                CameraImagePicker(image: $model.capturedImage)
                    .ignoresSafeArea()
            }
            .onChange(of: model.capturedImage) { _, image in
                guard let image else { return }
                model.classify(image)
            }
        }
    }

    @ViewBuilder
    private var imageCard: some View {
        Button {
            model.showGallery = true
        } label: {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(FruitPalette.card)
                .overlay {
                    if let image = model.selectedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 42))
                                .foregroundStyle(FruitPalette.accent)
                            Text("Выберите фото фрукта")
                                .font(.headline)
                            Text("Галерея, камера или пример ниже")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .frame(maxHeight: .infinity)
    }

    private var samplesRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Примеры")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(FruitKind.all) { kind in
                        Button {
                            model.loadSample(kind)
                        } label: {
                            VStack(spacing: 4) {
                                Text(kind.emoji)
                                    .font(.title)
                                Text(kind.title)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 72, height: 64)
                            .background(FruitPalette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                model.showGallery = true
            } label: {
                Label("Галерея", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(FruitPalette.accent)

            Button {
                model.showCamera = UIImagePickerController.isSourceTypeAvailable(.camera)
            } label: {
                Label("Камера", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
        }
        .font(.headline)
        .padding(.vertical, 4)
    }
}

@Observable
final class PhotoClassifyViewModel {
    var selectedImage: UIImage?
    var capturedImage: UIImage?
    var result: ClassificationResult?
    var showGallery = false
    var showCamera = false
    var pickerItem: PhotosPickerItem?

    private var classifier: FruitVisionClassifier?

    func classify(_ image: UIImage) {
        selectedImage = image
        guard let cgImage = Self.rasterize(image) else {
            result = .empty
            return
        }
        do {
            result = try readyClassifier().classify(cgImage: cgImage)
        } catch {
            result = FruitSampleMatcher.classify(cgImage: cgImage) ?? .empty
        }
    }

    func loadSample(_ kind: FruitKind) {
        guard let image = UIImage(named: kind.sampleName) else { return }
        classify(image)
    }

    func load(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            return
        }
        classify(image)
    }

    private func readyClassifier() throws -> FruitVisionClassifier {
        if let classifier {
            return classifier
        }
        let created = try FruitVisionClassifier()
        classifier = created
        return created
    }

    private static func rasterize(_ image: UIImage) -> CGImage? {
        if let cgImage = image.cgImage {
            return cgImage
        }
        let width = max(image.size.width * image.scale, 1)
        let height = max(image.size.height * image.scale, 1)
        let size = CGSize(width: width, height: height)
        UIGraphicsBeginImageContextWithOptions(size, true, 1)
        defer { UIGraphicsEndImageContext() }
        UIColor.white.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        image.draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()?.cgImage
    }
}
