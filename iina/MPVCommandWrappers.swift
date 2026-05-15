//
//  MPVCommandWrappers.swift
//  iina
//
//  Created by Yuze Jiang on 2025/05/25.
//  Copyright © 2025 lhc. All rights reserved.
//

extension MPVController {
  func loadFile(_ path: String, title: String? = nil) {
    if let options = loadFileOptions(title: title) {
      command(.loadfile, nodeArgs: [path, "replace", -1, options], level: .verbose)
    } else {
      command(.loadfile, args: [path], level: .verbose)
    }
  }

  func playlistInsert(_ path: String, index: Int, title: String? = nil) {
    if let options = loadFileOptions(title: title) {
      command(.loadfile, nodeArgs: [path, "insert-at", index, options], level: .verbose)
    } else {
      command(.loadfile, args: [path, "insert-at", index.description], level: .verbose)
    }
  }

  func playlistAppend(_ path: String, title: String? = nil) {
    if let options = loadFileOptions(title: title) {
      command(.loadfile, nodeArgs: [path, "append", -1, options], level: .verbose)
    } else {
      command(.loadfile, args: [path, "append"], level: .verbose)
    }
  }

  func playlistMove(_ from: Int, to: Int) {
    command(.playlistMove, args: ["\(from)", "\(to)"], level: .verbose)
  }

  func playlistRemove(_ index: Int) {
    command(.playlistRemove, args: [index.description], level: .verbose)
  }

  private func loadFileOptions(title: String?) -> [String: Any?]? {
    guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
    return [MPVOption.forceMediaTitle: title]
  }
}
