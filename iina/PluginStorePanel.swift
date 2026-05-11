//
//  PluginStore.swift
//  iina
//
//  Created by Hechen Li on 2026-04-18.
//  Copyright © 2026 lhc. All rights reserved.
//

import SwiftUI
import Combine

class PluginStorePanel: NSWindow {
  let l10n: SettingsLocalization.Context

  init(l10n: SettingsLocalization.Context) {
    self.l10n = l10n

    let style: NSWindow.StyleMask = [.titled, .resizable, .fullSizeContentView]
    let rect = NSRect(x: 0, y: 0, width: 600, height: 400)
    super.init(contentRect: rect, styleMask: style, backing: .buffered, defer: false)
    let hostingView = NSHostingView(rootView: PluginStoreView())
    if #available(macOS 13.0, *) {
      hostingView.sizingOptions = .preferredContentSize
    }
    contentView = hostingView
  }

  override func cancelOperation(_ sender: Any?) {
    sheetParent?.endSheet(self, returnCode: .OK)
  }
}

fileprivate let defaultPlugins = [
  ["name": "Online Media", "url": "iina/plugin-online-media", "id": "io.iina.ytdl", "desc": "Official plugin for playing online media via yt-dlp / youtube-dl. The built-in youtube-dl support will be disabled when this plugin is enabled."],
  ["name": "Userscript", "url": "iina/plugin-userscript", "id": "io.iina.user-script", "desc": "User Scripts for IINA"],
  ["name": "Online Subtitles", "url": "iina/plugin-opensub", "id": "io.iina.opensub", "desc": "Official OpenSubtitles plugin for IINA"],
]

struct Plugin: Identifiable, Hashable, Decodable {
  let name: String
  let url: URL
  let id: String
  let desc: String

  init(_ plugin: Dictionary<String, String>) {
    name = plugin["name"]!
    url = URL(string: plugin["url"]!)!
    id = plugin["id"]!
    desc = plugin["desc"]!
  }
}

let officialPlugins = defaultPlugins.map { Plugin($0) }

struct PluginStoreView: View {
  @State private var inputURL: String = ""
  @State private var selection: Plugin? = nil
  @State private var listDownloaded = false

  @State private var communityPluginList: [Plugin] = []
  @State private var errorMessage: String? = nil

  var body: some View {
    VStack(alignment: .leading) {
      Text("Input full URL:")
      HStack() {
        TextField("Full URL", text: $inputURL)
          .textFieldStyle(.roundedBorder)
          .onSubmit {
            // Mirror button action on return key
            print("Install from URL: \(inputURL)")
          }
        Button("Install") {
          // TODO: Handle install from inputURL
          // For now, just print for debugging
          print("Install from URL: \(inputURL)")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
      }.padding(.bottom)
      Text("List of available plugins:")
      HStack {
        VStack(alignment: .leading) {
          let installedPlugins = JavascriptPlugin.plugins
          List(selection: $selection) {
            Section("Official Plugins") {
              ForEach(officialPlugins, id: \.self) { plugin in
                HStack {
                  if installedPlugins.contains(where: { $0.identifier == plugin.id }) {
                    Image(systemName: "checkmark.circle.fill")
                  } else {
                    Image(systemName: "square.and.arrow.down")
                  }
                  Text(plugin.name)
                }
              }
            }

            Section("Community Plugins") {
              if errorMessage != nil {
                Text("Error: \(String(describing: errorMessage))")
              } else if listDownloaded {
                ForEach(communityPluginList, id: \.self) { plugin in
                  HStack {
                    if installedPlugins.contains(where: { $0.identifier == plugin.id }) {
                      Image(systemName: "checkmark.circle.fill")
                    } else {
                      Image(systemName: "square.and.arrow.down")
                    }
                    Text(plugin.name)
                  }
                }
              } else {
                ProgressView("Downloading")
              }
            }
          }.listStyle(.plain)
        }.frame(width: 300)
        GroupBox {
          PluginDetailView(plugin: selection).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }.frame(minWidth: 200)
      }
    }
    .task() {
      do {
        self.communityPluginList = try await GitHubService.fetchPluginList()
      } catch GitHubError.notFound {
        errorMessage = "Repository not found"
      } catch GitHubError.rateLimited {
        errorMessage = "Rate limit exceeded. Try again later or add an API token."
      } catch {
        errorMessage = error.localizedDescription
      }
      listDownloaded = true
    }
    .padding(20)
  }
}


struct PluginDetailView: View {
  let plugin: Plugin?

  var body: some View {
    if let plugin {
      let (owner, repo) = ownerAndRepo(from: plugin.url)
      VStack(alignment: .leading, spacing: 5) {
        Text("Name:").bold()
        Text(plugin.name).padding(.bottom, 5)
        Text("Description:").bold()
        Text(plugin.desc).padding(.bottom, 5)
        Text("URL:").bold()
        Link(destination: plugin.url) {
          Text(plugin.url.absoluteString)
            .multilineTextAlignment(.leading)
        }.padding(.bottom, 5)
        Text("ID:").bold()
        Text(plugin.id)
        if let owner = owner, let repo = repo {
          RepoDetailView(owner: owner, repo: repo)
        }
      }
    } else {
      Text("No selection").bold()
    }
  }

  private func ownerAndRepo(from url: URL) -> (String?, String?) {
    var elements = url.absoluteString.split(separator: "/")
    guard let repo = elements.popLast(), let owner = elements.last else {
      return (nil, nil)
    }
    return (String(owner), String(repo))
  }
}

#Preview {
  PluginStoreView()
}

struct GitHubRepo: Codable {
  let name: String
  let fullName: String
  let description: String?
  let stargazersCount: Int
  let forksCount: Int
  let openIssuesCount: Int
  let language: String?
  let htmlUrl: URL
  let updatedAt: Date
  let owner: Owner

  struct Owner: Codable {
    let login: String
    let avatarUrl: URL
  }

  enum CodingKeys: String, CodingKey {
    case name
    case fullName = "full_name"
    case description
    case stargazersCount = "stargazers_count"
    case forksCount = "forks_count"
    case openIssuesCount = "open_issues_count"
    case language
    case htmlUrl = "html_url"
    case updatedAt = "updated_at"
    case owner
  }
}

extension GitHubRepo.Owner {
  enum CodingKeys: String, CodingKey {
    case login
    case avatarUrl = "avatar_url"
  }
}

enum GitHubError: Error {
  case invalidURL
  case rateLimited
  case notFound
  case decodingError
  case network(Error)
}

class GitHubService {
  func fetchRepo(owner: String, repo: String) async throws -> GitHubRepo {
    guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)") else {
      throw GitHubError.invalidURL
    }

    var request = URLRequest(url: url)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
    // Optional: add a token to raise rate limits from 60/hr to 5000/hr
    // request.setValue("Bearer YOUR_TOKEN", forHTTPHeaderField: "Authorization")

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw GitHubError.network(URLError(.badServerResponse))
    }

    switch httpResponse.statusCode {
    case 200:
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      do {
        return try decoder.decode(GitHubRepo.self, from: data)
      } catch {
        throw GitHubError.decodingError
      }
    case 403:
      throw GitHubError.rateLimited
    case 404:
      throw GitHubError.notFound
    default:
      throw GitHubError.network(URLError(.badServerResponse))
    }
  }

  static func fetchPluginList() async throws -> [Plugin] {
    guard let url = URL(string: "https://raw.githubusercontent.com/iina/iina/refs/heads/develop/plugins.json") else {
      throw GitHubError.invalidURL
    }

    var request = URLRequest(url: url)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
    // Optional: add a token to raise rate limits from 60/hr to 5000/hr
    // request.setValue("Bearer YOUR_TOKEN", forHTTPHeaderField: "Authorization")

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw GitHubError.network(URLError(.badServerResponse))
    }

    switch httpResponse.statusCode {
    case 200:
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      do {
        return try decoder.decode([Plugin].self, from: data)
      } catch {
        throw GitHubError.decodingError
      }
    case 403:
      throw GitHubError.rateLimited
    case 404:
      throw GitHubError.notFound
    default:
      throw GitHubError.network(URLError(.badServerResponse))
    }
  }

  
}

struct RepoDetailView: View {
  let owner: String
  let repo: String

  @State private var repoData: GitHubRepo?
  @State private var isLoading = false
  @State private var errorMessage: String?

  private let service = GitHubService()

  var body: some View {
    Group {
      if isLoading {
        ProgressView("Loading...")
      } else if let error = errorMessage {
        if #available(macOS 14.0, *) {
          ContentUnavailableView("Failed to load",
                                 systemImage: "exclamationmark.triangle",
                                 description: Text(error))
        } else {
          VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
              .font(.title2)
            Text("Failed to load").bold()
            Text(error)
              .font(.caption)
              .foregroundColor(.secondary)
              .multilineTextAlignment(.center)
          }
        }
      } else if let repo = repoData {
        repoContent(repo)
      } else {
        Text("No data")
      }
    }
    .padding()
    .task(id: "\(owner)/\(repo)") {
      await load()
    }
  }

  @ViewBuilder
  private func repoContent(_ repo: GitHubRepo) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        AsyncImage(url: repo.owner.avatarUrl) { image in
          image.resizable()
        } placeholder: {
          Color.gray.opacity(0.2)
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 6))

        VStack(alignment: .leading) {
          Text(repo.fullName)
            .font(.headline)
          Link("View on GitHub", destination: repo.htmlUrl)
            .font(.caption)
        }
      }

      if let description = repo.description {
        Text(description)
          .foregroundColor(.secondary)
      }

      HStack(spacing: 20) {
        Label("\(repo.stargazersCount)", systemImage: "star.fill")
        Label("\(repo.forksCount)", systemImage: "tuningfork")
        Label("\(repo.openIssuesCount)", systemImage: "exclamationmark.circle")
        if let language = repo.language {
          Label(language, systemImage: "chevron.left.forwardslash.chevron.right")
        }
      }
      .font(.callout)
      .foregroundColor(.secondary)

      Text("Updated \(Self.relativeFormatter.localizedString(for: repo.updatedAt, relativeTo: Date()))")
        .font(.caption)
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private static let relativeFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .full
    return f
  }()

  private func load() async {
    isLoading = true
    errorMessage = nil
    do {
      repoData = try await service.fetchRepo(owner: owner, repo: repo)
    } catch GitHubError.notFound {
      errorMessage = "Repository not found"
    } catch GitHubError.rateLimited {
      errorMessage = "Rate limit exceeded. Try again later or add an API token."
    } catch {
      errorMessage = error.localizedDescription
    }
    isLoading = false
  }
}
