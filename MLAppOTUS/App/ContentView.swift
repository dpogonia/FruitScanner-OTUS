import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            FruitHomeworkView()
                .tabItem {
                    Label("Фрукты", systemImage: "leaf.fill")
                }

            FaceEditorView()
                .tabItem {
                    Label("Редактор", systemImage: "wand.and.stars")
                }
        }
        .tint(FruitPalette.accent)
        .preferredColorScheme(.dark)
    }
}

struct FruitHomeworkView: View {
    @State private var mode: FruitMode = .photo

    var body: some View {
        VStack(spacing: 0) {
            Picker("Режим", selection: $mode) {
                Text("Фото").tag(FruitMode.photo)
                Text("Камера").tag(FruitMode.camera)
                Text("AR").tag(FruitMode.ar)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(FruitPalette.background)

            Group {
                switch mode {
                case .photo:
                    PhotoClassifyView()
                case .camera:
                    LiveCameraView()
                case .ar:
                    ARClassifyView()
                }
            }
        }
        .background(FruitPalette.background)
    }
}

private enum FruitMode {
    case photo
    case camera
    case ar
}

enum FruitPalette {
    static let background = Color(red: 0.07, green: 0.10, blue: 0.08)
    static let card = Color(red: 0.13, green: 0.18, blue: 0.15)
    static let accent = Color(red: 0.96, green: 0.62, blue: 0.22)
    static let good = Color(red: 0.46, green: 0.80, blue: 0.52)
}

struct ResultBanner: View {
    let result: ClassificationResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let top = result?.top, result?.isReliable == true {
                HStack(spacing: 12) {
                    Text(top.kind?.emoji ?? "🍐")
                        .font(.system(size: 36))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(top.title)
                            .font(.title3.weight(.semibold))
                        Text("Уверенность \(top.percent)%")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(top.percent)%")
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(FruitPalette.good)
                }

                ProgressView(value: Double(top.confidence))
                    .tint(FruitPalette.good)

                if let alternatives = result?.alternatives, !alternatives.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(alternatives) { item in
                            Text("\(item.kind?.emoji ?? "") \(item.title) \(item.percent)%")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(.white.opacity(0.08), in: Capsule())
                        }
                    }
                }
            } else if result != nil {
                HStack(spacing: 12) {
                    Image(systemName: "xmark.circle")
                        .font(.title)
                        .foregroundStyle(FruitPalette.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Не распознан")
                            .font(.headline)
                        Text("Картинка не является распознаваемым фруктом")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let top = result?.top {
                            Text("Лучшее совпадение: \(top.title) \(top.percent)%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "leaf.circle")
                        .font(.title)
                        .foregroundStyle(FruitPalette.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Покажите фрукт")
                            .font(.headline)
                        Text("10 классов: яблоко, банан, киви и другие")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
    }
}

#Preview {
    ContentView()
}
