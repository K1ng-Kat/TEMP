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
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 175, ideal: 190, max: 202)
        } detail: {
            workspace
        }
        .tint(TEMPStyle.purple)
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
            Text("Only the copy stored by TEMP goes to Trash. Your original remains untouched.")
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
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(LinearGradient(
                            colors: [TEMPStyle.purple, TEMPStyle.violet],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                    Image(systemName: "hourglass")
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text("TEMP")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .tracking(-0.6)
                    Text("v0.2 · LESS TO KEEP.")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.15)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 52)
            .padding(.bottom, 25)

            Text("WORKSPACE")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 23)
                .padding(.bottom, 10)

            VStack(spacing: 4) {
                sidebarRow(.all, count: store.items.count)
                sidebarRow(.expiringSoon, count: store.expiringCount)
                sidebarRow(.pinned, count: store.pinnedCount)
            }
            .padding(.horizontal, 11)

            Spacer(minLength: 24)

            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your originals are safe")
                            .font(.system(size: 11, weight: .semibold))
                        Text("TEMP works on copies only.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                Rectangle()
                    .fill(TEMPStyle.hairline)
                    .frame(height: 1)

                Button {
                    store.showLibraryInFinder()
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "folder")
                        Text("Reveal storage")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(TEMPStyle.panel.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 11)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func sidebarRow(_ target: TempSection, count: Int) -> some View {
        let active = section == target
        return Button {
            withAnimation(.easeInOut(duration: 0.16)) { section = target }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: target.icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 22)
                    .foregroundStyle(active ? TEMPStyle.purple : Color.secondary)
                Text(target.title)
                    .font(.system(size: 12, weight: active ? .semibold : .medium))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(active ? TEMPStyle.purple : Color.secondary.opacity(0.65))
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .frame(height: 39)
            .background(
                active ? TEMPStyle.purple.opacity(0.115) : .clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Main workspace

    private var workspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                topBar
                introCard
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
            .frame(maxWidth: 1060, alignment: .leading)
            .padding(.horizontal, 23)
            .padding(.top, 22)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(TEMPStyle.purple, style: StrokeStyle(lineWidth: 3, dash: [10, 7]))
                    .padding(9)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted, perform: acceptDrop)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 7, height: 7)
                Text("READY WHEN YOU ARE")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 10)

            Picker("New items expire after", selection: expirationSelection) {
                ForEach(ExpirationPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 142)
            .help("Default lifetime for newly imported items")

            Menu {
                Button("Import files…", systemImage: "doc.badge.plus") {
                    showingFilesPicker = true
                }
                Button("Import folders…", systemImage: "folder.badge.plus") {
                    showingFoldersPicker = true
                }
            } label: {
                Label("Add items", systemImage: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 4)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .frame(height: 32)
    }

    private var introCard: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("YOUR SHORT-STAY WORKSPACE")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(TEMPStyle.purple)

                Text("Everything you need. Nothing you don’t.")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .tracking(-0.9)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)

                Text("Keep what matters now. Let the rest clear itself later.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .fill(TEMPStyle.purple.opacity(0.07))
                    .frame(width: 93, height: 93)
                Circle()
                    .stroke(TEMPStyle.purple.opacity(0.15), lineWidth: 1)
                    .frame(width: 76, height: 76)
                Circle()
                    .stroke(TEMPStyle.purple.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [3, 6]))
                    .frame(width: 91, height: 91)
                Image(systemName: "hourglass")
                    .font(.system(size: 37, weight: .ultraLight))
                    .foregroundStyle(TEMPStyle.purple)
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: 105, height: 94)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 114, alignment: .leading)
        .background(
            LinearGradient(
                colors: [TEMPStyle.purple.opacity(0.085), TEMPStyle.violet.opacity(0.025)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(TEMPStyle.purple.opacity(0.13))
        }
    }

    private var overview: some View {
        HStack(spacing: 12) {
            metric(title: "IN YOUR SPACE", count: store.items.count, detail: "Managed copies", symbol: "square.stack.3d.up.fill", accent: TEMPStyle.purple)
            metric(title: "EXPIRING SOON", count: store.expiringCount, detail: "Within 24 hours", symbol: "clock.fill", accent: .orange)
            metric(title: "PINNED", count: store.pinnedCount, detail: "Here to stay", symbol: "pin.fill", accent: .green)
        }
    }

    private func metric(title: String, count: Int, detail: String, symbol: String, accent: Color) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: 38, height: 38)
                .background(accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(count.formatted())
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .frame(maxWidth: .infinity, minHeight: 65)
        .background(TEMPStyle.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(TEMPStyle.hairline)
        }
    }

    // MARK: - Empty-state onboarding

    private var welcomeDropZone: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    Image(systemName: "circle.dotted.circle.fill")
                        .foregroundStyle(TEMPStyle.purple)
                    Text("DROP ZONE")
                        .tracking(1.3)
                        .foregroundStyle(TEMPStyle.purple)
                }
                .font(.system(size: 10, weight: .bold))

                Text(isDropTargeted ? "Drop it like it’s gone." : "Make space without the mess.")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .tracking(-0.45)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)

                Text("Drop files anywhere, or import below. TEMP stores copies, then moves them to Trash when their time is up.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button {
                        showingFilesPicker = true
                    } label: {
                        Label("Add files", systemImage: "plus")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut("o", modifiers: .command)

                    Button {
                        showingFoldersPicker = true
                    } label: {
                        Label("Add folder", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 7) {
                ZStack {
                    Circle()
                        .stroke(TEMPStyle.purple.opacity(0.12), lineWidth: 12)
                    Circle()
                        .stroke(TEMPStyle.purple.opacity(0.55), style: StrokeStyle(lineWidth: 3, dash: [3, 7]))
                        .padding(12)
                    Circle()
                        .fill(TEMPStyle.purple.opacity(0.09))
                        .padding(21)
                    Image(systemName: isDropTargeted ? "arrow.down.doc.fill" : "hourglass")
                        .font(.system(size: 40, weight: .ultraLight))
                        .foregroundStyle(TEMPStyle.purple)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 116, height: 116)

                Text("AUTO-EXPIRES")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(.secondary)
                Text(chosenExpiration.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(TEMPStyle.purple)
                    .lineLimit(1)
            }
            .frame(width: 130)
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 25)
        .padding(.vertical, 17)
        .frame(maxWidth: .infinity, minHeight: 218, alignment: .leading)
        .background(
            LinearGradient(
                colors: [TEMPStyle.purple.opacity(isDropTargeted ? 0.16 : 0.07), TEMPStyle.violet.opacity(0.015)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    TEMPStyle.purple.opacity(isDropTargeted ? 0.7 : 0.21),
                    style: StrokeStyle(lineWidth: 1.3, dash: [6, 5])
                )
        }
        .animation(.easeOut(duration: 0.16), value: isDropTargeted)
    }

    private var gettingStarted: some View {
        HStack(spacing: 11) {
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(TEMPStyle.purple)
                .frame(width: 32, height: 32)
                .background(TEMPStyle.purple.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text("Pick a lifetime. Import. Done.")
                    .font(.system(size: 11, weight: .semibold))
                Text("No organizing or cleanup chores. TEMP takes care of its own copies.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "checkmark.shield")
                .font(.system(size: 17))
                .foregroundStyle(.green)
        }
        .padding(12)
        .background(TEMPStyle.panel.opacity(0.65), in: RoundedRectangle(cornerRadius: 13))
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
                    .foregroundStyle(TEMPStyle.purple)
                    .frame(width: 44, height: 44)
                    .background(TEMPStyle.purple.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 10) {
                        Text("NEXT TO GO")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(TEMPStyle.purple)
                        Text(item.name)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                    }
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(TEMPStyle.purple.opacity(0.11))
                            Capsule()
                                .fill(LinearGradient(
                                    colors: [TEMPStyle.purple, TEMPStyle.violet],
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
                    .foregroundStyle(TEMPStyle.purple)
                    .frame(minWidth: 90, alignment: .trailing)
            }
            .padding(16)
            .background(TEMPStyle.purple.opacity(0.055), in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .strokeBorder(TEMPStyle.purple.opacity(0.12))
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
                .foregroundStyle(TEMPStyle.purple.opacity(0.7))
                .frame(width: 60, height: 60)
                .background(TEMPStyle.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
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
                .foregroundStyle(item.isFolder ? .blue : TEMPStyle.purple)
                .frame(width: 43, height: 43)
                .background(
                    item.isFolder ? Color.blue.opacity(0.09) : TEMPStyle.purple.opacity(0.085),
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
                        .foregroundStyle(item.isExpiringSoon ? .orange : TEMPStyle.purple)
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
        .background(TEMPStyle.panel.opacity(0.75), in: RoundedRectangle(cornerRadius: 13))
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
            Text("Only managed copies expire. Originals stay untouched.")
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
                .foregroundStyle(TEMPStyle.purple)
            Text("Choose a lifetime")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text("Pick when TEMP should move its copy of \(item.name) to Trash.")
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

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            store.importURLs(urls, expiresAfter: chosenExpiration.duration)
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
                    store.importURLs([url], expiresAfter: duration)
                }
            }
        }
        return true
    }
}
