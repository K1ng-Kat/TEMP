import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: TemporaryStore

    @State private var selection: TempSection? = .all
    @State private var defaultExpiration: ExpirationPreset = .oneDay
    @State private var showingFilesPicker = false
    @State private var showingFoldersPicker = false
    @State private var isDropTargeted = false
    @State private var pendingTrash: TempItem?
    @State private var editingExpiration: TempItem?
    @State private var customDate = Date().addingTimeInterval(24 * 60 * 60)

    private var currentSection: TempSection { selection ?? .all }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Library") {
                    ForEach(TempSection.allCases) { section in
                        Label(section.title, systemImage: section.icon)
                            .tag(section)
                    }
                }

                Section("Storage") {
                    Button {
                        store.showLibraryInFinder()
                    } label: {
                        Label("Reveal TEMP storage", systemImage: "folder")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("TEMP")
            .navigationSplitViewColumnWidth(min: 205, ideal: 225)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 7) {
                    Label("Safe by design", systemImage: "checkmark.shield")
                        .font(.caption.weight(.semibold))
                    Text("TEMP only trashes imported copies. Your original files stay untouched.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } detail: {
            mainContent
        }
        .tint(.indigo)
        .fileImporter(
            isPresented: $showingFilesPicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .fileImporter(
            isPresented: $showingFoldersPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .sheet(item: $editingExpiration) { item in
            VStack(alignment: .leading, spacing: 18) {
                Text("Custom expiration")
                    .font(.title2.bold())
                Text("Choose when TEMP should move its copy of \(item.name) to Trash.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                DatePicker(
                    "Expires",
                    selection: $customDate,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                Divider()
                HStack {
                    Spacer()
                    Button("Cancel") { editingExpiration = nil }
                        .keyboardShortcut(.cancelAction)
                    Button("Save") {
                        store.setExpiration(for: item.id, to: customDate)
                        editingExpiration = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 410)
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
            Text("Only TEMP's managed copy is moved to Trash. The original is not affected.")
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

    private var mainContent: some View {
        VStack(spacing: 0) {
            header
            Divider()
            overview
            Divider()

            let visibleItems = store.items(in: currentSection)
            if visibleItems.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(visibleItems) { item in
                            fileRow(item)
                        }
                    }
                    .padding(22)
                }
            }

            Divider()
            HStack(spacing: 7) {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text("Expired items move to Trash while TEMP runs, or when you next open it.")
                Spacer()
                Button("Clean up now") { store.cleanupExpired() }
                    .buttonStyle(.link)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.indigo, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
            acceptDrop(providers)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    Image(systemName: "hourglass")
                        .font(.title2.weight(.medium))
                        .foregroundStyle(.indigo)
                    Text(currentSection.title)
                        .font(.largeTitle.bold())
                }
                Text(currentSection.detail)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 10)
            VStack(alignment: .trailing, spacing: 4) {
                Text("New items expire after")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Default expiration", selection: $defaultExpiration) {
                    ForEach(ExpirationPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 146)
            }

            Menu {
                Button("Import files…", systemImage: "doc.badge.plus") {
                    showingFilesPicker = true
                }
                Button("Import folders…", systemImage: "folder.badge.plus") {
                    showingFoldersPicker = true
                }
            } label: {
                Label("Add items", systemImage: "plus")
                    .fontWeight(.semibold)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
    }

    private var overview: some View {
        HStack(spacing: 12) {
            statCard(title: "IN TEMP", number: store.items.count, symbol: "square.stack", color: .indigo)
            statCard(title: "EXPIRING SOON", number: store.expiringCount, symbol: "clock", color: .orange)
            statCard(title: "PINNED", number: store.pinnedCount, symbol: "pin.fill", color: .green)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 15)
    }

    private func statCard(title: String, number: Int, symbol: String, color: Color) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 35, height: 35)
                .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(number.formatted())
                    .font(.title2.bold())
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 13))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: currentSection == .pinned ? "pin.slash" :
                    currentSection == .expiringSoon ? "clock" : "tray")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(.tertiary)
            Text(currentSection == .all ? "Your TEMP space is ready" :
                 currentSection == .pinned ? "Nothing pinned yet" : "Nothing expiring soon")
                .font(.title2.weight(.semibold))
            Text(currentSection == .all
                 ? "Drop files or folders here, or use Add items.\nTEMP keeps your originals untouched."
                 : currentSection == .pinned
                 ? "Pin a file to keep its managed copy indefinitely."
                 : "Items expiring within 24 hours will show up here.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if currentSection == .all {
                Button {
                    showingFilesPicker = true
                } label: {
                    Label("Import your first files", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fileRow(_ item: TempItem) -> some View {
        HStack(spacing: 13) {
            Image(systemName: item.isFolder ? "folder.fill" : "doc.fill")
                .font(.title2)
                .foregroundStyle(item.isFolder ? .blue : .indigo)
                .frame(width: 42, height: 42)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 5) {
                Text(item.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text("\(item.subtitle) · Added \(item.importedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            if item.isPinned {
                Label("Pinned", systemImage: "pin.fill")
                    .foregroundStyle(.green)
                    .font(.caption.weight(.medium))
            } else if let expiration = item.expiresAt {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(expiration, style: .relative)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(item.isExpiringSoon ? .orange : .primary)
                    Text(expiration.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                store.togglePin(for: item.id)
            } label: {
                Image(systemName: item.isPinned ? "pin.slash" : "pin")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help(item.isPinned ? "Unpin (expires in 24 hours)" : "Pin forever")

            Menu {
                Button("Open") { store.open(item) }
                Button("Show in Finder") { store.showInFinder(item) }
                Divider()
                Menu("Change expiration") {
                    ForEach(ExpirationPreset.allCases) { preset in
                        Button(preset.title) {
                            store.setExpiration(for: item.id, to: preset.expirationDate())
                        }
                    }
                    Divider()
                    Button("Choose date…") {
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
                    .frame(width: 25, height: 25)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { store.open(item) }
        .contextMenu {
            Button("Open") { store.open(item) }
            Button("Show in Finder") { store.showInFinder(item) }
            Divider()
            Button(item.isPinned ? "Unpin" : "Pin forever") {
                store.togglePin(for: item.id)
            }
            Button("Move to Trash", role: .destructive) { pendingTrash = item }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            store.importURLs(urls, expiresAfter: defaultExpiration.duration)
        case .failure(let error):
            store.errorMessage = error.localizedDescription
        }
    }

    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        let duration = defaultExpiration.duration

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadItem(
                forTypeIdentifier: UTType.fileURL.identifier,
                options: nil
            ) { value, error in
                guard error == nil else { return }
                let url: URL?
                if let value = value as? URL {
                    url = value
                } else if let value = value as? Data {
                    url = URL(dataRepresentation: value, relativeTo: nil)
                } else if let value = value as? String {
                    url = URL(string: value)
                } else {
                    url = nil
                }
                guard let url, url.isFileURL else { return }
                DispatchQueue.main.async {
                    store.importURLs([url], expiresAfter: duration)
                }
            }
        }
        return true
    }
}
