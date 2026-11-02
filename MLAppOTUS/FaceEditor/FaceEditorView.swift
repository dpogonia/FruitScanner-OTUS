import PhotosUI
import SwiftUI
import UIKit

struct FaceEditorView: View {
    @State private var model = FaceEditorModel()

    var body: some View {
        NavigationStack {
            ZStack {
                FruitPalette.background.ignoresSafeArea()

                VStack(spacing: 14) {
                    imageCard
                    faceTypeCard
                    sliders
                    actions
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .navigationTitle("Редактор")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(FruitPalette.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.showLandmarks.toggle()
                    } label: {
                        Image(systemName: model.showLandmarks ? "face.dashed.fill" : "face.dashed")
                    }
                    .disabled(model.face == nil)
                    .accessibilityLabel("Контур лица")
                }
            }
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
                model.setImage(image)
            }
        }
    }

    @ViewBuilder
    private var imageCard: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(FruitPalette.card)
            .overlay {
                if let image = model.displayedImage {
                    GeometryReader { geo in
                        let fitted = fittedRect(imageSize: image.size, in: geo.size)
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .overlay {
                                if model.showLandmarks, let face = model.face {
                                    LandmarkOverlay(face: face, imageRect: fitted)
                                }
                            }
                            .overlay(alignment: .bottomTrailing) {
                                if !model.compareOriginal {
                                    Image(systemName: "hand.tap.fill")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(8)
                                        .background(.black.opacity(0.45), in: Circle())
                                        .padding(10)
                                        .accessibilityLabel("Удерживайте, чтобы сравнить с оригиналом")
                                        .allowsHitTesting(false)
                                }
                            }
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { _ in model.compareOriginal = true }
                                    .onEnded { _ in model.compareOriginal = false }
                            )
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 42))
                            .foregroundStyle(FruitPalette.accent)
                        Text("Нейро-редактор лица")
                            .font(.headline)
                        Text("Загрузите портрет — определим тип лица и изменим овал и глаза")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Загрузить пример") {
                            model.loadSample()
                        }
                        .buttonStyle(.bordered)
                        .tint(FruitPalette.accent)
                    }
                    .padding()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            )
            .frame(maxHeight: .infinity)
        if let message = model.errorMessage {
            Text(message)
                .font(.caption.weight(.medium))
                .foregroundStyle(.red.opacity(0.9))
        }
    }

    @ViewBuilder
    private var faceTypeCard: some View {
        if let face = model.face {
            HStack(spacing: 12) {
                Image(systemName: "face.smiling")
                    .font(.title2)
                    .foregroundStyle(FruitPalette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Тип лица: \(face.shape.title)")
                        .font(.headline)
                    Text(face.shape.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .background(FruitPalette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var sliders: some View {
        VStack(spacing: 14) {
            editSlider(
                title: "Овал лица",
                leading: "Шире",
                trailing: "Уже",
                value: $model.oval
            )
            editSlider(
                title: "Глаза",
                leading: "Меньше",
                trailing: "Больше",
                value: $model.eyes
            )
        }
        .disabled(model.face == nil)
        .opacity(model.face == nil ? 0.45 : 1)
        .onChange(of: model.oval) { _, _ in model.render() }
        .onChange(of: model.eyes) { _, _ in model.render() }
    }

    private func editSlider(
        title: String,
        leading: String,
        trailing: String,
        value: Binding<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            HStack {
                Text(leading)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Slider(value: value, in: -1...1)
                    .tint(FruitPalette.accent)
                Text(trailing)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(FruitPalette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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

            Button {
                model.reset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .frame(width: 22)
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .disabled(model.sourceImage == nil)
        }
        .font(.headline)
    }

    private func fittedRect(imageSize: CGSize, in bounds: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(
            x: (bounds.width - width) / 2,
            y: (bounds.height - height) / 2,
            width: width,
            height: height
        )
    }
}

struct LandmarkOverlay: View {
    let face: DetectedFace
    let imageRect: CGRect

    var body: some View {
        Canvas { context, _ in
            var path = Path()
            for point in face.overlayPoints {
                let viewPoint = convert(point)
                path.addEllipse(in: CGRect(x: viewPoint.x - 1.5, y: viewPoint.y - 1.5, width: 3, height: 3))
            }
            context.fill(path, with: .color(FruitPalette.accent.opacity(0.9)))

            if face.contour.count > 1 {
                var contour = Path()
                contour.move(to: convert(face.contour[0]))
                for point in face.contour.dropFirst() {
                    contour.addLine(to: convert(point))
                }
                context.stroke(contour, with: .color(.white.opacity(0.7)), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }

    private func convert(_ point: CGPoint) -> CGPoint {
        let size = face.imageSize
        guard size.width > 0, size.height > 0 else { return .zero }
        return CGPoint(
            x: imageRect.minX + point.x / size.width * imageRect.width,
            y: imageRect.minY + (1 - point.y / size.height) * imageRect.height
        )
    }
}

@Observable
final class FaceEditorModel {
    var sourceImage: UIImage?
    var previewImage: UIImage?
    var face: DetectedFace?
    var oval: Double = 0
    var eyes: Double = 0
    var compareOriginal = false
    var showLandmarks = false
    var errorMessage: String?
    var showGallery = false
    var showCamera = false
    var pickerItem: PhotosPickerItem?
    var capturedImage: UIImage?

    var displayedImage: UIImage? {
        if compareOriginal { return sourceImage }
        return previewImage ?? sourceImage
    }

    func setImage(_ image: UIImage) {
        guard let prepared = FaceAnalyzer.prepare(image) else {
            errorMessage = "Не удалось прочитать изображение."
            return
        }
        sourceImage = prepared
        face = FaceAnalyzer.detect(in: prepared)
        oval = 0
        eyes = 0
        compareOriginal = false
        if face == nil {
            errorMessage = "Лицо не найдено. Нужен портрет анфас."
            previewImage = prepared
        } else {
            errorMessage = nil
            previewImage = prepared
        }
    }

    func render() {
        guard let sourceImage else { return }
        guard let face else {
            previewImage = sourceImage
            return
        }
        previewImage = FaceWarper.render(
            image: sourceImage,
            face: face,
            oval: Float(oval),
            eyes: Float(eyes)
        )
    }

    func reset() {
        oval = 0
        eyes = 0
        previewImage = sourceImage
    }

    func loadSample() {
        guard let image = UIImage(named: "sample-face") else {
            errorMessage = "Пример не найден в бандле."
            return
        }
        setImage(image)
    }

    func load(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            return
        }
        setImage(image)
    }
}
