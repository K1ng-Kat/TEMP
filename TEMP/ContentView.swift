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
    @State private var searchText = ""
    @AppStorage("TEMP.sidebar.visible") private var sidebarVisible = true
    @State private var compactSidebarOpen = false
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
                        colors: [Color.accentColor.opacity(0.15), Color.purple.opacity(0.07), .clear, Color.cyan.opacity(0.05)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                }
                .ignoresSafeArea()
                HStack(spacing: 0) {
                    if !compact && sidebarVisible {
                        sidebar.frame(width: 216)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    workspace
                        .frame(width: max(1, geometry.size.width - sidebarWidth))
                }
                .padding(.top, 44)

                if compact && compactSidebarOpen {
                    Color.black.opacity(0.16)
                        .ignoresSafeArea()
                        .onTapGesture { compactSidebarOpen = false }
                    sidebar
                        .frame(width: min(244, geometry.size.width - 50))
                        .padding(.top, 44)
                        .shadow(color: .black.opacity(0.15), radius: 19, x: 4, y: 0)
                        .transition(.move(edge: .leading))
                }

                HStack {
                    Button {
                        withAnimation(.smooth(duration: 0.26)) {
                            if compact { compactSidebarOpen.toggle() }
                            else { sidebarVisible.toggle() }
                        }
                    } label: {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.75)
                    }
                    .help("Toggle Sidebar")
                    Spacer()
                }
                .padding(.leading, sidebarWidth > 0 ? sidebarWidth + 12 : 83)
                .padding(.top, 7)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .onChange(of: section) { _, _ in compactSidebarOpen = false }
        }
        .tint(.accentColor)
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
            .padding(.top, 20)
            .padding(.bottom, 28)

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
            }
            .padding(.horizontal, 10)
            Spacer(minLength: 12)
            VStack(alignment: .leading, spacing: 13) {
                Divider()
                Button {
                    store.showLibraryInFinder()
                } label: {
                    Label("Reveal TEMP storage", systemImage: "folder")
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                Text("Files are copied. Folders stay in place.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 17)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.primary.opacity(0.075)).frame(width: 0.75)
        }
    }

    private func sidebarRow(_ target: TempSection, count: Int) -> some View {
        let active = section == target
        return Button {
            withAnimation(.easeInOut(duration: 0.16)) { section = target }
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

    private var workspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                topBar
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
            .frame(maxWidth: 1160, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 18)
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

    private var topBar: some View {
        HStack(alignment: .center, spacing: 13) {
            VStack(alignment: .leading, spacing: 6) {
                Text(section.title)
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                Text(section.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 5)
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
            Menu {
                Button("Import files…", systemImage: "doc.badge.plus") { showingFilesPicker = true }
                Button("Track folders…", systemImage: "folder.badge.plus") { showingFoldersPicker = true }
            } label: {
                Label("Add items", systemImage: "plus")
                    .font(.system(size: 12, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .frame(minHeight: 64)
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
