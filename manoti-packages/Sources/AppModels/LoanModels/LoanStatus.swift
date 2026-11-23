//
//  LoanStatus.swift
//  AppModels
//

import Foundation

nonisolated public enum LoanStatus: String, CaseIterable, Codable, Sendable {
    case open
    case settled
}
