//
//  SettingsLocalization.swift
//  iina
//
//  Created by Hechen Li on 6/22/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

struct SettingsLocalization {
  struct Key: RawRepresentable {
    typealias RawValue = String
    var rawValue: String

    init(_ rawValue: String) {
      self.rawValue = rawValue
    }

    init?(rawValue: String) {
      self.rawValue = rawValue
    }
  }

  class Context {
    var tableName: String
    var keyPrefix: String?

    init(tableName: String, keyPrefix: String? = nil) {
      self.tableName = tableName
      self.keyPrefix = keyPrefix
    }

    func localized(_ key: Key) -> String {
      var k = key.rawValue
      if !k.hasPrefix("$") {
        k = (keyPrefix ?? "") + (keyPrefix == nil ? "" : ".") + k
      }
      return NSLocalizedString(k, tableName: tableName, comment: key.rawValue)
    }
  }

  static func injectContext(_ view: NSView, _ context: SettingsLocalization.Context!) {
    var newContext = context
    if var vc = view as? WithSettingsLocalizationContext {
      if let container = vc as? SettingsContainer {
        vc.l10n = Context(tableName: context.tableName, keyPrefix: container.l10nScope)
        newContext = vc.l10n
      } else {
        vc.l10n = context
      }
    }
    for v in view.subviews {
      injectContext(v, newContext)
    }
  }

}

protocol WithSettingsLocalizationContext {
  var l10n: SettingsLocalization.Context! { get set }
}
