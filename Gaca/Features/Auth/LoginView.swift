import GoogleSignIn
import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var model
    @State private var registering = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    private var googleConfigured: Bool {
        !((Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String) ?? "").isEmpty
    }

    private var valid: Bool {
        email.contains("@") && !password.isEmpty && (!registering || !name.trimmingCharacters(in: .whitespaces).isEmpty)
    }

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
                Text("Gaca")
                    .font(.largeTitleGaca)
                    .foregroundStyle(Palette.accent)
                Text(registering ? "Create an account" : "Sign in to see your alerts")
                    .font(.system(size: 17))
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.top, 4)

                VStack(spacing: 0) {
                    if registering {
                        field("Name") { TextField("Your name", text: $name).textContentType(.name) }
                        Divider().overlay(Palette.divider)
                    }
                    field("Email") {
                        TextField("you@example.com", text: $email)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Divider().overlay(Palette.divider)
                    field("Password") {
                        SecureField("Required", text: $password)
                            .textContentType(registering ? .newPassword : .password)
                            .onSubmit(submit)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 14).fill(Palette.surface))
                .padding(.top, 30)

                if let error {
                    ErrorLine(text: error).padding(.top, 12)
                }

                Button(action: submit) {
                    ZStack {
                        Text(registering ? "Create account" : "Sign in").opacity(busy ? 0 : 1)
                        if busy { ProgressView().tint(Palette.onAccent) }
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Palette.accent))
                    .opacity(valid ? 1 : 0.4)
                }
                .disabled(!valid || busy)
                .padding(.top, 20)
                .accessibilityIdentifier("login.submit")

                if googleConfigured {
                    Button(action: google) {
                        HStack(spacing: 10) {
                            Image(systemName: "g.circle")
                            Text("Sign in with Google")
                        }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Palette.surface))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.border, lineWidth: 0.5))
                    }
                    .disabled(busy)
                    .padding(.top, 12)
                }

                Button {
                    registering.toggle()
                    error = nil
                } label: {
                    (Text(registering ? "Already have an account? " : "New here? ")
                        .foregroundStyle(Palette.textSecondary)
                     + Text(registering ? "Sign in" : "Create an account")
                        .foregroundStyle(Palette.accent).fontWeight(.semibold))
                        .font(.system(size: 15))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding(.top, 16)
            }
            .padding(.horizontal, 24)
            .padding(.top, 120)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.page)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.system(size: 16)).frame(width: 84, alignment: .leading)
            content().font(.system(size: 16))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
    }

    private func submit() {
        guard valid, !busy else { return }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                let token = registering
                    ? try await model.api.register(name: name.trimmingCharacters(in: .whitespaces), email: email, password: password)
                    : try await model.api.login(email: email.trimmingCharacters(in: .whitespaces), password: password)
                try await model.signedIn(with: token.accessToken)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func google() {
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first else { return }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: root)
                guard let idToken = result.user.idToken?.tokenString else {
                    error = "Google sign-in returned something the app couldn't read."
                    return
                }
                let token = try await model.api.googleLogin(idToken: idToken)
                try await model.signedIn(with: token.accessToken)
            } catch let gid as GIDSignInError where gid.code == .canceled {
                // The user backed out — nothing to say.
            } catch {
                self.error = "Google sign-in failed: \(error.localizedDescription)"
            }
        }
    }
}
