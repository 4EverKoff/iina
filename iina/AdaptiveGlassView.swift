//
//  AdaptiveGlassView.swift
//  iina
//
//  Created by Yuze Jiang on 2026/05/01.
//  Copyright © 2026 lhc. All rights reserved.
//

/// Whether Liquid Glass effects should be applied.
/// Returns `true` only on macOS 26+ when the user has not disabled the preference.
var effectiveLiquidGlass: Bool {
  if #available(macOS 26, *) {
    return UserDefaults.standard.bool(forKey: Preference.Key.useLiquidGlass.rawValue)
  }
  return false
}

class AdaptiveGlassView: NSView {
  var internalEffectView: NSView = NSVisualEffectView()

  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  override func awakeFromNib() {
    super.awakeFromNib()

    if #available(macOS 26, *), effectiveLiquidGlass {
      internalEffectView = NSGlassEffectView()
    }

    setupEffectView()
  }

  private func setupEffectView() {
    let existingSubviews = subviews
    let existingConstraints = constraints.filter {
      $0.firstItem === self || $0.secondItem === self
    }

    // Create a container to hold existing subviews
    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false

    // Move subviews into container
    for subview in existingSubviews {
      container.addSubview(subview)
    }

    // Re-add the old self-referencing constraints,
    // now targeting container instead of self
    removeConstraints(existingConstraints)
    for c in existingConstraints {
      let firstItem = c.firstItem === self ? container : c.firstItem
      let secondItem = c.secondItem === self ? container : c.secondItem
      container.addConstraint(NSLayoutConstraint(
        item: firstItem as Any,
        attribute: c.firstAttribute,
        relatedBy: c.relation,
        toItem: secondItem,
        attribute: c.secondAttribute,
        multiplier: c.multiplier,
        constant: c.constant
      ))
    }

    // Wire up
    if #available(macOS 26, *), let glassView = internalEffectView as? NSGlassEffectView {
      glassView.contentView = container
    } else if let visualEffectView = internalEffectView as? NSVisualEffectView {
      container.frame = visualEffectView.bounds
      visualEffectView.addSubview(container)
      NSLayoutConstraint.activate([
        container.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
        container.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),
        container.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
        container.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
      ])
    }

    // Add internalEffectView to self and pin it
    internalEffectView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(internalEffectView)
    NSLayoutConstraint.activate([
      internalEffectView.topAnchor.constraint(equalTo: topAnchor),
      internalEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),
      internalEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
      internalEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])
  }

  func roundCorners(withRadius cornerRadius: CGFloat) {
    if let view = internalEffectView as? NSVisualEffectView {
      view.roundCorners(withRadius: cornerRadius)
    } else if #available(macOS 26, *), let view = internalEffectView as? NSGlassEffectView {
      view.cornerRadius = cornerRadius
    }
  }
}
