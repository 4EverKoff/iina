import SwiftUI
import AppKit

final class SpotlightPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: SpotlightPanel?
    let store = CatalogStore()
    private var monitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let panel = SpotlightPanel(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 480),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: LauncherView(store: store))
        panel.center()
        window = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.store.handleKey(event.keyCode) else { return event }
            return nil
        }

        Task { await bootstrap() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    private func bootstrap() async {
        do {
            let cfg = try XtreamConfig.load()
            var pw = LaunchOptions.stdinPassword
            if pw == nil {
                do {
                    pw = try KeychainStore.loadPassword(username: cfg.username)
                } catch {
                    xlog("[xtream-launcher] trousseau indisponible : \(String(describing: error))")
                }
            }
            guard let pw, !pw.isEmpty else {
                await MainActor.run {
                    store.setupServer = cfg.server
                    store.setupUsername = cfg.username
                    store.needsSetup = true
                    store.status = "Mot de passe à renseigner"
                }
                return
            }
            await MainActor.run {
                store.bootstrap(server: cfg.server, username: cfg.username, password: pw)
                NSApp.activate(ignoringOtherApps: true)
                window?.makeKeyAndOrderFront(nil)
            }
        } catch {
            await MainActor.run {
                store.needsSetup = true
                store.status = "Configurer le compte Xtream"
            }
            xlog("[xtream-launcher] config plist introuvable ou incomplète")
        }
    }
}

struct LauncherView: View {
    @ObservedObject var store: CatalogStore
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if store.needsSetup {
                SetupView(store: store)
            } else {
                VStack(spacing: 0) {
                    header
                    Divider().opacity(0.4)
                    content
                    Divider().opacity(0.4)
                    footer
                }
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
    }

    private var header: some View {
        Group {
            if store.drilledSeason != nil, let s = store.drilledSeries {
                HStack(spacing: 10) {
                    Button(action: { store.back() }) {
                        Label("Retour", systemImage: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    Text("\(s.name) · Saison \(store.drilledSeason!)")
                        .font(.system(size: 18, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                }
                .padding(.horizontal, 18).padding(.vertical, 14)
            } else if let s = store.drilledSeries {
                HStack(spacing: 10) {
                    Button(action: { store.back() }) {
                        Label("Retour", systemImage: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    Text(s.name)
                        .font(.system(size: 18, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                }
                .padding(.horizontal, 18).padding(.vertical, 14)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(.secondary)
                    TextField("TV, films, séries…", text: $store.query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 22, weight: .light))
                        .focused($focused)
                }
                .padding(.horizontal, 18).padding(.vertical, 14)
            }
        }
        .onAppear { focused = true }
    }

    private var content: some View {
        let secs: [SectionData]
        if store.drilledSeries == nil {
            secs = store.sections()
        } else if store.drilledSeason == nil {
            secs = store.seasonSections()
        } else {
            secs = store.episodeSections()
        }
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(secs) { sec in
                        Section(header: sectionHeader(sec.title)) {
                            ForEach(sec.rows) { row in rowView(row) }
                        }
                    }
                    if secs.isEmpty { emptyView }
                }
            }
            .onChange(of: store.selectionIndex) { newValue in
                let rows = secs.flatMap { $0.rows }
                guard newValue >= 0, newValue < rows.count else { return }
                proxy.scrollTo(rows[newValue].id, anchor: .center)
            }
        }
    }

    private func rowView(_ row: RowData) -> some View {
        let selected = row.flatIndex == store.selectionIndex
        return Button(action: { store.openRow(row) }) {
            HStack(spacing: 10) {
                if let iconURL = row.media?.icon ?? row.episode?.image {
                    AsyncImage(url: URL(string: iconURL)) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        default:
                            placeholderBadge(row.kind)
                        }
                    }
                    .frame(width: 46, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                } else {
                    placeholderBadge(row.kind)
                        .frame(width: 46, height: 32)
                }
                Text(row.kind.badge)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(badgeColor(row.kind), in: RoundedRectangle(cornerRadius: 5))
                Text(row.label)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                if row.season != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(selected ? Color.accentColor.opacity(0.25) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .id(row.id)
    }

    private func placeholderBadge(_ kind: MediaKind) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(badgeColor(kind).opacity(0.25))
            .overlay(
                Image(systemName: kind == .tv ? "tv" : (kind == .movie ? "film" : "play.rectangle"))
                    .font(.system(size: 12))
                    .foregroundStyle(badgeColor(kind))
            )
    }

    private func badgeColor(_ kind: MediaKind) -> Color {
        switch kind {
        case .tv: return .blue
        case .movie: return .purple
        case .series: return .orange
        case .episode: return .green
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
    }

    private var emptyView: some View {
        Text(store.query.isEmpty ? "Aucun élément" : "Aucun résultat")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 40)
    }

    private var footer: some View {
        HStack {
            Text(store.status).foregroundStyle(.secondary)
            Spacer()
            Text("\(store.live.count) TV · \(store.vod.count) films · \(store.series.count) séries")
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 18).padding(.vertical, 8)
    }
}

/// Formulaire de premier démarrage : serveur, identifiant, mot de passe.
/// Le mot de passe part directement dans le Trousseau, jamais dans un fichier.
struct SetupView: View {
    @ObservedObject var store: CatalogStore
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Configuration Xtream")
                .font(.system(size: 18, weight: .medium))
            Text("Renseigné une fois : serveur et identifiant dans un fichier local, mot de passe dans le Trousseau.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Serveur (http://…)", text: $store.setupServer)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
            TextField("Identifiant", text: $store.setupUsername)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
            SecureField("Mot de passe", text: $password)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
            HStack {
                Button("Enregistrer et charger", action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(store.setupServer.isEmpty || store.setupUsername.isEmpty || password.isEmpty)
                Spacer()
            }
            Text(store.status)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(22)
    }

    private func submit() {
        store.completeSetup(server: store.setupServer, username: store.setupUsername, password: password)
        password = ""
    }
}
