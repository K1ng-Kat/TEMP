import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum TEMPStyle {
    static let purple = Color(red: 0.39, green: 0.32, blue: 0.93)
    static let violet = Color(red: 0.60, green: 0.42, blue: 0.99)
    static let panel = Color(nsColor: .controlBackgroundColor)
    static let hairline = Color.primary.opacity(0.075)
}

private enum SortMode: String, CaseIterable, Identifiable {
    case expiration = "Expiring first"
    case newest = "Recently added"
    case name = "Name"

    var id: Self { self }
}

struct ContentView: View {
    @EnvironmentObject private var store: TemporaryStore

    @AppStorage("TEMP.defaultExpiration") private var defaultExpirationRaw = ExpirationPreset.oneDay.rawValue

    @State private var section: TempSection = .all
    @State private var showingSettings = false
    @State private var searchText = ""
    @AppStorage("TEMP.sidebar.visible") private var sidebarVisible = true
    @State private var compactSidebarOpen = false
    @State private var compactLayout = false
    @AppStorage("TEMP.welcome.completed") private var hasCompletedWelcome = false
    @State private var showingWelcome = false
    @State private var pendingFolderURLs: [URL] = []
    @State private var pendingFolderDuration: TimeInterval?
    @State private var confirmingFolderImport = false
    @State private var sortMode: SortMode = .expiration
    @State private var showingFilesPicker = false
    @State private var showingFoldersPicker = false
    @State private var isDropTargeted = false
    @State private var pendingTrash: TempItem?
    @State private var editingExpiration: TempItem?
    @State private var customDate = Date().addingTimeInterval(24 * 60 * 60)

    private var chosenExpiration: ExpirationPreset {
        ExpirationPreset(rawValue: defaultExpirationRaw) ?? .oneDay
    }

    private var expirationSelection: Binding<ExpirationPreset> {
        Binding(
            get: { chosenExpiration },
            set: { defaultExpirationRaw = $0.rawValue }
        )
    }

    private var visibleItems: [TempItem] {
        let matches = store.items(in: section).filter {
            searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
        }
        switch sortMode {
        case .expiration:
            return matches.sorted {
                if $0.isPinned != $1.isPinned { return !$0.isPinned }
                return ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture)
            }
        case .newest:
            return matches.sorted { $0.importedAt > $1.importedAt }
        case .name:
            return matches.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    private var nextExpiration: TempItem? {
        store.items.filter { !$0.isPinned && $0.expiresAt != nil }
            .min { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
    }

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 940
            let sidebarWidth: CGFloat = compact ? 0 : (sidebarVisible ? 216 : 0)

            ZStack(alignment: .topLeading) {
                ZStack {
                    Color(nsColor: .windowBackgroundColor)
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.15),
                            Color.purple.opacity(0.07),
                            .clear,
                            Color.cyan.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                .ignoresSafeArea()

                HStack(spacing: 0) {
                    if !compact && sidebarVisible {
                        sidebar
                            .frame(width: 216)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }

                    workspace(compact: compact)
                        .frame(width: max(1, geometry.size.width - sidebarWidth))
                }
                .frame(maxHeight: .infinity, alignment: .top)

                if compact && compactSidebarOpen {
                    Color.black.opacity(0.16)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.smooth(duration: 0.25)) {
                                compactSidebarOpen = false
                            }
                        }

                    sidebar
                        .frame(width: min(244, geometry.size.width - 50))
                        .shadow(color: .black.opacity(0.15), radius: 19, x: 4, y: 0)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .onAppear {
                compactLayout = compact
                if !hasCompletedWelcome { showingWelcome = true }
            }
            .onChange(of: compact) { _, value in
                compactLayout = value
                compactSidebarOpen = false
            }
            .onChange(of: section) { _, _ in compactSidebarOpen = false }
        }
        .tint(.accentColor)
        .sheet(isPresented: $showingWelcome) {
            TEMPWelcomeExperience(
                onFinish: {
                    hasCompletedWelcome = true
                    showingWelcome = false
                },
                onImportFiles: {
                    hasCompletedWelcome = true
                    showingWelcome = false
                    showingFilesPicker = true
                },
                onTrackFolder: {
                    hasCompletedWelcome = true
                    showingWelcome = false
                    showingFoldersPicker = true
                }
            )
        }
        .fileImporter(
            isPresented: $showingFilesPicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true,
            onCompletion: handleImport
        )
        .fileImporter(
            isPresented: $showingFoldersPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: true,
            onCompletion: handleImport
        )
        .sheet(item: $editingExpiration) { item in
            customExpirationSheet(for: item)
        }
        .confirmationDialog(
            "Track original folders?",
            isPresented: $confirmingFolderImport,
            titleVisibility: .visible
        ) {
            Button("Track original folders") {
                store.importURLs(pendingFolderURLs, expiresAfter: pendingFolderDuration)
                pendingFolderURLs = []
                confirmingFolderImport = false
            }
            Button("Cancel", role: .cancel) {
                pendingFolderURLs = []
                confirmingFolderImport = false
            }
        } message: {
            Text("TEMP does not copy folders. They stay at their original locations. When their timer expires, the ORIGINAL folders and their contents move to Trash. Choose Keep forever to disable automatic expiration.")
        }
        .confirmationDialog(
            "Move \(pendingTrash?.name ?? "this item") to Trash?",
            isPresented: Binding(
                get: { pendingTrash != nil },
                set: { if !$0 { pendingTrash = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                if let item = pendingTrash { store.moveToTrash(item) }
                pendingTrash = nil
            }
        } message: {
            Text(pendingTrash?.isInPlaceFolder == true
                 ? "This will move the ORIGINAL folder and all of its contents to Trash."
                 : "Only TEMP's managed copy is moved to Trash.")
        }
        .alert(
            "TEMP couldn't complete that action",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "Unknown error")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "hourglass")
                    .font(.system(size: 19, weight: .medium))
                    .frame(width: 39, height: 39)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("TEMP")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("Temporary workspace")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 22)

            Text("LIBRARY")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 19)
                .padding(.bottom, 9)
            VStack(spacing: 4) {
                sidebarRow(.all, count: store.items.count)
                sidebarRow(.expiringSoon, count: store.expiringCount)
                sidebarRow(.pinned, count: store.pinnedCount)

                Divider()
                    .padding(.vertical, 10)

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showingSettings = true
                        compactSidebarOpen = false
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13))
                            .frame(width: 20)
                        Text("Settings")
                            .font(.system(size: 12, weight: showingSettings ? .semibold : .medium))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(showingSettings ? Color.primary : Color.secondary)
                    .padding(.horizontal, 11)
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                    .background(showingSettings ? Color.accentColor.opacity(0.13) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            }
            .padding(.horizontal, 10)
            Spacer(minLength: 12)
            VStack(alignment: .leading, spacing: 13) {
                Divider()
                Button {
                    showingWelcome = true
                } label: {
                    Label("How TEMP works", systemImage: "questionmark.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .accessibilityHint("Opens the TEMP welcome guide")

                Button {
                    store.showLibraryInFinder()
                } label: {
                    Label("Reveal TEMP storage", systemImage: "folder")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                Text("Version \(appVersion) · Build \(appBuild)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Text("Files are copied. Folders stay in place.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 17)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.primary.opacity(0.075)).frame(width: 0.75)
        }
    }

    private func sidebarRow(_ target: TempSection, count: Int) -> some View {
        let active = section == target && !showingSettings
        return Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                section = target
                showingSettings = false
                compactSidebarOpen = false
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: target.icon)
                    .font(.system(size: 13))
                    .frame(width: 20)
                Text(target.title)
                    .font(.system(size: 12, weight: active ? .semibold : .medium))
                Spacer()
                Text(count.formatted())
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .foregroundStyle(active ? Color.primary : Color.secondary)
            .padding(.horizontal, 11)
            .frame(height: 38)
            .background(active ? Color.accentColor.opacity(0.13) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Main workspace

    private func workspace(compact: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                topBar(compact: compact)

                if showingSettings {
                    settingsPage
                } else {
                    overview
                    if store.items.isEmpty && section == .all {
                        welcomeDropZone
                        gettingStarted
                    } else {
                        if section == .all, let next = nextExpiration {
                            upcomingCard(next)
                        }
                        library
                    }
                    bottomNote
                }
            }
            .frame(maxWidth: 1160, alignment: .leading)
            .padding(.horizontal, compact ? 18 : 24)
            .padding(.top, 14)
            .padding(.bottom, 23)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color.clear)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 7]))
                    .padding(9)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted, perform: acceptDrop)
    }

    private func sidebarToggle() -> some View {
        let expanded = compactLayout ? compactSidebarOpen : sidebarVisible

        return Button {
            withAnimation(.smooth(duration: 0.26)) {
                if compactLayout {
                    compactSidebarOpen.toggle()
                } else {
                    sidebarVisible.toggle()
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13, weight: .semibold))
                Text(expanded ? "Hide sidebar" : "Show sidebar")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .frame(minWidth: 114, minHeight: 35)
            .padding(.horizontal, 9)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .help(expanded ? "Close the sidebar" : "Open the sidebar")
        .accessibilityLabel(expanded ? "Hide sidebar" : "Show sidebar")
    }

    private func topBar(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center, spacing: 12) {
                sidebarToggle()

                VStack(alignment: .leading, spacing: 5) {
                    Text(showingSettings ? "Settings" : section.title)
                        .font(.system(size: compact ? 25 : 31, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text(showingSettings ? "Preferences, storage, and app information" : section.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if !compact && !showingSettings {
                    expirationPicker
                }

                if !showingSettings {
                    importMenu
                }
            }

            if compact && !showingSettings {
                HStack(spacing: 8) {
                    expirationPicker
                    Spacer()
                    Button {
                        showingWelcome = true
                    } label: {
                        Label("How it works", systemImage: "questionmark.circle")
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var expirationPicker: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text("NEW ITEMS EXPIRE")
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Picker("Default expiration", selection: expirationSelection) {
                ForEach(ExpirationPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 130)
        }
    }

    private var importMenu: some View {
        Menu {
            Button("Import files…", systemImage: "doc.badge.plus") {
                showingFilesPicker = true
            }
            Button("Track folders…", systemImage: "folder.badge.plus") {
                showingFoldersPicker = true
            }
        } label: {
            Label("Add items", systemImage: "plus")
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 3)
                .frame(minHeight: 35)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "Unknown"
    }

    private var appBuild: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "Unknown"
    }

    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsCard(title: "General", subtitle: "Choose how TEMP handles new items", icon: "slider.horizontal.3") {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Default expiration")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Used for files and folders when you add them.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 10)
                    Picker("Default expiration", selection: expirationSelection) {
                        ForEach(ExpirationPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 150)
                }
            }

            settingsCard(title: "Storage & cleanup", subtitle: "TEMP keeps you in control", icon: "externaldrive") {
                VStack(spacing: 12) {
                    settingsAction(
                        title: "Reveal TEMP storage",
                        detail: "Open the folder containing TEMP-managed file copies.",
                        icon: "folder"
                    ) {
                        store.showLibraryInFinder()
                    }

                    Divider()

                    settingsAction(
                        title: "Run cleanup now",
                        detail: "Move expired items to Trash. Tracked original folders are included.",
                        icon: "trash"
                    ) {
                        store.cleanupExpired()
                    }

                    Text("Individual files are copied. Folders are tracked in place and their originals go to Trash when they expire.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            settingsCard(title: "Help", subtitle: "A quick refresher", icon: "questionmark.circle") {
                settingsAction(
                    title: "Show welcome guide",
                    detail: "Replay the four-page introduction to TEMP.",
                    icon: "book.closed"
                ) {
                    showingWelcome = true
                }
            }

            settingsCard(title: "About TEMP", subtitle: "See which version is installed on this Mac", icon: "info.circle") {
                HStack(spacing: 14) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 55, height: 55)
                        .background(Color.accentColor.opacity(0.09),
                                    in: RoundedRectangle(cornerRadius: 15))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("TEMP for macOS")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                        Text("Version \(appVersion) (Build \(appBuild))")
                            .font(.system(size: 12, weight: .medium))
                            .monospacedDigit()
                        Text("These numbers come from the installed app, not GitHub.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }

                Divider()

                settingsAction(
                    title: "See latest builds on GitHub",
                    detail: "Compare this installed build with the latest macOS build.",
                    icon: "arrow.up.right.square"
                ) {
                    guard let url = URL(string: "https://github.com/K1ng-Kat/TEMP/actions/workflows/mac-build.yml") else { return }
                    NSWorkspace.shared.open(url)
                }

                Text("A successful GitHub build does not automatically update the app installed on this Mac.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func settingsCard<Content: View>(
        title: String,
        subtitle: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 36, height: 36)
                    .background(Color.primary.opacity(0.055),
                                in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            content()
        }
        .padding(19)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.primary.opacity(0.075), lineWidth: 0.75)
        }
    }

    private func settingsAction(
        title: String,
        detail: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 27)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var overview: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 12)], spacing: 12) {
            metric(title: "In TEMP", count: store.items.count, detail: "Tracked items", symbol: "square.stack.3d.up")
            metric(title: "Expiring soon", count: store.expiringCount, detail: "Within 24 hours", symbol: "clock")
            metric(title: "Pinned", count: store.pinnedCount, detail: "Kept indefinitely", symbol: "pin")
        }
    }

    private func metric(title: String, count: Int, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 33, height: 33)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(count.formatted()).font(.title3.weight(.semibold)).monospacedDigit()
                Text(detail).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 91, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.primary.opacity(0.075), lineWidth: 0.75)
        }
    }

    // MARK: - Empty-state onboarding

    private var welcomeDropZone: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 13) {
                Text("YOUR WORKSPACE")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.1)
                    .foregroundStyle(.secondary)
                Text("Keep it temporary.")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                Text("Add files or folders to get started. TEMP handles the expiration.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 9) {
                    Button {
                        showingFilesPicker = true
                    } label: { Label("Add files", systemImage: "plus") }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut("o", modifiers: .command)
                    Button {
                        showingFoldersPicker = true
                    } label: { Label("Track folder", systemImage: "folder") }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .keyboardShortcut("o", modifiers: [.command, .shift])
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: isDropTargeted ? "arrow.down.doc" : "folder.badge.clock")
                .font(.system(size: 65, weight: .ultraLight))
                .foregroundStyle(Color.secondary.opacity(0.5))
                .frame(width: 100, height: 110)
                .accessibilityHidden(true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(
                    Color.primary.opacity(isDropTargeted ? 0.3 : 0.08),
                    style: StrokeStyle(lineWidth: 1, dash: isDropTargeted ? [7, 5] : [])
                )
        }
    }

    private var gettingStarted: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
            Text("Files are copied to TEMP storage. Tracked folders stay in place and go to Trash on expiration.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(15)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Library and lifetime

    private func upcomingCard(_ item: TempItem) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let until = max(0, (item.expiresAt ?? .distantFuture).timeIntervalSince(timeline.date))
            let total = max(1, (item.expiresAt ?? timeline.date).timeIntervalSince(item.importedAt))
            let progress = min(1, max(0, 1 - until / total))

            HStack(spacing: 18) {
                Image(systemName: "hourglass.bottomhalf.filled")
                    .font(.system(size: 21))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 10) {
                        Text("NEXT TO GO")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(Color.accentColor)
                        Text(item.name)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                    }
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.accentColor.opacity(0.11))
                            Capsule()
                                .fill(LinearGradient(
                                    colors: [Color.accentColor, Color.purple],
                                    startPoint: .leading, endPoint: .trailing
                                ))
                                .frame(width: max(3, geometry.size.width * progress))
                        }
                    }
                    .frame(height: 5)
                    Text("TEMP will move this copy to Trash when its time is up.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(item.expiresAt ?? .now, style: .relative)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.accentColor)
                    .frame(minWidth: 90, alignment: .trailing)
            }
            .padding(16)
            .background(Color.accentColor.opacity(0.055), in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .strokeBorder(Color.accentColor.opacity(0.12))
            }
        }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(section.title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text(section.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    TextField("Search items", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 10)
                .frame(width: 152, height: 30)
                .background(TEMPStyle.panel, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(TEMPStyle.hairline)
                }

                Picker("Sort", selection: $sortMode) {
                    ForEach(SortMode.allCases) { sort in
                        Text(sort.rawValue).tag(sort)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 135)
            }

            if visibleItems.isEmpty {
                sectionEmptyState
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(visibleItems) { item in
                        fileRow(item)
                    }
                }
            }
        }
    }

    private var sectionEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: searchText.isEmpty ? section.icon : "magnifyingglass")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Color.accentColor.opacity(0.7))
                .frame(width: 60, height: 60)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            Text(searchText.isEmpty ? "Nothing here yet" : "No matching files")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            Text(searchText.isEmpty
                 ? "Files will appear here as soon as they match this view."
                 : "Try a different name or clear your search.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if !searchText.isEmpty {
                Button("Clear search") { searchText = "" }
                    .buttonStyle(.bordered)
            } else {
                Button("Import files") { showingFilesPicker = true }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .background(TEMPStyle.panel.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(TEMPStyle.hairline)
        }
    }

    private func fileRow(_ item: TempItem) -> some View {
        HStack(spacing: 13) {
            Image(systemName: item.isFolder ? "folder.fill" : "doc.fill")
                .font(.system(size: 18))
                .foregroundStyle(item.isFolder ? .blue : Color.accentColor)
                .frame(width: 43, height: 43)
                .background(
                    item.isFolder ? Color.blue.opacity(0.09) : Color.accentColor.opacity(0.085),
                    in: RoundedRectangle(cornerRadius: 11)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(item.subtitle)  ·  Added \(item.importedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)

            if item.isPinned {
                Label("Kept forever", systemImage: "pin.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.green)
                    .lineLimit(1)
            } else if let expiration = item.expiresAt {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(expiration, style: .relative)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(item.isExpiringSoon ? .orange : Color.accentColor)
                    Text(expiration.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .frame(minWidth: 100, alignment: .trailing)
            }

            Button {
                store.togglePin(for: item.id)
            } label: {
                Image(systemName: item.isPinned ? "pin.slash" : "pin")
                    .font(.system(size: 12))
                    .frame(width: 24, height: 27)
            }
            .buttonStyle(.borderless)
            .help(item.isPinned ? "Unpin (expires in 24 hours)" : "Keep forever")

            Menu {
                Button("Open") { store.open(item) }
                Button("Show in Finder") { store.showInFinder(item) }
                Divider()
                Menu("Change lifetime") {
                    ForEach(ExpirationPreset.allCases) { preset in
                        Button(preset.title) {
                            store.setExpiration(for: item.id, to: preset.expirationDate())
                        }
                    }
                    Divider()
                    Button("Choose a date…") {
                        customDate = max(
                            item.expiresAt ?? Date().addingTimeInterval(24 * 60 * 60),
                            Date().addingTimeInterval(60)
                        )
                        editingExpiration = item
                    }
                }
                Divider()
                if item.isInPlaceFolder {
                    Button("Stop tracking (keep folder)") {
                        store.stopTracking(item)
                    }
                    Divider()
                }
                Button("Move to Trash", role: .destructive) {
                    pendingTrash = item
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 23, height: 27)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder(TEMPStyle.hairline)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { store.open(item) }
        .contextMenu {
            Button("Open") { store.open(item) }
            Button("Show in Finder") { store.showInFinder(item) }
            Divider()
            Button(item.isPinned ? "Unpin" : "Keep forever") { store.togglePin(for: item.id) }
            if item.isInPlaceFolder {
                Button("Stop tracking (keep folder)") { store.stopTracking(item) }
            }
            Button("Move to Trash", role: .destructive) { pendingTrash = item }
        }
    }

    private var bottomNote: some View {
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: "checkmark.shield")
                .foregroundStyle(.green)
            Text("Files expire from TEMP storage. Tracked folders expire at their original location.")
            Spacer(minLength: 10)
            Button("Clean up now") { store.cleanupExpired() }
                .buttonStyle(.link)
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .padding(.top, 3)
    }

    private func customExpirationSheet(for item: TempItem) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 25))
                .foregroundStyle(Color.accentColor)
            Text("Choose a lifetime")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text(item.isInPlaceFolder ? "TEMP will move the original folder to Trash." : "TEMP will move its managed copy to Trash.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            DatePicker("Expires on", selection: $customDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.field)
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { editingExpiration = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Save lifetime") {
                    store.setExpiration(for: item.id, to: customDate)
                    editingExpiration = nil
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(25)
        .frame(width: 420)
    }

    // MARK: - Import handling

    private func importRequestedURLs(_ urls: [URL], expiresAfter duration: TimeInterval?) {
        let folders = urls.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        }
        let files = urls.filter { !folders.contains($0) }
        if !files.isEmpty { store.importURLs(files, expiresAfter: duration) }
        if !folders.isEmpty {
            pendingFolderURLs.append(contentsOf: folders)
            pendingFolderDuration = duration
            confirmingFolderImport = true
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            importRequestedURLs(urls, expiresAfter: chosenExpiration.duration)
        case .failure(let error):
            store.errorMessage = error.localizedDescription
        }
    }

    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        let valid = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !valid.isEmpty else { return false }
        let duration = chosenExpiration.duration
        for provider in valid {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { value, error in
                if let error {
                    Task { @MainActor in store.errorMessage = error.localizedDescription }
                    return
                }
                let url: URL?
                if let value = value as? URL {
                    url = value
                } else if let data = value as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let string = value as? String {
                    url = URL(string: string)
                } else {
                    url = nil
                }
                guard let url, url.isFileURL else { return }
                Task { @MainActor in
                    importRequestedURLs([url], expiresAfter: duration)
                }
            }
        }
        return true
    }
}


// MARK: - Welcome guide
// Deliberately lives next to the root view so this is included in the existing
// Xcode target without creating a second project-file dependency.

private enum TEMPWelcomeStep: Int, CaseIterable {
    case introduction
    case files
    case folders
    case control

    var icon: String {
        switch self {
        case .introduction: "hourglass"
        case .files: "doc.on.doc"
        case .folders: "folder"
        case .control: "slider.horizontal.3"
        }
    }

    var eyebrow: String {
        switch self {
        case .introduction: "MEET TEMP"
        case .files: "TEMPORARY FILES"
        case .folders: "FOLDERS STAY PUT"
        case .control: "YOU'RE IN CONTROL"
        }
    }

    var headline: String {
        switch self {
        case .introduction: "Your files. On your terms."
        case .files: "Keep the original."
        case .folders: "No duplicate folders."
        case .control: "Set it. Change it. Keep it."
        }
    }

    var explanation: String {
        switch self {
        case .introduction:
            "TEMP is a simple place for the files and folders you only need for a little while. Give an item a lifetime, and TEMP handles cleanup."
        case .files:
            "Import a file and TEMP makes a managed copy. Use that copy for temporary work. When it expires, only TEMP's copy goes to Trash."
        case .folders:
            "Choose a folder and TEMP tracks it exactly where it lives. Nothing is duplicated. When it expires, the original folder and everything inside it go to Trash."
        case .control:
            "Change an expiration any time, pin an item to keep it, or stop tracking a folder without deleting it. Cleanup runs while TEMP is open and resumes at the next launch."
        }
    }

    var detail: String {
        switch self {
        case .introduction:
            "Less clutter, without another folder to organize."
        case .files:
            "Your original file stays untouched."
        case .folders:
            "TEMP asks before tracking any original folder."
        case .control:
            "Expired items go to macOS Trash, not permanent deletion."
        }
    }
}

private struct TEMPWelcomeExperience: View {
    let onFinish: () -> Void
    let onImportFiles: () -> Void
    let onTrackFolder: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stepIndex = 0
    @State private var forward = true
    @State private var revealed = false

    private var step: TEMPWelcomeStep {
        TEMPWelcomeStep(rawValue: stepIndex) ?? .introduction
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "hourglass")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 38, height: 38)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("TEMP")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("A quick introduction")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Skip") { onFinish() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .contentShape(Rectangle())
                    .accessibilityHint("Closes the welcome guide")
            }
            .padding(.bottom, 23)

            ZStack {
                pageContent(step)
                    .id(stepIndex)
                    .transition(pageTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Step \(stepIndex + 1) of \(TEMPWelcomeStep.allCases.count)")

            HStack(spacing: 7) {
                ForEach(0..<TEMPWelcomeStep.allCases.count, id: \.self) { index in
                    Button {
                        go(to: index)
                    } label: {
                        Capsule()
                            .fill(index == stepIndex ? Color.accentColor : Color.primary.opacity(0.13))
                            .frame(width: index == stepIndex ? 24 : 8, height: 7)
                            .contentShape(Rectangle())
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show guide page \(index + 1)")
                    .accessibilityAddTraits(index == stepIndex ? .isSelected : [])
                }

                Spacer()

                Text("\(stepIndex + 1) / \(TEMPWelcomeStep.allCases.count)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)

            Divider()
                .padding(.bottom, 18)

            HStack(spacing: 9) {
                if stepIndex > 0 {
                    Button("Back") { go(to: stepIndex - 1) }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }

                Spacer()

                if stepIndex < TEMPWelcomeStep.allCases.count - 1 {
                    Button {
                        go(to: stepIndex + 1)
                    } label: {
                        Label("Continue", systemImage: "arrow.right")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Import a file") { onImportFiles() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    Button("Track a folder") { onTrackFolder() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    Button("Get started") { onFinish() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(29)
        .frame(width: 730, height: 480)
        .background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.12),
                        Color.purple.opacity(0.065),
                        Color.clear,
                        Color.cyan.opacity(0.035)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onAppear {
            withAnimation(reduceMotion ? .linear(duration: 0.01) : .easeOut(duration: 0.55)) {
                revealed = true
            }
        }
    }

    private func pageContent(_ current: TEMPWelcomeStep) -> some View {
        HStack(alignment: .center, spacing: 26) {
            illustration(for: current)
                .frame(width: 234, height: 238)
                .scaleEffect(revealed ? 1 : 0.92)
                .opacity(revealed ? 1 : 0.25)

            VStack(alignment: .leading, spacing: 14) {
                Text(current.eyebrow)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(Color.accentColor)

                Text(current.headline)
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .tracking(-0.4)
                    .fixedSize(horizontal: false, vertical: true)

                Text(current.explanation)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(4)

                Label(current.detail, systemImage: current == .folders ? "exclamationmark.shield" : "checkmark.shield")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(current == .folders ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func illustration(for current: TEMPWelcomeStep) -> some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.085))
                .frame(width: 216, height: 216)

            Circle()
                .strokeBorder(Color.accentColor.opacity(0.15), lineWidth: 1)
                .frame(width: 178, height: 178)

            RoundedRectangle(cornerRadius: 29, style: .continuous)
                .fill(.ultraThinMaterial)
                .frame(width: 142, height: 142)
                .overlay {
                    RoundedRectangle(cornerRadius: 29, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
                }
                .rotationEffect(.degrees(current == .control ? 7 : -6))

            Image(systemName: current.icon)
                .font(.system(size: 66, weight: .ultraLight))
                .foregroundStyle(Color.accentColor)
                .contentTransition(.symbolEffect(.replace))
                .symbolRenderingMode(.hierarchical)
                .shadow(color: Color.accentColor.opacity(0.13), radius: 12)
        }
        .accessibilityHidden(true)
    }

    private func go(to index: Int) {
        guard index != stepIndex,
              (0..<TEMPWelcomeStep.allCases.count).contains(index) else { return }
        forward = index > stepIndex
        withAnimation(reduceMotion ? .linear(duration: 0.12) : .spring(response: 0.43, dampingFraction: 0.87)) {
            stepIndex = index
        }
    }
}
