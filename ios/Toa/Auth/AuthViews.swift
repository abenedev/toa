import SwiftUI

struct WelcomeView: View {
    @Environment(Session.self) private var session
    @State private var flow: AuthFlowView.Mode?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Toa").font(.largeTitle.bold())
            Text("Track your workouts, log exercises, and reach your fitness goals.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            VStack(spacing: 12) {
                Button { flow = .login } label: { Text("Log in").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!AppConfig.accountsEnabled)
                Button { flow = .signup } label: { Text("Sign up").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
                    .disabled(!AppConfig.accountsEnabled)
                if !AppConfig.accountsEnabled {
                    Text("Accounts aren't available in this build yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button("Continue as guest") { session.continueAsGuest() }
                    .padding(.top, 8)
                Text("As a guest, your workouts stay on this iPhone. Create an account any time to back them up and use them on other devices.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .controlSize(.large)
        }
        .padding(24)
        .sheet(item: $flow) { mode in
            AuthFlowView(mode: mode)
        }
    }
}

/// Log in / sign up (with email confirmation) / forgot password.
struct AuthFlowView: View {
    enum Mode: String, Identifiable {
        case login, signup
        var id: String { rawValue }
    }

    let mode: Mode
    var prefilledEmail = ""

    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    private enum Step { case form, confirm, forgot, reset }

    @State private var step = Step.form
    @State private var email = ""
    @State private var password = ""
    @State private var passwordConfirmation = ""
    @State private var code = ""
    @State private var newPassword = ""
    @State private var error: String?
    @State private var info: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                switch step {
                case .form: formSection
                case .confirm: confirmSection
                case .forgot: forgotSection
                case .reset: resetSection
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                if let info {
                    Section { Text(info).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .disabled(busy)
            .onAppear { if email.isEmpty { email = prefilledEmail } }
        }
    }

    private var title: String {
        switch step {
        case .form: mode == .login ? "Log in" : "Create account"
        case .confirm: "Confirm your email"
        case .forgot, .reset: "Reset password"
        }
    }

    @ViewBuilder private var formSection: some View {
        Section {
            TextField("Email", text: $email)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Password", text: $password)
                .textContentType(mode == .login ? .password : .newPassword)
            if mode == .signup {
                SecureField("Confirm password", text: $passwordConfirmation)
                    .textContentType(.newPassword)
            }
        } footer: {
            if mode == .signup {
                Text("Your workouts on this device are uploaded to your new account.")
            }
        }
        Section {
            Button(mode == .login ? "Log in" : "Sign up") { run(mode == .login ? logIn : signUp) }
                .disabled(email.isEmpty || password.isEmpty || (mode == .signup && password != passwordConfirmation))
            if mode == .login {
                Button("Forgot password?") { step = .forgot; error = nil }
            }
        }
    }

    @ViewBuilder private var confirmSection: some View {
        Section {
            TextField("Verification code", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
        } footer: {
            Text("We sent a code to \(email).")
        }
        Section {
            Button("Confirm") { run(confirm) }.disabled(code.isEmpty)
            Button("Resend code") {
                run {
                    try await session.cognito.resendConfirmationCode(email: normalizedEmail)
                    info = "A new code was sent."
                }
            }
        }
    }

    @ViewBuilder private var forgotSection: some View {
        Section {
            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } footer: {
            Text("We'll email you a code to choose a new password.")
        }
        Section {
            Button("Send code") {
                run {
                    try await session.cognito.forgotPassword(email: normalizedEmail)
                    step = .reset
                }
            }
            .disabled(email.isEmpty)
        }
    }

    @ViewBuilder private var resetSection: some View {
        Section {
            TextField("Verification code", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
            SecureField("New password", text: $newPassword)
                .textContentType(.newPassword)
        }
        Section {
            Button("Save new password") {
                run {
                    try await session.cognito.confirmForgotPassword(email: normalizedEmail, code: code, newPassword: newPassword)
                    password = newPassword
                    try await logIn()
                }
            }
            .disabled(code.isEmpty || newPassword.isEmpty)
        }
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private func logIn() async throws {
        do {
            try await session.signIn(email: normalizedEmail, password: password)
            dismiss()
        } catch let error as AuthError where error.code == "UserNotConfirmedException" {
            try? await session.cognito.resendConfirmationCode(email: normalizedEmail)
            step = .confirm
        }
    }

    private func signUp() async throws {
        let needsConfirmation = try await session.cognito.signUp(email: normalizedEmail, password: password)
        if needsConfirmation {
            step = .confirm
        } else {
            try await logIn()
        }
    }

    private func confirm() async throws {
        try await session.cognito.confirmSignUp(email: normalizedEmail, code: code.trimmingCharacters(in: .whitespaces))
        try await logIn()
    }

    private func run(_ action: @escaping () async throws -> Void) {
        error = nil
        info = nil
        busy = true
        Task {
            defer { busy = false }
            do {
                try await action()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
