import SwiftUI

/// Pages your crew has made for you, pages people shared with you, and the public gallery
/// (gaca-android ArtifactsScreen: Mine / Shared with me / Gallery).
struct ArtifactsView: View {
    @Environment(AppModel.self) private var model
    @State private var artifacts: [Artifact] = []
    @State private var stale = false
    @State private var filter: ArtifactFilter = .mine
    @State private var showArchived = false
    @State private var query = ""
    @State private var loading = true
    @State private var error: String?
    @State private var editMode: EditMode = .inactive

    /// A one-line result (a bring home, a leave), with Undo beside it while a bring home can still be undone.
    @State private var notice: String?
    @State private var undo: UndoOffer?
    /// A bring home, undo or leave is running (bringing home can take a while).
    @State private var working = false

    @State private var confirmDelete: Artifact?
    @State private var confirmBringHome: Artifact?
    @State private var confirmLeave: Artifact?
    @State private var sharing: Artifact?
    @State private var publishing: Artifact?

    @State private var gallery = GalleryState()
    @State private var confirmInstall: Template?

    struct UndoOffer: Equatable {
        let id: String
        let title: String
        /// Nil when the server's time could not be read: offered until dismissed (the server refuses a late undo).
        let until: Date?
    }

    struct GalleryState {
        var loaded = false
        var loading = false
        var templates: [Template] = []
        var next: String?
        var loadingMore = false
        var problem: CloudBlock?
        var failure: String?
        var installingId: String?
    }

    private var isGallery: Bool { filter == .gallery }

    private var shown: [Artifact] {
        artifacts.filter { $0.matches(filter) }.filter {
            query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || ($0.description ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    private var shownTemplates: [Template] { gallery.templates.filter { $0.matches(query) } }

    var body: some View {
        List {
            Section {
                filterChips
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                    .moveDisabled(true)
            }
            banners
            if isGallery { galleryRows } else { pageRows }
        }
        .listStyle(.insetGrouped)
        .gacaPage()
        .navigationTitle("Artifacts")
        .searchable(text: $query, prompt: isGallery ? "Search the gallery" : "Search pages")
        .environment(\.editMode, $editMode)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !isGallery {
                    Button(editMode.isEditing ? "Done" : "Edit") {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                    .disabled(shown.count < 2 || !query.isEmpty)
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button("Add a shared page", systemImage: "link.badge.plus") { model.push(.join) }
                    if !isGallery { Toggle("Show archived", isOn: $showArchived) }
                } label: {
                    Image(systemName: showArchived ? "line.3.horizontal.decrease.circle.fill" : "ellipsis.circle")
                }
                .accessibilityLabel("More")
                SettingsButton()
            }
        }
        .confirmationDialog(confirmDelete.map { "Delete \u{201C}\($0.title)\u{201D}?" } ?? "", isPresented: present($confirmDelete), titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let a = confirmDelete { delete(a) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The page and everything it stored will be gone for good. Archive it instead to just tidy it away.")
        }
        .alert(confirmBringHome.map { "Bring \u{201C}\($0.title)\u{201D} home?" } ?? "", isPresented: present($confirmBringHome), presenting: confirmBringHome) { a in
            Button("Bring home") { bringHome(a) }
            Button("Cancel", role: .cancel) {}
        } message: { a in
            Text(a.bringHomeWarning)
        }
        .alert(confirmLeave.map { "Leave \u{201C}\($0.title)\u{201D}?" } ?? "", isPresented: present($confirmLeave), presenting: confirmLeave) { a in
            Button("Leave", role: .destructive) { leave(a) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It disappears from your list. To get back in, you would need a new link from its owner.")
        }
        .alert(confirmInstall.map { "Add \u{201C}\($0.title)\u{201D}?" } ?? "", isPresented: present($confirmInstall), presenting: confirmInstall) { t in
            Button("Add a copy") { install(t) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("A copy is made on your server and appears under Mine. It is private to you until you share it.")
        }
        .sheet(item: $sharing, onDismiss: { Task { await load() } }) { ShareSheet(artifact: $0) { Task { await load() } } }
        .sheet(item: $publishing, onDismiss: { Task { await load() } }) { PublishSheet(artifact: $0) }
        .refreshable { if isGallery { await loadGallery() } else { await load() } }
        .task(id: showArchived) { await load() }
        .onChange(of: filter) { _, new in
            editMode = .inactive
            if new == .gallery && !gallery.loaded { Task { await loadGallery() } }
        }
    }

    // MARK: Pieces

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ArtifactFilter.allCases) { f in
                    AllPill(title: f.rawValue, selected: filter == f) { withAnimation { filter = f } }
                }
            }
        }
    }

    @ViewBuilder private var banners: some View {
        if stale && !isGallery {
            Text("The cloud could not be reached, so shared pages are as they were last time.")
                .font(.system(size: 13)).foregroundStyle(Palette.textMeta)
                .listRowBackground(Color.clear)
        }
        if let notice {
            HStack(spacing: 10) {
                if working { ProgressView().tint(Palette.accent) }
                Text(notice)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.successInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let undo, !working {
                    Button("Undo") { undoBringHome(undo) }
                        .font(.system(size: 14, weight: .semibold))
                        .buttonStyle(.borderless)
                }
                if !working {
                    Button { self.notice = nil; self.undo = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Palette.textMeta)
                        .accessibilityLabel("Dismiss")
                }
            }
            .listRowBackground(Palette.successBg)
        }
        if let error { ErrorLine(text: error).listRowBackground(Color.clear) }
    }

    @ViewBuilder private var pageRows: some View {
        if loading && artifacts.isEmpty {
            ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
        } else if shown.isEmpty {
            emptyState.listRowBackground(Color.clear)
        }
        Section {
            ForEach(shown) { artifact in
                NavigationLink(value: Route.artifact(artifact.id)) {
                    ArtifactRow(artifact: artifact, style: model.style(for: artifact.crew))
                }
                .swipeActions(edge: .trailing) {
                    if artifact.canManage {
                        Button(role: .destructive) { confirmDelete = artifact } label: { Label("Delete", systemImage: "trash") }
                        Button { setArchived(artifact, !artifact.isArchived) } label: {
                            Label(artifact.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox")
                        }
                        .tint(Color(hex: "#7A838C"))
                    } else if artifact.canLeave && !working {
                        Button(role: .destructive) { confirmLeave = artifact } label: { Label("Leave", systemImage: "rectangle.portrait.and.arrow.right") }
                    }
                }
                .contextMenu { menu(for: artifact) }
            }
            .onMove(perform: move)
            .moveDisabled(!query.isEmpty)
        }
        if filter == .shared {
            Section {
                Button { model.push(.join) } label: {
                    Label("Add a shared page", systemImage: "link.badge.plus").foregroundStyle(Palette.accent)
                }
            } footer: {
                Text("Got a link to someone's page? Paste it to see what it is before you add it.")
            }
        }
    }

    @ViewBuilder private var emptyState: some View {
        if !query.isEmpty {
            EmptyState(title: "No pages match.")
        } else if filter == .shared {
            EmptyState(mark: .wingsLevel, title: "Nothing shared with you yet.",
                       message: "When someone sends you a link to a page, add it here and it will show up in this list.")
        } else {
            EmptyState(mark: .wingsLevel, title: "Nothing here yet.",
                       message: "Ask your crew for a page (a Costco list, a trip planner, a tracker) and it will show up here.")
        }
    }

    @ViewBuilder private func menu(for artifact: Artifact) -> some View {
        if query.isEmpty, artifact.id != artifacts.first?.id {
            Button("Move to top", systemImage: "arrow.up.to.line") { moveToTop(artifact) }
        }
        if artifact.canShare {
            Button("Share…", systemImage: "person.crop.circle.badge.plus") { sharing = artifact }
        }
        if artifact.canPublish {
            Button(artifact.publishedId != nil ? "Publish new version…" : "Publish…", systemImage: "globe") { publishing = artifact }
        }
        if artifact.canBringHome && !working {
            Button("Bring home…", systemImage: "house") { confirmBringHome = artifact }
        }
        if artifact.canLeave && !working {
            Button("Leave…", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { confirmLeave = artifact }
        }
        // Only the owner may archive or delete: the cloud refuses both to everyone else.
        if artifact.canManage {
            Button(artifact.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox") {
                setArchived(artifact, !artifact.isArchived)
            }
            Button("Delete…", systemImage: "trash", role: .destructive) { confirmDelete = artifact }
        }
    }

    @ViewBuilder private var galleryRows: some View {
        if let problem = gallery.problem {
            VStack(spacing: 12) {
                Text(problem.message).font(.system(size: 15)).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center)
                if problem.canOpenSettings {
                    Button("Open Settings") { model.push(.settings) }.buttonStyle(.borderedProminent).tint(Palette.accent)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .listRowBackground(Color.clear)
        } else if let failure = gallery.failure {
            VStack(spacing: 12) {
                EmptyState(systemImage: "exclamationmark.triangle", title: "Couldn't load the gallery", message: failure)
                Button("Try again") { Task { await loadGallery() } }.buttonStyle(.borderless)
            }
            .listRowBackground(Color.clear)
        } else if !gallery.loaded || (gallery.loading && gallery.templates.isEmpty) {
            ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
        } else if shownTemplates.isEmpty {
            EmptyState(mark: gallery.templates.isEmpty ? .wingsLevel : nil,
                       title: gallery.templates.isEmpty ? "The gallery is empty for now." : "No templates match.")
                .listRowBackground(Color.clear)
        } else {
            Section {
                ForEach(shownTemplates) { template in
                    TemplateRow(template: template, adding: gallery.installingId == template.id,
                                enabled: gallery.installingId == nil) { confirmInstall = template }
                }
                if gallery.next != nil {
                    HStack {
                        Spacer()
                        if gallery.loadingMore { ProgressView() } else {
                            Button("Show more") { Task { await loadMoreGallery() } }.buttonStyle(.borderless)
                        }
                        Spacer()
                    }
                    .onAppear { Task { await loadMoreGallery() } }
                }
            } footer: {
                Text("Adding a copy makes a private page on your server. Nothing from your pages goes to the gallery.")
            }
        }
    }

    // MARK: Loading

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            if model.crew.isEmpty { try? await model.refreshCrew() }
            let list = try await model.api.artifactList(includeArchived: showArchived)
            artifacts = list.artifacts
            stale = list.stale ?? false
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadGallery() async {
        gallery.loading = true
        gallery.problem = nil
        gallery.failure = nil
        do {
            let page = try await model.api.templates()
            gallery = GalleryState(loaded: true, templates: page.templates, next: page.next)
        } catch is CancellationError {
            gallery.loading = false
        } catch {
            gallery.loading = false
            gallery.loaded = true
            if let block = CloudBlock.from(error, doing: "browsed", todo: "browse the gallery") {
                gallery.problem = (error as? APIError)?.code == "cloud_not_linked"
                    ? CloudBlock(message: "Link your server to GACA Cloud to browse the gallery.", canOpenSettings: true)
                    : block
            } else {
                gallery.failure = error.localizedDescription
            }
        }
    }

    private func loadMoreGallery() async {
        guard let cursor = gallery.next, !gallery.loadingMore else { return }
        gallery.loadingMore = true
        defer { gallery.loadingMore = false }
        do {
            let page = try await model.api.templates(cursor: cursor)
            var seen = Set(gallery.templates.map(\.id))
            gallery.templates += page.templates.filter { seen.insert($0.id).inserted }
            gallery.next = page.next
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Makes a private copy on this server, then opens it.
    private func install(_ template: Template) {
        guard gallery.installingId == nil else { return }
        gallery.installingId = template.id
        error = nil
        Task {
            defer { gallery.installingId = nil }
            do {
                let page = try await model.api.installTemplate(template.id)
                filter = .mine
                notice = "Added \u{201C}\(template.title)\u{201D} to your pages. It is private until you share it."
                undo = nil
                await load()
                model.push(.artifact(page.id))
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    // MARK: Bring home, undo, leave (each confirmed before it gets here)

    private func bringHome(_ artifact: Artifact) {
        transfer("Bringing \u{201C}\(artifact.title)\u{201D} home…") {
            let result = try await model.api.bringHome(artifact)
            let lost = result.membersLostAccess ?? 0
            var text = "\u{201C}\(artifact.title)\u{201D} is back on your server."
            if lost > 0 { text += " \(plural(lost, "person", "people")) lost access." }
            if let warning = result.warning, !warning.isEmpty { text += " \(warning)" }
            var offer: UndoOffer?
            if let raw = result.undoUntil {
                let until = Self.parseDate(raw)
                if until.map({ $0 > .now }) ?? true { offer = UndoOffer(id: artifact.id, title: artifact.title, until: until) }
            }
            return (text, offer)
        }
    }

    private func undoBringHome(_ offer: UndoOffer) {
        transfer("Undoing…") {
            let undone = try await model.api.undoBringHome(offer.id)
            return (undone ? "\u{201C}\(offer.title)\u{201D} is back in the cloud."
                           : "Nothing to undo: \u{201C}\(offer.title)\u{201D} stays on your server.", nil)
        }
    }

    private func leave(_ artifact: Artifact) {
        transfer("Leaving \u{201C}\(artifact.title)\u{201D}…") {
            try await model.api.leavePage(artifact.id)
            return ("You left \u{201C}\(artifact.title)\u{201D}.", nil)
        }
    }

    private func transfer(_ start: String, _ work: @escaping () async throws -> (String, UndoOffer?)) {
        guard !working else { return }
        working = true
        notice = start
        undo = nil
        error = nil
        Task {
            do {
                let (done, offer) = try await work()
                notice = done
                undo = offer
                if let offer, let until = offer.until { expire(offer, at: until) }
            } catch {
                notice = nil
                self.error = (error as? APIError)?.code == "members_will_lose_access"
                    ? "Other people share this page now. Refresh the list and try again to see who would lose access."
                    : error.transferMessage
            }
            working = false
            await load() // a failed transfer may still have changed where the page lives
        }
    }

    /// Takes the Undo away once the cloud no longer keeps its copy.
    private func expire(_ offer: UndoOffer, at until: Date) {
        Task {
            try? await Task.sleep(for: .seconds(max(0, until.timeIntervalSinceNow)))
            if undo == offer { undo = nil }
        }
    }

    private static func parseDate(_ raw: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: raw) { return d }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: raw) { return d }
        // A naive timestamp from the server is UTC.
        f.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return f.date(from: raw.components(separatedBy: ".").first ?? raw)
    }

    // MARK: Order, archive, delete

    private func act(_ work: @escaping () async throws -> Void) {
        Task {
            do { try await work() } catch { self.error = error.localizedDescription }
            await load()
        }
    }

    /// Moves within what is shown (one filter's pages), then fits that order back into the slots those pages
    /// hold in the whole list, so pages under the other filter keep their places.
    private func move(from source: IndexSet, to destination: Int) {
        var visible = shown
        let slots = artifacts.indices.filter { i in visible.contains { $0.id == artifacts[i].id } }
        visible.move(fromOffsets: source, toOffset: destination)
        for (slot, page) in zip(slots, visible) { artifacts[slot] = page }
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

    private func present<T>(_ item: Binding<T?>) -> Binding<Bool> {
        Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
    }
}

struct ArtifactRow: View {
    let artifact: Artifact
    let style: CrewStyle

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: artifact.isSharedWithMe ? "person.2" : "square.grid.2x2")
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
                    if artifact.isArchived { Text(" · archived") }
                }
                .font(.system(size: 12))
                .foregroundStyle(Palette.textSecondary)
                .padding(.top, 2)
                badges.padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }

    /// Private / Shared / Published, then who it is shared with or by, your role on someone else's page, and a transfer state.
    private var badges: some View {
        VStack(alignment: .leading, spacing: 2) {
            badgeLine
            if let transfer = artifact.transferLine {
                Text(transfer).font(.system(size: 12)).foregroundStyle(Palette.textMeta)
            }
        }
    }

    private var badgeLine: some View {
        HStack(spacing: 6) {
            ForEach(artifact.badges, id: \.self) { badge in
                ArtifactTag(text: badge.rawValue,
                            background: badge == .published ? Palette.successBg : Palette.chip,
                            ink: badge == .published ? Palette.successInk : Palette.accent)
            }
            if artifact.isSharedWithMe {
                ArtifactTag(text: artifact.accessRole.label, background: Palette.chip, ink: Palette.accent)
            }
            if let who = artifact.sharedByLine ?? artifact.peopleLine {
                Label(who, systemImage: "person.2.fill")
                    .labelStyle(TightLabel())
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.system(size: 10)).foregroundStyle(Palette.textMeta)
            configuration.title
        }
    }
}

struct ArtifactTag: View {
    let text: String
    let background: Color
    let ink: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(ink)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 6).fill(background))
    }
}

/// One template in the gallery, with Add a copy.
struct TemplateRow: View {
    let template: Template
    let adding: Bool
    let enabled: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(template.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.textPrimary).lineLimit(1)
                if let d = template.description, !d.isEmpty {
                    Text(d).font(.system(size: 14)).foregroundStyle(Palette.textSecondary).lineLimit(2)
                }
                if !meta.isEmpty {
                    Text(meta).font(.system(size: 12)).foregroundStyle(Palette.textMeta).padding(.top, 2)
                }
                if !template.tagList.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(template.tagList.prefix(4), id: \.self) { ArtifactTag(text: $0, background: Palette.chip, ink: Palette.accent) }
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            if adding {
                ProgressView()
            } else {
                Button("Add a copy", action: onAdd)
                    .font(.system(size: 14, weight: .semibold))
                    .buttonStyle(.bordered)
                    .tint(Palette.accent)
                    .disabled(!enabled)
            }
        }
        .padding(.vertical, 4)
    }

    private var meta: String {
        var parts: [String] = []
        if let name = template.author?.name { parts.append("by \(name)") }
        if let c = template.category, !c.isEmpty { parts.append(c) }
        if let n = template.downloads, n > 0 { parts.append("\(n) added") }
        return parts.joined(separator: " · ")
    }
}
