//
//  SmartRuleConditions.swift
//  AppModels
//

import Foundation

nonisolated public struct SmartRuleConditions: Codable, Sendable, Equatable {
    public var amountMinMinor: Int64?
    public var amountMaxMinor: Int64?
    public var timeStartMinutes: Int?
    public var timeEndMinutes: Int?
    public var weekdays: [Int]?
    public var payeeContains: [String]?
    public var contextMerchant: String?

    public init(
        amountMinMinor: Int64? = nil,
        amountMaxMinor: Int64? = nil,
        timeStartMinutes: Int? = nil,
        timeEndMinutes: Int? = nil,
        weekdays: [Int]? = nil,
        payeeContains: [String]? = nil,
        contextMerchant: String? = nil
    ) {
        self.amountMinMinor = amountMinMinor
        self.amountMaxMinor = amountMaxMinor
        self.timeStartMinutes = timeStartMinutes
        self.timeEndMinutes = timeEndMinutes
        self.weekdays = weekdays
        self.payeeContains = payeeContains
        self.contextMerchant = contextMerchant
    }

    public func matches(
        amountMinor: Int64,
        payee: String,
        date: Date,
        contextMerchant: String?,
        calendar: Calendar = .current
    ) -> Bool {
        if let amountMinMinor, amountMinor < amountMinMinor {
            return false
        }

        if let amountMaxMinor, amountMinor > amountMaxMinor {
            return false
        }

        if let weekdays, !weekdays.isEmpty {
            let weekday = calendar.component(.weekday, from: date)
            if !weekdays.contains(weekday) {
                return false
            }
        }

        if let timeStartMinutes, let timeEndMinutes {
            let components = calendar.dateComponents([.hour, .minute], from: date)
            let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)

            let inWindow =
                timeStartMinutes <= timeEndMinutes
                ? (minutes >= timeStartMinutes && minutes < timeEndMinutes)
                : (minutes >= timeStartMinutes || minutes < timeEndMinutes)

            if !inWindow {
                return false
            }
        }

        if let payeeContains, !payeeContains.isEmpty {
            let matched = payeeContains.contains { fragment in
                containsWholeWord(payee, fragment)
            }

            if !matched {
                return false
            }
        }

        if let required = self.contextMerchant, !required.isEmpty {
            guard let contextMerchant,
                normalised(contextMerchant) == normalised(required)
            else {
                return false
            }
        }

        return true
    }

    /// Matches a whole word or phrase, not a fragment inside another word: `mart` must
    /// not match `SMART`, and `uber` must not match `Uber Eats`.
    private func containsWholeWord(_ haystack: String, _ needle: String) -> Bool {
        let text = haystack.uppercased()
        let word = needle.uppercased()
        guard !word.isEmpty else {
            return false
        }

        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: word, range: searchRange) {
            let startsAtBoundary =
                range.lowerBound == text.startIndex
                || !text[text.index(before: range.lowerBound)].isLetter
            let endsAtBoundary =
                range.upperBound == text.endIndex
                || !text[range.upperBound].isLetter

            if startsAtBoundary, endsAtBoundary {
                return true
            }

            searchRange = range.upperBound..<text.endIndex
        }

        return false
    }

    private func normalised(_ value: String) -> String {
        value
            .uppercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
