import SwiftUI
import VisionKit

/// First run (or after Disconnect): pair this iPhone with a GACA server by scanning the QR code
/// `gaca-api pair` shows, opening its link, or typing the address and code.
struct PairingView: View {
    @Environment(AppModel.self) private var model
    var prefillServer: String?

    @State private var typing = false
    @State private var scanning = false
    @State private var address = ""
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?

    private var canScan: Bool { DataScannerViewController.isSupported }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: "sparkle")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Palette.onAccent)
                    .frame(width: 56, height: 56)
                    .background(RoundedRectangle(cornerRadius: 15).fill(Palette.accent))
                    .padding(.bottom, 20)
                    .accessibilityHidden(true)
                Text("Gaca").font(.largeTitleGaca).foregroundStyle(Palette.accent)
                Text("Connect to your server")
                    .font(.system(size: 17)).foregroundStyle(Palette.textSecondary).padding(.top, 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text("On the computer that runs your GACA server, run")
                    Text("gaca-api pair")
                        .font(.system(size: 17, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Palette.accent)
                    Text(typing || !canScan ? "then type the address and the code it prints." : "then scan the QR code it shows.")
                }
                .font(.system(size: 16))
                .foregroundStyle(Palette.textPrimary)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(Palette.surface))
                .padding(.top, 28)

                if typing || !canScan {
                    VStack(spacing: 0) {
                        field("Server") {
                            TextField("gaca.example.com", text: $address)
                                .keyboardType(.URL)
                                .textContentType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .accessibilityIdentifier("pair.address")
                        }
                        Divider().overlay(Palette.divider)
                        field("Code") {
                            TextField("ABCD-1234", text: $code)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .onSubmit { pair(address: address, code: code) }
                                .accessibilityIdentifier("pair.code")
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 14).fill(Palette.surface))
                    .padding(.top, 16)
                }

                if let error {
                    ErrorLine(text: error).padding(.top, 12)
                }

                Button {
                    if typing || !canScan { pair(address: address, code: code) } else { scanning = true }
                } label: {
                    ZStack {
                        Label(typing || !canScan ? "Pair" : "Scan QR code", systemImage: typing || !canScan ? "link" : "qrcode.viewfinder")
                            .opacity(busy ? 0 : 1)
                        if busy { ProgressView().tint(Palette.onAccent) }
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Palette.accent))
                }
                .disabled(busy)
                .padding(.top, 20)
                .accessibilityIdentifier("pair.submit")

                if canScan {
                    Button(typing ? "Scan a QR code instead" : "Enter a code instead") {
                        typing.toggle()
                        error = nil
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.top, 12)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 100)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.page)
        .sheet(isPresented: $scanning) {
            QRScanner { text in
                scanning = false
                guard let link = SetupLink(text) else {
                    error = "That QR code isn't from a GACA server. Run gaca-api pair on your server."
                    return
                }
                apply(link)
            }
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                Text("Point at the QR code from gaca-api pair")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .padding(.top, 24)
            }
        }
        .onAppear {
            if address.isEmpty, let prefillServer { address = prefillServer }
            if let link = model.pendingSetupLink { model.pendingSetupLink = nil; apply(link) }
        }
        .onChange(of: model.pendingSetupLink) { _, link in
            if let link { model.pendingSetupLink = nil; apply(link) }
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.system(size: 16)).frame(width: 64, alignment: .leading)
            content().font(.system(size: 16))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
    }

    /// A scanned or tapped `gaca://setup` link: fill in what it carries and pair right away.
    private func apply(_ link: SetupLink) {
        if let url = link.url { address = url }
        if let c = link.code { code = c }
        pair(address: address, code: code)
    }

    private func pair(address: String, code: String) {
        guard !busy else { return }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await model.pair(address: address, code: code)
            } catch {
                typing = true
                self.error = error.localizedDescription
            }
        }
    }
}

/// The system QR scanner (VisionKit) — reports the first QR code it reads.
struct QRScanner: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                                qualityLevel: .balanced, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        private var done = false

        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for case .barcode(let code) in items {
                if let text = code.payloadStringValue {
                    done = true
                    scanner.stopScanning()
                    onScan(text)
                    return
                }
            }
        }
    }
}
