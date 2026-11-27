//
//  SplitTemplate.swift
//  AppModels
//

import Foundation

nonisolated public struct SplitTemplateLine: Codable, Equatable, Sendable {
    public let categoryID: UUID
    /// Share of the entry in basis points. A template's lines sum to 10,000.
    public let weightBasisPoints: Int

    public init(categoryID: UUID, weightBasisPoints: Int) {
        self.categoryID = categoryID
        self.weightBasisPoints = weightBasisPoints
    }
}

/// How a merchant's receipts were split last time, as proportions rather than amounts.
///
/// Learned from manual split entries and offered back in review. It is never applied without
/// a tap: a wrong split silently corrupts a budget, while a wrong offer costs one tap.
nonisolated public struct SplitTemplate: Codable, Equatable, Sendable {
    public let lines: [SplitTemplateLine]

    /// Keeps only positive shares, drops duplicates and normalises to 10,000 basis points.
    /// Returns nil when there are fewer than two distinct categories to split between.
    public init?(lines: [SplitTemplateLine]) {
        var weights: [UUID: Int] = [:]

        for line in lines where line.weightBasisPoints > 0 {
            weights[line.categoryID, default: 0] += line.weightBasisPoints
        }

        guard weights.count >= 2 else {
            return nil
        }

        let total = weights.values.reduce(0, +)
        guard total > 0 else {
            return nil
        }

        var normalised = weights.map { categoryID, weight in
            SplitTemplateLine(
                categoryID: categoryID,
                weightBasisPoints: max(1, weight * 10_000 / total)
            )
        }

        let allocated = normalised.reduce(0) { $0 + $1.weightBasisPoints }
        let missing = 10_000 - allocated

        if missing != 0, let largest = normalised.indices.max(by: {
            normalised[$0].weightBasisPoints < normalised[$1].weightBasisPoints
        }) {
            let line = normalised[largest]
            normalised[largest] = SplitTemplateLine(
                categoryID: line.categoryID,
                weightBasisPoints: line.weightBasisPoints + missing
            )
        }

        self.lines = normalised.sorted {
            if $0.weightBasisPoints != $1.weightBasisPoints {
                return $0.weightBasisPoints > $1.weightBasisPoints
            }

            return $0.categoryID.uuidString < $1.categoryID.uuidString
        }
    }

    /// - Parameter lines: the saved lines of a manually split entry. Every line must carry a
    ///   category, otherwise the uncategorised share would be redistributed silently.
    @MainActor
    public static func from(lines: [LedgerLineInput]) -> SplitTemplate? {
        guard lines.count >= 2,
            lines.allSatisfy({ $0.category != nil && $0.amountMinor > 0 })
        else {
            return nil
        }

        var weights: [UUID: Int] = [:]

        for line in lines {
            guard let category = line.category else {
                return nil
            }

            weights[category.id, default: 0] += Int(clamping: line.amountMinor)
        }

        return SplitTemplate(
            lines: weights.map { SplitTemplateLine(categoryID: $0.key, weightBasisPoints: $0.value) }
        )
    }

    /// Splits `totalMinor` in the same proportions. Every line gets at least one minor unit
    /// and the parts always add up to the total.
    public func allocations(totalMinor: Int64) -> [(categoryID: UUID, amountMinor: Int64)]? {
        guard totalMinor >= Int64(lines.count), totalMinor > 0 else {
            return nil
        }

        var amounts = lines.map { line in
            totalMinor * Int64(line.weightBasisPoints) / 10_000
        }

        for index in amounts.indices where amounts[index] == 0 {
            amounts[index] = 1
        }

        var difference = totalMinor - amounts.reduce(0, +)

        while difference > 0 {
            let index = lines.indices.max { lhs, rhs in
                let left = (totalMinor * Int64(lines[lhs].weightBasisPoints)) % 10_000
                let right = (totalMinor * Int64(lines[rhs].weightBasisPoints)) % 10_000
                return left < right
            } ?? 0
            amounts[index] += 1
            difference -= 1
        }

        while difference < 0 {
            guard let index = amounts.indices
                .filter({ amounts[$0] > 1 })
                .max(by: { amounts[$0] < amounts[$1] })
            else {
                return nil
            }

            amounts[index] -= 1
            difference += 1
        }

        return zip(lines, amounts).map { line, amount in
            (categoryID: line.categoryID, amountMinor: amount)
        }
    }

    // MARK: - Storage

    public init?(encoded: String) {
        guard let data = encoded.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(SplitTemplate.self, from: data)
        else {
            return nil
        }

        self = decoded
    }

    public var encoded: String {
        guard let data = try? JSONEncoder().encode(self) else {
            return ""
        }

        return String(data: data, encoding: .utf8) ?? ""
    }

    /// "Household 60% · Groceries 40%", resolved against the categories in the store.
    public func summary(categoryNames: [UUID: String]) -> String? {
        let parts = lines.compactMap { line -> String? in
            guard let name = categoryNames[line.categoryID] else {
                return nil
            }

            return "\(name) \(line.weightBasisPoints / 100)%"
        }

        guard parts.count == lines.count else {
            return nil
        }

        return parts.joined(separator: " · ")
    }
}
