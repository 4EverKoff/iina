//
//  MPVPlaylistItem.swift
//  iina
//
//  Created by lhc on 23/8/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class MPVPlaylistItem: NSObject, Identifiable {

  /** Actually this is the path. Use `filename` to conform mpv API's naming. */
  var filename: String

  /** Title or the real filename */
  var filenameForDisplay: String {
    if let title, !title.isEmpty {
      return title
    }
    if isNetworkResource,
      let url = URL(string: filename) {
      let path = url.path.removingPercentEncoding ?? url.path
      let lastPathComponent = NSString(string: path).lastPathComponent
      if !lastPathComponent.isEmpty {
        return lastPathComponent
      }
    }
    return NSString(string: filename).lastPathComponent
  }

  var isCurrent: Bool
  var isPlaying: Bool
  var isNetworkResource: Bool

  var title: String?

  init(filename: String, isCurrent: Bool, isPlaying: Bool, title: String?) {
    self.filename = filename
    self.isCurrent = isCurrent
    self.isPlaying = isPlaying
    self.title = title
    self.isNetworkResource = Regex.url.matches(filename)
  }
}
