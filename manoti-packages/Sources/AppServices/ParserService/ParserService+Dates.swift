//
//  ParserService+Dates.swift
//  AppServices
//

import Foundation

enum DateExtractor {
    struct Result {
        let date: Date
        let fromMessage: Bool
    }

    static func extract(date: String?, time: String?, ampm: String?, fallback: Date) -> Result {
        guard let date, !date.isEmpty else {
            return Result(date: fallback, fromMessage: false)
        }

        var stamp = date.trimmingCharacters(in: .whitespaces)
        if let time, !time.isEmpty {
            stamp += " \(time.trimmingCharacters(in: .whitespaces))"
        }
        if let ampm, !ampm.isEmpty {
            stamp += " \(ampm.trimmingCharacters(in: .whitespaces))"
        }

        for format in formats {
            if let parsed = formatter(format).date(from: stamp) {
                return Result(date: parsed, fromMessage: true)
            }
        }

        return Result(date: fallback, fromMessage: false)
    }

    private static let formats = [
        "dd/MM/yy h:mm a",
        "dd/MM/yyyy h:mm a",
        "dd/MM/yy HH:mm",
        "dd/MM/yyyy HH:mm",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd HH:mm",
        "yyyy-MM-dd",
        "dd/MM/yy",
        "dd/MM/yyyy",
        "dd MMM yyyy",
        "dd MMM yyyy HH:mm",
    ]

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_KE")
        formatter.timeZone = .current
        formatter.dateFormat = format
        formatter.isLenient = false
        return formatter
    }
}
