import StoreKit
import SwiftData
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(Session.self) private var session
    @Environment(Profile.self) private var profile
    @Environment(SyncEngine.self) private var sync
    @Environment(Subscriptions.self) private var subscriptions
    @Environment(\.modelContext) private var context
    @AppStorage("appearance") private var appearance = "system"

    @State private var bodyweight = ""
    @State private var authFlow: AuthFlowView.Mode?
    @State private var showChangePassword = false
    @State private var showChangeEmail = false
    @State private var showManageSubscription = false
    @State private var confirmSignOut = false
    @State private var confirmDeleteAccount = false
    @State private var deleteError: String?
    @State private var deleting = false

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                Section("Profile") {
                    HStack {
                        Text("Bodyweight (kg)")
                        TextField("—", text: $bodyweight)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .onSubmit(saveBodyweight)
                    }
                }
                Section {
                    Picker("Theme", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Appearance")
                }
                subscriptionSection
                if session.isSignedIn {
                    Section("Security") {
                        Button("Change email") { showChangeEmail = true }
                        Button("Change password") { showChangePassword = true }
                    }
                }
                Section {
                    Button(session.isSignedIn ? "Log out" : "Exit guest mode", role: .destructive) { confirmSignOut = true }
                }
                if session.isSignedIn {
                    Section {
                        Button("Delete account", role: .destructive) { confirmDeleteAccount = true }
                            .disabled(deleting)
                        if let deleteError { Text(deleteError).foregroundStyle(.red) }
                    } header: {
                        Text("Danger zone")
                    } footer: {
                        Text("Permanently deletes your account and all your workouts from every device.")
                    }
                }
                Section {
                } footer: {
                    Text("Toa \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Settings")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        saveBodyweight()
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .onAppear { bodyweight = profile.bodyweight.map { Fmt.number($0) } ?? "" }
            .onDisappear(perform: saveBodyweight)
            .onChange(of: profile.bodyweight) { bodyweight = profile.bodyweight.map { Fmt.number($0) } ?? "" }
            .sheet(item: $authFlow) { mode in
                AuthFlowView(mode: mode, prefilledEmail: session.email ?? "")
            }
            .sheet(isPresented: $showChangePassword) { ChangePasswordView() }
            .sheet(isPresented: $showChangeEmail) { ChangeEmailView() }
            .manageSubscriptionsSheet(isPresented: $showManageSubscription)
            .alert(session.isSignedIn ? "Log out?" : "Exit guest mode?", isPresented: $confirmSignOut) {
                Button(session.isSignedIn ? "Log out" : "Delete data & exit", role: .destructive) { session.signOut() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(signOutMessage)
            }
            .alert("Delete your account?", isPresented: $confirmDeleteAccount) {
                Button("Delete account", role: .destructive) { Task { await deleteAccount() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your account and all your data. This can't be undone.")
            }
        }
    }

    @ViewBuilder private var accountSection: some View {
        if session.isSignedIn {
            Section("Account") {
                LabeledContent("Email", value: session.email ?? "")
                if session.needsReauth {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your session has expired. Log in again to resume syncing; nothing on this iPhone is lost.")
                            .font(.subheadline)
                        Button("Log in again") { authFlow = .login }
                    }
                }
                HStack {
                    Text("Cloud sync")
                    Spacer()
                    if sync.isSyncing {
                        ProgressView()
                    } else {
                        Text(syncStatus).foregroundStyle(.secondary).font(.subheadline)
                    }
                }
                Button("Sync now") { Task { await sync.syncNow() } }
                    .disabled(sync.isSyncing || session.needsReauth)
            }
        } else {
            Section {
                Text("You're using Toa as a guest: your workouts are only stored on this iPhone. Create an account to back them up and use them on your other devices.")
                    .font(.subheadline)
                Button("Create account") { authFlow = .signup }
                Button("Log in") { authFlow = .login }
            } header: {
                Text("Guest mode")
            } footer: {
                if !AppConfig.accountsEnabled { Text("Accounts aren't available in this build yet.") }
            }
            .disabled(!AppConfig.accountsEnabled)
        }
    }

    @ViewBuilder private var subscriptionSection: some View {
        let subscribed = subscriptions.removesAds(profile)
        Section {
            Text(subscribed
                 ? "You're subscribed — ads are removed. Thank you!"
                 : "Remove ads — \(subscriptions.product?.displayPrice ?? "€2")/month")
            if !subscribed {
                if session.isSignedIn {
                    Button(subscriptions.isPurchasing ? "Purchasing…" : "Subscribe") {
                        Task { await subscriptions.purchase(userId: session.userId) }
                    }
                    .disabled(subscriptions.product == nil || subscriptions.isPurchasing)
                } else {
                    Text("Create an account to subscribe.").foregroundStyle(.secondary)
                }
            }
            if subscriptions.isEntitled {
                Button("Manage subscription") { showManageSubscription = true }
            }
            Button("Restore purchases") { Task { await subscriptions.restore() } }
            if let error = subscriptions.lastError {
                Text(error).foregroundStyle(.red)
            }
        } header: {
            Text("Subscription")
        } footer: {
            Text("Auto-renewable monthly subscription, cancel any time in your App Store settings.")
        }
    }

    private var syncStatus: String {
        if let error = sync.lastError { return error }
        if let date = sync.lastSyncedAt { return "Synced \(date.formatted(.relative(presentation: .named)))" }
        return "Not synced yet"
    }

    private var signOutMessage: String {
        guard session.isSignedIn else {
            return "All workouts stored on this iPhone will be deleted."
        }
        let pending = context.pendingChangeCount + (profile.bodyweightDirty ? 1 : 0)
        return pending > 0
            ? "\(pending) change(s) haven't been uploaded yet and will be lost. Your synced data stays in your account."
            : "Your data stays in your account and will be downloaded when you log in again."
    }

    private func saveBodyweight() {
        let value = Fmt.parseDouble(bodyweight)
        guard value != profile.bodyweight else { return }
        profile.setBodyweight(value.map { max(0, $0) })
    }

    private func deleteAccount() async {
        deleting = true
        deleteError = nil
        defer { deleting = false }
        do {
            guard let api = sync.api else { throw APIError.notConfigured }
            try await api.deleteMe()
            let token = try await session.accessToken()
            try? await session.cognito.deleteUser(accessToken: token)
            session.signOut()
        } catch {
            deleteError = error.localizedDescription
        }
    }
}

private struct ChangePasswordView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var new = ""
    @State private var confirmation = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                SecureField("Current password", text: $current).textContentType(.password)
                SecureField("New password", text: $new).textContentType(.newPassword)
                SecureField("Confirm new password", text: $confirmation).textContentType(.newPassword)
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Change password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        busy = true
                        Task {
                            defer { busy = false }
                            do {
                                let token = try await session.accessToken()
                                try await session.cognito.changePassword(accessToken: token, old: current, new: new)
                                dismiss()
                            } catch {
                                self.error = error.localizedDescription
                            }
                        }
                    }
                    .disabled(busy || current.isEmpty || new.isEmpty || new != confirmation)
                }
            }
        }
    }
}

private struct ChangeEmailView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("New email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(codeSent)
                    if codeSent {
                        TextField("Verification code", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                    }
                } footer: {
                    Text(codeSent ? "Enter the code we sent to \(email)." : "We'll send a verification code to the new address.")
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Change email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(codeSent ? "Verify" : "Send code") { Task { await submit() } }
                        .disabled(busy || email.trimmed.isEmpty || (codeSent && code.isEmpty))
                }
            }
        }
    }

    private func submit() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            let token = try await session.accessToken()
            if codeSent {
                try await session.cognito.verifyEmail(accessToken: token, code: code.trimmed)
                await session.refreshProfile()
                dismiss()
            } else {
                try await session.cognito.updateEmail(accessToken: token, email: email.trimmed.lowercased())
                codeSent = true
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
