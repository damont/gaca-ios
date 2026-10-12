import SwiftUI

/// Pages your crew has made for you, in the order you keep them.
struct ArtifactsView: View {
    @Environment(AppModel.self) private var model
    @State private var artifacts: [Artifact] = []
    @State private var showArchived = false
    @State private var query = ""
    @State private var loading = true
    @State private var error: String?
    @State private var confirmDelete: Artifact?
    @State private var editMode: EditMode = .inactive

    private var shown: [Artifact] {
        query.isEmpty ? artifacts : artifacts.filter {
            $0.title.localizedCaseInsensitiveContains(query) || ($0.description ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List {
            if let error { ErrorLine(text: error).listRowBackground(Color.clear) }
            if loading && artifacts.isEmpty {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            } else if shown.isEmpty {
                EmptyState(mark: query.isEmpty ? .wingsLevel : nil,
                           title: query.isEmpty ? "Nothing here yet." : "No pages match.",
                           message: query.isEmpty ? "Ask your crew for a page (a Costco list, a trip planner, a tracker) and it will show up here." : nil)
                    .listRowBackground(Color.clear)
            }
            Section {
                ForEach(shown) { artifact in
                    NavigationLink(value: Route.artifact(artifact.id)) {
                        ArtifactRow(artifact: artifact, style: model.style(for: artifact.crew))
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { confirmDelete = artifact } label: { Label("Delete", systemImage: "trash") }
                        Button { setArchived(artifact, !(artifact.archived ?? false)) } label: {
                            Label(artifact.archived == true ? "Unarchive" : "Archive", systemImage: "archivebox")
                        }
                        .tint(Color(hex: "#7A838C"))
                    }
                    .contextMenu {
                        if artifact.id != artifacts.first?.id {
                            Button("Move to top", systemImage: "arrow.up.to.line") { moveToTop(artifact) }
                        }
                        Button(artifact.archived == true ? "Unarchive" : "Archive", systemImage: "archivebox") {
                            setArchived(artifact, !(artifact.archived ?? false))
                        }
                        Button("Delete…", systemImage: "trash", role: .destructive) { confirmDelete = artifact }
                    }
                }
                .onMove(perform: move)
                .moveDisabled(!query.isEmpty)
            }
        }
        .listStyle(.insetGrouped)
        .gacaPage()
        .navigationTitle("Artifacts")
        .searchable(text: $query, prompt: "Search pages")
        .environment(\.editMode, $editMode)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(editMode.isEditing ? "Done" : "Edit") {
                    withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                }
                .disabled(artifacts.count < 2 || !query.isEmpty)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Toggle("Show archived", isOn: $showArchived)
                } label: {
                    Image(systemName: showArchived ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Filter")
                SettingsButton()
            }
        }
        .confirmationDialog(deleteTitle, isPresented: deleting, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let a = confirmDelete { delete(a) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The page and everything it stored will be gone for good. Archive it instead to just tidy it away.")
        }
        .refreshable { await load() }
        .task(id: showArchived) { await load() }
    }

    private var deleteTitle: String {
        confirmDelete.map { "Delete \u{201C}\($0.title)\u{201D}?" } ?? ""
    }

    private var deleting: Binding<Bool> {
        Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            if model.crew.isEmpty { try? await model.refreshCrew() }
            artifacts = try await model.api.artifacts(includeArchived: showArchived)
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func act(_ work: @escaping () async throws -> Void) {
        Task {
            do { try await work() } catch { self.error = error.localizedDescription }
            await load()
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        artifacts.move(fromOffsets: source, toOffset: destination)
        let ids = artifacts.map(\.id)
        act { _ = try await model.api.reorderArtifacts(ids) }
    }

    private func moveToTop(_ artifact: Artifact) {
        act { _ = try await model.api.reorderArtifacts([artifact.id]) }
    }

    private func setArchived(_ artifact: Artifact, _ archived: Bool) {
        act { _ = try await model.api.patchArtifact(artifact.id, ArtifactPatch(archived: archived)) }
    }

    private func delete(_ artifact: Artifact) {
        artifacts.removeAll { $0.id == artifact.id }
        act { try await model.api.deleteArtifact(artifact.id) }
    }
}

struct ArtifactRow: View {
    let artifact: Artifact
    let style: CrewStyle

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(style.ink)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 11).fill(style.tint))
            VStack(alignment: .leading, spacing: 2) {
                Text(artifact.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.textPrimary).lineLimit(1)
                if let description = artifact.description {
                    Text(description).font(.system(size: 14)).foregroundStyle(Palette.textSecondary).lineLimit(2)
                }
                HStack(spacing: 0) {
                    if let crew = artifact.crew {
                        Text(crewDisplayName(crew)).fontWeight(.semibold).foregroundStyle(style.ink)
                        Text(" · ")
                    }
                    Text("updated \(RelativeTime.short(artifact.updatedAt))")
                    if artifact.archived == true { Text(" · archived") }
                }
                .font(.system(size: 12))
                .foregroundStyle(Palette.textSecondary)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }
}
