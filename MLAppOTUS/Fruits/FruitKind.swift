import Foundation

nonisolated struct FruitKind: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let emoji: String
    let sampleName: String

    static let all: [FruitKind] = [
        FruitKind(id: "apple", title: "Яблоко", emoji: "🍎", sampleName: "sample-apple"),
        FruitKind(id: "avocado", title: "Авокадо", emoji: "🥑", sampleName: "sample-avocado"),
        FruitKind(id: "banana", title: "Банан", emoji: "🍌", sampleName: "sample-banana"),
        FruitKind(id: "cherry", title: "Вишня", emoji: "🍒", sampleName: "sample-cherry"),
        FruitKind(id: "kiwi", title: "Киви", emoji: "🥝", sampleName: "sample-kiwi"),
        FruitKind(id: "mango", title: "Манго", emoji: "🥭", sampleName: "sample-mango"),
        FruitKind(id: "orange", title: "Апельсин", emoji: "🍊", sampleName: "sample-orange"),
        FruitKind(id: "pinenapple", title: "Ананас", emoji: "🍍", sampleName: "sample-pineapple"),
        FruitKind(id: "strawberries", title: "Клубника", emoji: "🍓", sampleName: "sample-strawberry"),
        FruitKind(id: "watermelon", title: "Арбуз", emoji: "🍉", sampleName: "sample-watermelon")
    ]

    static func named(_ id: String) -> FruitKind? {
        all.first { $0.id == id }
    }
}

nonisolated struct ClassificationResult: Equatable, Sendable {
    struct Candidate: Equatable, Sendable, Identifiable {
        var id: String { identifier }
        let identifier: String
        let confidence: Float

        var kind: FruitKind? { FruitKind.named(identifier) }
        var title: String { kind?.title ?? identifier }
        var percent: Int { Int((confidence * 100).rounded()) }
    }

    let top: Candidate?
    let alternatives: [Candidate]

    var isReliable: Bool {
        guard let top else { return false }
        let second = alternatives.first?.confidence ?? 0
        return top.confidence >= 0.80 && (top.confidence - second) >= 0.08
    }

    static let empty = ClassificationResult(top: nil, alternatives: [])
}
