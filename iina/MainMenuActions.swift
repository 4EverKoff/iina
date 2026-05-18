//
//  MainWindowMenuActions.swift
//  iina
//
//  Created by lhc on 25/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa


class MainMenuActionHandler: NSResponder, NSMenuItemValidation {

  unowned var player: PlayerCore

  init(playerCore: PlayerCore) {
    self.player = playerCore
    super.init()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  @objc func menuShowInspector(_ sender: AnyObject) {
    let inspector = AppDelegate.shared.inspector
    inspector.showWindow(self)
  }

  @objc func menuSavePlaylist(_ sender: NSMenuItem) {
    let filename = KoffPlaylistStore.shared.defaultPlaylistFilename(for: player)
    let playlistDirectory = try? KoffPlaylistStore.shared.ensurePlaylistsDirectory()
    Utility.quickSavePanel(title: "Save Playlist", filename: filename,
                           types: [KoffPlaylistStore.fileExtension], dir: playlistDirectory,
                           sheetWindow: player.currentWindow) { url in
      do {
        try KoffPlaylistStore.shared.saveCurrentPlaylist(from: self.player, to: url)
      } catch {
        Utility.showAlert("custom", arguments: ["Could not save playlist: \(error.localizedDescription)"],
                          sheetWindow: self.player.currentWindow)
      }
    }
  }

  @objc func menuLoadPlaylist(_ sender: NSMenuItem) {
    do {
      let playlistDirectory = try KoffPlaylistStore.shared.ensurePlaylistsDirectory()
      Utility.quickOpenPanel(title: "Load Playlist", chooseDir: false, dir: playlistDirectory,
                             sheetWindow: player.currentWindow,
                             allowedFileTypes: [KoffPlaylistStore.fileExtension]) { url in
        do {
          try KoffPlaylistStore.shared.loadPlaylist(at: url, in: self.player)
        } catch {
          Utility.showAlert("custom", arguments: ["Could not load playlist: \(error.localizedDescription)"],
                            sheetWindow: self.player.currentWindow)
        }
      }
    } catch {
      Utility.showAlert("custom", arguments: ["Could not open playlists folder: \(error.localizedDescription)"],
                        sheetWindow: player.currentWindow)
    }
  }

  @objc func menuManagePlaylists(_ sender: NSMenuItem) {
    do {
      let playlistDirectory = try KoffPlaylistStore.shared.ensurePlaylistsDirectory()
      NSWorkspace.shared.open(playlistDirectory)
    } catch {
      Utility.showAlert("custom", arguments: ["Could not open playlists folder: \(error.localizedDescription)"],
                        sheetWindow: player.currentWindow)
    }
  }

  @objc func menuShowCurrentFileInFinder(_ sender: NSMenuItem) {
    guard let url = player.info.currentURL, !player.info.isNetworkResource else { return }
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  @objc func menuDeleteCurrentFile(_ sender: NSMenuItem) {
    guard let url = player.info.currentURL, !player.info.isNetworkResource else { return }
    do {
      let index = player.mpv.getInt(MPVProperty.playlistPos)
      player.playlistRemove(index)
      try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    } catch let error {
      Utility.showAlert("playlist.error_deleting", arguments: [error.localizedDescription])
    }
  }

  // currently only being used for key command
  @objc func menuDeleteCurrentFileHard(_ sender: NSMenuItem) {
    guard let url = player.info.currentURL, !player.info.isNetworkResource else { return }
    do {
      let index = player.mpv.getInt(MPVProperty.playlistPos)
      player.playlistRemove(index)
      try FileManager.default.removeItem(at: url)
    } catch let error {
      Utility.showAlert("playlist.error_deleting", arguments: [error.localizedDescription])
    }
  }

}

// MARK: - Control

extension MainMenuActionHandler {
  @objc func menuTogglePause(_ sender: NSMenuItem) {
    player.togglePause()
    // set speed to 0 if is fastforwarding
    if player.mainWindow.isFastforwarding {
      player.setSpeed(1)
      player.mainWindow.isFastforwarding = false
    }
  }

  @objc func menuStop(_ sender: NSMenuItem) {
    // FIXME: handle stop
    player.sendOSD(.stop)
    player.stop()
  }

  @objc func menuStep(_ sender: NSMenuItem) {
    if let args = sender.representedObject as? (Double, Preference.SeekOption) {
      player.seek(relativeSecond: args.0, option: args.1)
    } else {
      let seconds = Double(abs((sender.representedObject as? Int) ?? 5))
      if sender.tag == 0 { // -> 5s
        player.seek(relativeSecond: seconds, option: Preference.SeekOption.defaultValue)
      } else if sender.tag == 1 { // <- 5s
        player.seek(relativeSecond: -seconds, option: Preference.SeekOption.defaultValue)
      }
    }
  }

  @objc func menuStepFrame(_ sender: NSMenuItem) {
    if player.info.state == .playing {
      player.pause()
    }
    if sender.tag == 0 { // -> 1f
      player.frameStep(backwards: false)
    } else if sender.tag == 1 { // <- 1f
      player.frameStep(backwards: true)
    }
  }

  @objc func menuChangeSpeed(_ sender: NSMenuItem) {
    if sender.tag == 5 {
      player.setSpeed(1)
      return
    }
    if let multiplier = sender.representedObject as? Double {
      player.setSpeed(player.info.playSpeed * multiplier)
    }
  }

  @objc func menuJumpToBegin(_ sender: NSMenuItem) {
    player.seek(absoluteSecond: 0)
  }

  @objc func menuJumpTo(_ sender: NSMenuItem) {
    // Make certain the cached video position in the playback info is up to date.
    player.syncPositionIfNeeded()
    Utility.quickPromptPanel("jump_to", inputValue: self.player.info.videoPosition?.stringRepresentationWithPrecision(3)) { input in
      if let vt = VideoTime(input) {
        self.player.seek(absoluteSecond: vt.second)
      }
    }
  }

  @objc func menuSnapshot(_ sender: NSMenuItem) {
    player.screenshot()
  }

  @objc func menuABLoop(_ sender: NSMenuItem) {
    player.mainWindow.abLoop()
  }

  @objc func menuFileLoop(_ sender: NSMenuItem) {
    player.toggleFileLoop()
  }

  @objc func menuPlaylistLoop(_ sender: NSMenuItem) {
    player.togglePlaylistLoop()
  }

  @objc func menuPlaylistItem(_ sender: NSMenuItem) {
    let index = sender.tag
    player.playFileInPlaylist(index)
  }

  @objc func menuChapterSwitch(_ sender: NSMenuItem) {
    let index = sender.tag
    guard let chapter = player.playChapter(index) else {
      Logger.log("Cannot switch to chapter \(index) because it was not found! Will ignore request and reload chapters instead",
                 subsystem: player.subsystem)
      player.getChapters()
      return
    }
    player.sendOSD(.chapter(chapter.title))
  }

  @objc func menuChangeTrack(_ sender: NSMenuItem) {
    if let trackObj = sender.representedObject as? (MPVTrack, MPVTrack.TrackType) {
      player.setTrack(trackObj.0.id, forType: trackObj.1)
    } else if let trackObj = sender.representedObject as? MPVTrack {
      player.setTrack(trackObj.id, forType: trackObj.type)
    }
  }

  @objc func menuNextMedia(_ sender: NSMenuItem) {
    player.navigateInPlaylist(nextMedia: true)
  }

  @objc func menuPreviousMedia(_ sender: NSMenuItem) {
    player.navigateInPlaylist(nextMedia: false)
  }

  @objc func menuNextChapter(_ sender: NSMenuItem) {
    player.mpv.command(.add, args: ["chapter", "1"], checkError: false)
  }

  @objc func menuPreviousChapter(_ sender: NSMenuItem) {
    player.mpv.command(.add, args: ["chapter", "-1"], checkError: false)
  }
}

// MARK: - Video

extension MainMenuActionHandler {
  @objc func menuChangeAspect(_ sender: NSMenuItem) {
    if let aspectStr = sender.representedObject as? String {
      player.setVideoAspect(aspectStr)
      player.sendOSD(.aspect(aspectStr))
    } else {
      Logger.log("Unknown aspect in menuChangeAspect(): \(sender.representedObject.debugDescription)", level: .error)
    }
  }

  @objc func menuChangeCrop(_ sender: NSMenuItem) {
    if let cropStr = sender.representedObject as? String {
      if cropStr == "Custom" {
        player.mainWindow.hideSideBar {
          self.player.mainWindow.enterInteractiveMode(.crop, selectWholeVideoByDefault: true)
        }
        return
      }
      player.setCrop(fromString: cropStr)
    } else {
      Logger.log("sender.representedObject is not a string in menuChangeCrop()", level: .error)
    }
  }

  @objc func menuChangeRotation(_ sender: NSMenuItem) {
    if let rotationInt = sender.representedObject as? Int {
      player.setVideoRotate(rotationInt)
    }
  }

  @objc func menuToggleFlip(_ sender: NSMenuItem) {
    if player.info.flipFilter == nil {
      player.setFlip(true)
    } else {
      player.setFlip(false)
    }
  }

  @objc func menuToggleMirror(_ sender: NSMenuItem) {
    if player.info.mirrorFilter == nil {
      player.setMirror(true)
    } else {
      player.setMirror(false)
    }
  }

  @objc func menuToggleDeinterlace(_ sender: NSMenuItem) {
    player.toggleDeinterlace(sender.state != .on)
  }

  @objc
  func menuToggleVideoFilterString(_ sender: NSMenuItem) {
    if let string = (sender.representedObject as? String) {
      menuToggleFilterString(string, forType: MPVProperty.vf)
    }
  }

  private func menuToggleFilterString(_ string: String, forType type: String) {
    let isVideo = type == MPVProperty.vf
    if let filter = MPVFilter(rawString: string) {
      // Removing a filter based on its position within the filter list is the preferred way to do
      // it as per discussion with the mpv project. Search the list of filters and find the index
      // of the specified filter (if present).
      if let index = player.mpv.getFilters(type).firstIndex(of: filter) {
        // remove
        if isVideo {
          _ = player.removeVideoFilter(filter, index)
        } else {
          _ = player.removeAudioFilter(filter, index)
        }
      } else {
        // add
        if isVideo {
          if !player.addVideoFilter(filter) {
            Utility.showAlert("filter.incorrect")
          }
        } else {
          if !player.addAudioFilter(filter) {
            Utility.showAlert("filter.incorrect")
          }
        }
      }
    }
    let vfWindow = AppDelegate.shared.vfWindow
    if vfWindow.loaded {
      vfWindow.reloadTable()
    }
  }
}

// MARK: - Audio

extension MainMenuActionHandler {
  @objc func menuLoadExternalAudio(_ sender: NSMenuItem) {
    let currentDir = player.info.currentURL?.deletingLastPathComponent()
    Utility.quickOpenPanel(title: "Load external audio file", chooseDir: false, dir: currentDir,
                           sheetWindow: player.currentWindow,
                           allowedFileTypes: Utility.playableFileExt) { url in
      self.player.loadExternalAudioFile(url)
    }
  }

  @objc func menuChangeVolume(_ sender: NSMenuItem) {
    if let volumeDelta = sender.representedObject as? Int {
      let newVolume = Double(volumeDelta) + player.info.volume
      player.setVolume(newVolume)
    } else {
      Logger.log("sender.representedObject is not int in menuChangeVolume()", level: .error)
    }
  }

  @objc func menuToggleMute(_ sender: NSMenuItem) {
    player.toggleMute()
  }

  @objc func menuChangeAudioDelay(_ sender: NSMenuItem) {
    if let delayDelta = sender.representedObject as? Double {
      let newDelay = player.info.audioDelay + delayDelta
      player.setAudioDelay(newDelay)
    } else {
      Logger.log("sender.representedObject is not Double in menuChangeAudioDelay()", level: .error)
    }
  }

  @objc func menuResetAudioDelay(_ sender: NSMenuItem) {
    player.setAudioDelay(0)
  }

  @objc
  func menuToggleAudioFilterString(_ sender: NSMenuItem) {
    if let string = (sender.representedObject as? String) {
      menuToggleFilterString(string, forType: MPVProperty.af)
    }
  }
}

// MARK: - Sub

extension MainMenuActionHandler {
  @objc func menuLoadExternalSub(_ sender: NSMenuItem) {
    let currentDir = player.info.currentURL?.deletingLastPathComponent()
    // In addition to subtitle files allow the user to choose video files as mpv will look for and
    // load embedded subtitle streams in the video file.
    Utility.quickOpenPanel(title: "Load external subtitle", chooseDir: false, dir: currentDir,
                           sheetWindow: player.currentWindow,
                           allowedFileTypes: Utility.containsSubExt) { url in
      self.player.loadExternalSubFile(url, delay: true)
    }
  }

  @objc func menuToggleSubVisibility(_ sender: NSMenuItem) {
    player.toggleSubVisibility()
  }

  @objc func menuToggleSecondSubVisibility(_ sender: NSMenuItem) {
    player.toggleSecondSubVisibility()
  }

  @objc func menuChangeSubDelay(_ sender: NSMenuItem) {
    if let delayDelta = sender.representedObject as? Double {
      let newDelay = player.info.subDelay + delayDelta
      player.setSubDelay(newDelay)
    } else {
      Logger.log("sender.representedObject is not Double in menuChangeSubDelay()", level: .error)
    }
  }

  @objc func menuChangeSubScale(_ sender: NSMenuItem) {
    if sender.tag == 0 {
      player.setSubScale(1)
      return
    }
    // FIXME: better refactor this part
    let amount = sender.tag > 0 ? 0.1 : -0.1
    let currentScale = player.mpv.getDouble(MPVOption.Subtitles.subScale)
    let displayValue = currentScale >= 1 ? currentScale : -1/currentScale
    let truncated = round(displayValue * 100) / 100
    var newTruncated = truncated + amount
    // range for this value should be (~, -1), (1, ~)
    if newTruncated > 0 && newTruncated < 1 || newTruncated > -1 && newTruncated < 0 {
      newTruncated = -truncated + amount
    }
    player.setSubScale(abs(newTruncated > 0 ? newTruncated : 1 / newTruncated))
  }

  @objc func menuResetSubDelay(_ sender: NSMenuItem) {
    player.setSubDelay(0)
  }

  @objc func menuSetSubEncoding(_ sender: NSMenuItem) {
    player.setSubEncoding((sender.representedObject as? String) ?? "auto")
    player.reloadAllSubs()
  }

  @objc func menuSubFont(_ sender: NSMenuItem) {
    player.chooseSubFont()
  }

  @objc func menuFindOnlineSub(_ sender: NSMenuItem) {
    // return if last search is not finished
    guard let url = player.info.currentURL, !player.isSearchingOnlineSubtitle else { return }

    player.isSearchingOnlineSubtitle = true
    OnlineSubtitle.search(forFile: url, player: player, providerID: sender.representedObject as? String) { urls in
      if urls.isEmpty {
        self.player.sendOSD(.foundSub(0))
      } else {
        for url in urls {
          Logger.log("Saved subtitle to \(url.path)")
          self.player.loadExternalSubFile(url)
        }
        self.player.sendOSD(.downloadedSub(
          urls.map({ $0.lastPathComponent }).joined(separator: "\n")
        ))
      }
      self.player.isSearchingOnlineSubtitle = false
    }
  }

  @objc func saveDownloadedSub(_ sender: NSMenuItem) {
    let selected = player.info.$subTracks.withLock { $0.filter { $0.id == player.info.sid } }
    guard selected.count > 0 else {
      Utility.showAlert("sub.no_selected")

      return
    }
    let sub = selected[0]
    // make sure it's a downloaded sub
    guard let path = sub.externalFilename, path.contains("/var/") else {
      Utility.showAlert("sub.no_selected")
      return
    }
    let subURL = URL(fileURLWithPath: path)
    let subFileName = subURL.lastPathComponent
    let windowTitle = NSLocalizedString("alert.sub.save_downloaded.title", comment: "Save Downloaded Subtitle")
    Utility.quickSavePanel(title: windowTitle, filename: subFileName, sheetWindow: player.currentWindow) { (destURL) in
      do {
        // The Save panel checks to see if a file already exists and if so asks if it should be
        // replaced. The quickSavePanel would not have called this code if the user canceled, so if
        // the destination file already exists move it to the trash.
        do {
          try FileManager.default.trashItem(at: destURL, resultingItemURL: nil)
            Logger.log("Trashed existing subtitle file \(destURL)")
          } catch CocoaError.fileNoSuchFile {
            // Expected, ignore error. The Apple Secure Coding Guide in the section Race Conditions
            // and Secure File Operations recommends attempting an operation and handling errors
            // gracefully instead of trying to figure out ahead of time whether the operation will
            // succeed.
          }
          try FileManager.default.copyItem(at: subURL, to: destURL)
          Logger.log("Saved downloaded subtitle to \(destURL.path)")
          self.player.sendOSD(.savedSub)
      } catch let error as NSError {
        Utility.showAlert("error_saving_file", arguments: ["subtitle", error.localizedDescription])
      }
    }
  }

  @objc func menuCycleTrack(_ sender: NSMenuItem) {
    switch sender.tag {
    case 0: player.mpv.command(.cycle, args: ["video"])
    case 1: player.mpv.command(.cycle, args: ["audio"])
    case 2: player.mpv.command(.cycle, args: ["sub"])
    default: break
    }
  }

  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    switch menuItem.action {
    case #selector(menuDeleteCurrentFile(_:)), #selector(menuShowCurrentFileInFinder(_:)):
      return player.info.currentURL != nil && !player.info.isNetworkResource
    case #selector(menuSavePlaylist(_:)):
      return player.info.$playlist.withLock { !$0.isEmpty }
    default:
      break
    }
    return true
  }

  // MARK: - Plugin

  @objc func showPluginsPanel(_ sender: NSMenuItem) {
    player.mainWindow.showPluginSidebar(tab: nil)
  }

  @objc func reloadAllPlugins(_ sender: NSMenuItem) {
    // Remove the developer tool menu item that retains the plugin instance
    AppDelegate.shared.menuController.pluginMenu.items
      .compactMap { $0.submenu }.flatMap { $0.items }
      .forEach { $0.representedObject = nil }
    AppDelegate.shared.menuController.pluginMenu.removeAllItems()

    for player in PlayerCore.playerCores {
      player.clearPlugins()
    }

    JavascriptPlugin.recreateAllPlugins()
    JavascriptPlugin.loadGlobalInstances()

    for player in PlayerCore.playerCores {
      for plugin in JavascriptPlugin.plugins {
        player.reloadPlugin(plugin, forced: true)
      }
      // Try to emit the events that are already emitted.
      // Of course this is not exhaustive, so users shouldn't rely on this function
      if player.mainWindow.loaded {
        player.events.emit(.windowLoaded)
      }
      player.events.emit(.mpvInitialized)
      if player.info.state == .playing {
        player.events.emit(.fileLoaded)
        player.events.emit(.fileStarted)
      }
    }
  }
}

final class KoffPlaylistStore {

  static let shared = KoffPlaylistStore()
  static let fileExtension = "iina-koff-playlist"

  static func isPlaylistURL(_ url: URL) -> Bool {
    url.pathExtension.lowercased() == fileExtension
  }

  static func isPlaylistPath(_ path: String) -> Bool {
    path.lowercasedPathExtension == fileExtension
  }

  private static let format = "iina-koff-playlist"
  private static let schemaVersion = 1

  struct PlaylistDocument: Codable {
    var format: String
    var schemaVersion: Int
    var name: String
    var savedAt: Date
    var currentIndex: Int?
    var lastPlayedPath: String?
    var position: Double?
    var paused: Bool
    var items: [PlaylistItem]
  }

  struct PlaylistItem: Codable {
    var path: String
    var title: String?
  }

  enum StoreError: LocalizedError {
    case emptyPlaylist
    case invalidFormat
    case invalidItem(String)

    var errorDescription: String? {
      switch self {
      case .emptyPlaylist:
        return "The playlist is empty."
      case .invalidFormat:
        return "This is not an IINA Koff playlist."
      case .invalidItem(let path):
        return "Cannot open playlist item: \(path)"
      }
    }
  }

  private final class PendingRestore {
    var observer: NSObjectProtocol?
    let targetIndex: Int
    let position: Double?
    let pauseOnCompletion: Bool
    var requestedTargetFile = false

    init(targetIndex: Int, position: Double?, pauseOnCompletion: Bool = true) {
      self.targetIndex = targetIndex
      self.position = position
      self.pauseOnCompletion = pauseOnCompletion
    }
  }

  private let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }()

  private let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()

  private let fileManager = FileManager.default
  private var pendingRestore: PendingRestore?
  private var isRestoring = false

  var playlistsDirectoryURL: URL {
    let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let appFolder = Bundle.main.bundleIdentifier ?? "com.koff.iina"
    return appSupport
      .appendingPathComponent(appFolder, isDirectory: true)
      .appendingPathComponent("Playlists", isDirectory: true)
  }

  var autosavedPlaylistURL: URL {
    playlistsDirectoryURL.appendingPathComponent("Autosaved.\(Self.fileExtension)", isDirectory: false)
  }

  @discardableResult
  func ensurePlaylistsDirectory() throws -> URL {
    try fileManager.createDirectory(at: playlistsDirectoryURL, withIntermediateDirectories: true)
    return playlistsDirectoryURL
  }

  func defaultPlaylistFilename(for player: PlayerCore) -> String {
    player.getPlaylist()
    let name = player.info.$playlist.withLock { playlist in
      playlist.first(where: { $0.isCurrent || $0.isPlaying })?.filenameForDisplay
        ?? playlist.first?.filenameForDisplay
        ?? "Playlist"
    }
    return "\(sanitizedFilename(name)).\(Self.fileExtension)"
  }

  func autosave(from player: PlayerCore) {
    guard !isRestoring, let document = makeDocument(from: player, name: "Autosaved") else { return }
    do {
      try write(document, to: autosavedPlaylistURL)
    } catch {
      Logger.log("Failed to autosave IINA Koff playlist: \(error.localizedDescription)", level: .error)
    }
  }

  func saveCurrentPlaylist(from player: PlayerCore, to url: URL) throws {
    guard let document = makeDocument(from: player, name: url.deletingPathExtension().lastPathComponent) else {
      throw StoreError.emptyPlaylist
    }
    let destination = url.pathExtension == Self.fileExtension ? url : url.appendingPathExtension(Self.fileExtension)
    try write(document, to: destination)
  }

  func loadPlaylist(at url: URL, in player: PlayerCore) throws {
    let data = try Data(contentsOf: url)
    let document = try decoder.decode(PlaylistDocument.self, from: data)
    try load(document, in: player)
  }

  @discardableResult
  func restoreLastAutosavedPlaylistIfAvailable(in player: PlayerCore) -> Bool {
    guard fileManager.fileExists(atPath: autosavedPlaylistURL.path) else { return false }
    do {
      try loadPlaylist(at: autosavedPlaylistURL, in: player)
      return true
    } catch {
      Logger.log("Failed to restore IINA Koff playlist: \(error.localizedDescription)", level: .error)
      return false
    }
  }

  func restoreLastAutosavedPlaylistIfAvailable(in player: PlayerCore, appendingAndPlaying paths: [String]) -> Bool {
    guard !paths.isEmpty, fileManager.fileExists(atPath: autosavedPlaylistURL.path) else { return false }
    do {
      let data = try Data(contentsOf: autosavedPlaylistURL)
      var document = try decoder.decode(PlaylistDocument.self, from: data)
      let firstNewIndex = document.items.count
      document.items.append(contentsOf: paths.map { PlaylistItem(path: $0, title: nil) })
      document.currentIndex = firstNewIndex
      document.lastPlayedPath = paths[0]
      document.position = nil
      document.paused = false
      try load(document, in: player, pauseOnCompletion: false)
      return true
    } catch {
      Logger.log("Failed to restore and extend IINA Koff playlist: \(error.localizedDescription)", level: .error)
      return false
    }
  }

  private func makeDocument(from player: PlayerCore, name: String) -> PlaylistDocument? {
    if player.info.state.active {
      player.syncPositionIfNeeded()
      player.getPlaylist()
    }

    let playlist = player.info.$playlist.withLock {
      $0.filter { !Self.isPlaylistPath($0.filename) }.map { $0 }
    }
    guard !playlist.isEmpty else { return nil }

    let items = playlist.map { PlaylistItem(path: $0.filename, title: $0.title) }
    let currentIndex = playlist.firstIndex { $0.isCurrent || $0.isPlaying }
    let position = player.info.videoPosition?.second

    return PlaylistDocument(
      format: Self.format,
      schemaVersion: Self.schemaVersion,
      name: name,
      savedAt: Date(),
      currentIndex: currentIndex,
      lastPlayedPath: currentIndex.map { items[$0].path },
      position: position?.isFinite == true ? position : nil,
      paused: player.mpv.getFlag(MPVOption.PlaybackControl.pause),
      items: items
    )
  }

  private func write(_ document: PlaylistDocument, to url: URL) throws {
    try ensurePlaylistsDirectory()
    try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try encoder.encode(document)
    try data.write(to: url, options: .atomic)
  }

  private func load(_ document: PlaylistDocument, in player: PlayerCore, pauseOnCompletion: Bool = true) throws {
    guard document.format == Self.format else { throw StoreError.invalidFormat }
    guard !document.items.isEmpty else { throw StoreError.emptyPlaylist }

    let urls = try document.items.map { item -> (item: PlaylistItem, url: URL) in
      guard !Self.isPlaylistPath(item.path) else {
        throw StoreError.invalidItem(item.path)
      }
      guard let url = playbackURL(for: item.path) else {
        throw StoreError.invalidItem(item.path)
      }
      return (item, url)
    }

    let targetIndex = min(max(document.currentIndex ?? 0, 0), urls.count - 1)
    let pendingRestore = PendingRestore(targetIndex: targetIndex, position: document.position, pauseOnCompletion: pauseOnCompletion)
    installRestoreObserver(pendingRestore, for: player)

    isRestoring = true
    self.pendingRestore = pendingRestore

    player.openURL(urls[0].url, shouldAutoLoad: false, forceMediaTitle: urls[0].item.title)
    urls.dropFirst().forEach { player.mpv.playlistAppend($0.item.path, title: $0.item.title) }
    player.getPlaylist()
    player.postNotification(.iinaPlaylistChanged)
  }

  private func installRestoreObserver(_ pendingRestore: PendingRestore, for player: PlayerCore) {
    pendingRestore.observer = NotificationCenter.default.addObserver(
      forName: .iinaFileLoaded,
      object: player,
      queue: .main
    ) { [weak self, weak player] _ in
      guard let self, let player else { return }
      self.handleFileLoadedDuringRestore(player)
    }
  }

  private func handleFileLoadedDuringRestore(_ player: PlayerCore) {
    guard let pendingRestore else { return }

    if pendingRestore.targetIndex > 0 && !pendingRestore.requestedTargetFile {
      pendingRestore.requestedTargetFile = true
      player.playFileInPlaylist(pendingRestore.targetIndex)
      return
    }

    completeRestore(in: player)
  }

  private func completeRestore(in player: PlayerCore) {
    guard let pendingRestore else { return }
    if let observer = pendingRestore.observer {
      NotificationCenter.default.removeObserver(observer)
    }
    self.pendingRestore = nil

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak player] in
      guard let self, let player else { return }
      if let position = pendingRestore.position, position.isFinite, position > 0 {
        player.seek(absoluteSecond: position)
      }
      if pendingRestore.pauseOnCompletion {
        player.pause()
        player.mpv.setFlag(MPVOption.PlaybackControl.pause, true, level: .verbose)
      } else {
        player.resume()
      }
      player.getPlaylist()
      self.isRestoring = false
      self.autosave(from: player)
    }
  }

  private func playbackURL(for path: String) -> URL? {
    if path.first == "/" {
      return URL(fileURLWithPath: path)
    }
    return URL(string: path)
  }

  private func sanitizedFilename(_ filename: String) -> String {
    let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
    let components = filename.components(separatedBy: invalidCharacters)
    let sanitized = components.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
    return sanitized.isEmpty ? "Playlist" : sanitized
  }
}
