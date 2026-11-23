//
//  RuleService.swift
//  AppServices
//

import AppModels
import AppPackageExtensions
import Foundation
import Observation
import SwiftData

@Observable
public final class RuleService: Loggable {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func save() throws {
        try context.save()
        ManotiNotifications.postDataChanged()
    }

    public func isValid(pattern: String) -> Bool {
        (try? NSRegularExpression(pattern: pattern)) != nil
    }
}
