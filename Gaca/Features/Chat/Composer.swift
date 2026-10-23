import PhotosUI
import SwiftUI

/// A photo picked for the next message, already shrunk for upload.
struct PendingPhoto: Identifiable, Equatable {
    let id = UUID()
    let jpeg: Data
    let thumbnail: UIImage
}

/// The floating message box shared by the Chat home and a thread: attach, type, send. When the
/// crew member has `skills`, a sparkle button next to + opens them (most used first), and typing
/// `/` lists them above the box; picking one puts `/skill-name ` at the start of the message.
struct Composer: View {
    @Binding var text: String
    @Binding var photos: [PendingPhoto]
    let placeholder: String
    let style: CrewStyle
    let sending: Bool
    var skills: [Skill] = []
    let onSend: () -> Void

    @State private var picked: [PhotosPickerItem] = []
    @State private var preparing = false
    @State private var showingLibrary = false
    @State private var showingCamera = false
    @State private var showingSkills = false
    @FocusState private var focused: Bool

    static let maxPhotos = 4

    private var canSend: Bool {
        !sending && !preparing && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !photos.isEmpty)
    }

    var body: some View {
        VStack(spacing: 8) {
            if !skills.isEmpty, let query = SkillCommand.slashQuery(text) {
                SlashSkillList(skills: skills, query: query,
                               onPick: { text = SkillCommand.insert($0, into: text) },
                               onSeeAll: { showingSkills = true })
            }
            box
        }
        .sheet(isPresented: $showingSkills) {
            SkillsSheet(skills: skills) { skill in
                showingSkills = false
                text = SkillCommand.insert(skill, into: text)
                focused = true
            }
        }
    }

    private var box: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !photos.isEmpty || preparing {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(photos) { photo in
                            Image(uiImage: photo.thumbnail)
                                .resizable().scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(alignment: .topTrailing) {
                                    Button { photos.removeAll { $0.id == photo.id } } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(Palette.onAccent)
                                            .frame(width: 22, height: 22)
                                            .background(Circle().fill(Palette.accent))
                                    }
                                    .offset(x: 6, y: -6)
                                    .accessibilityLabel("Remove photo")
                                }
                        }
                        if preparing { ProgressView().frame(width: 64, height: 64) }
                    }
                    .padding(.top, 6).padding(.horizontal, 4)
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    if CameraPicker.isAvailable {
                        Button { showingCamera = true } label: { Label("Take Photo", systemImage: "camera") }
                    }
                    Button { showingLibrary = true } label: { Label("Choose from Library", systemImage: "photo.on.rectangle") }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color(hex: "#E6EBF0")))
                }
                .disabled(photos.count >= Self.maxPhotos)
                .accessibilityLabel("Attach photo")
                .photosPicker(isPresented: $showingLibrary, selection: $picked,
                              maxSelectionCount: max(1, Self.maxPhotos - photos.count), matching: .images)
                .fullScreenCover(isPresented: $showingCamera) {
                    CameraPicker { image in
                        if photos.count < Self.maxPhotos, let photo = PhotoPrep.prepare(image) { photos.append(photo) }
                    }
                    .ignoresSafeArea()
                }

                if !skills.isEmpty {
                    Button { showingSkills = true } label: {
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(Palette.suggest))
                    }
                    .disabled(sending)
                    .accessibilityLabel("Skills")
                    .accessibilityIdentifier("composer.skills")
                }

                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(1...5)
                    .font(.system(size: 16))
                    .padding(.vertical, 9)
                    .focused($focused)
                    .accessibilityIdentifier("composer.field")

                Button(action: onSend) {
                    ZStack {
                        if sending { ProgressView().tint(.white) } else {
                            Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                        }
                    }
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(canSend || sending ? style.solid : Palette.border))
                }
                .disabled(!canSend)
                .accessibilityLabel("Send")
                .accessibilityIdentifier("composer.send")
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 26).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(Palette.border, lineWidth: 0.5))
        .shadow(color: Palette.accent.opacity(0.12), radius: 10, y: 4)
        // While typing, Done sits in the navigation bar (as in Notes), away from Send, to put
        // the keyboard away and get the tab bar back. Swiping the conversation down works too.
        .toolbar {
            if focused {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { focused = false }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("composer.done")
                }
            }
        }
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            picked = []
            preparing = true
            Task {
                for item in items where photos.count < Self.maxPhotos {
                    if let data = try? await item.loadTransferable(type: Data.self), let photo = PhotoPrep.prepare(data) {
                        photos.append(photo)
                    }
                }
                preparing = false
            }
        }
    }
}

/// Shrinks a picked photo to what the API accepts (≤ 2 MB): longest edge 1600 px, JPEG.
enum PhotoPrep {
    static let maxEdge: CGFloat = 1600
    static let maxBytes = 1_500_000

    static func prepare(_ data: Data) -> PendingPhoto? {
        guard let image = UIImage(data: data) else { return nil }
        return prepare(image)
    }

    static func prepare(_ image: UIImage) -> PendingPhoto? {
        let resized = resize(image, maxEdge: maxEdge)
        var quality: CGFloat = 0.85
        var jpeg = resized.jpegData(compressionQuality: quality)
        while let j = jpeg, j.count > maxBytes, quality > 0.3 {
            quality -= 0.15
            jpeg = resized.jpegData(compressionQuality: quality)
        }
        guard let jpeg else { return nil }
        return PendingPhoto(jpeg: jpeg, thumbnail: resize(image, maxEdge: 256))
    }

    static func resize(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        let size = image.size
        let scale = min(1, maxEdge / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

/// The system camera, for taking a photo to attach rather than picking an old one.
struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onCapture(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
