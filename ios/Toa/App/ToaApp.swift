import SwiftData
import SwiftUI

@main
@MainActor
struct ToaApp: App {
    private let container: ModelContainer
    @State private var session: Session
    @State private var profile: Profile
    @State private var sync: SyncEngine
    @State private var subscriptions = Subscriptions()
    @State private var router = Router()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: Exercise.self, Workout.self, WorkoutExercise.self, WorkoutSet.self, Tombstone.self)
        } catch {
            fatalError("Could not open the local database: \(error)")
        }
        container.mainContext.seedDefaultExercises()
        self.container = container

        let session = Session()
        let profile = Profile()
        let sync = SyncEngine(context: container.mainContext, session: session, profile: profile)
        _session = State(initialValue: session)
        _profile = State(initialValue: profile)
        _sync = State(initialValue: sync)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(profile)
                .environment(sync)
                .environment(subscriptions)
                .environment(router)
                .onAppear(perform: wire)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                sync.schedule(after: 0)
                Task { await subscriptions.refreshEntitlement() }
            }
        }
    }

    private func wire() {
        let context = container.mainContext
        session.onWipe = { [sync, profile, router] in
            context.wipeUserData()
            sync.reset()
            profile.reset()
            router.discardDraft()
        }
        session.onSignedIn = { [sync] in sync.schedule(after: 0) }
        sync.afterSync = { [subscriptions, profile, sync] in
            if let server = await subscriptions.uploadPending(using: sync.api) {
                profile.setServerSubscribed(server.isSubscribed)
            }
        }
        subscriptions.start()
        router.restoreDraft()
    }
}

/// App-wide navigation state: the workout editor is presented from the root.
@MainActor
@Observable
final class Router {
    enum Editor: Identifiable {
        case new
        case edit(UUID)
        case start(UUID)
        case resume(WorkoutDraft)

        var id: String {
            switch self {
            case .new: "new"
            case .edit(let id): "edit-\(id)"
            case .start(let id): "start-\(id)"
            case .resume(let draft): "resume-\(draft.workoutId)"
            }
        }
    }

    var editor: Editor?
    /// Editor waiting behind the ad interstitial.
    var gatedEditor: Editor?
    var showAd = false

    /// Opens the editor, after an ad unless the user is subscribed.
    func open(_ editor: Editor, hasAds: Bool) {
        if hasAds {
            gatedEditor = editor
            showAd = true
        } else {
            self.editor = editor
        }
    }

    func adFinished() {
        showAd = false
        editor = gatedEditor
        gatedEditor = nil
    }

    func restoreDraft() {
        if editor == nil, let draft = DraftStore.load() {
            editor = .resume(draft)
        }
    }

    func discardDraft() {
        editor = nil
        DraftStore.clear()
    }
}

struct RootView: View {
    @Environment(Session.self) private var session
    @Environment(Router.self) private var router
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        @Bindable var router = router
        Group {
            if session.state == .signedOut {
                WelcomeView()
            } else {
                MainTabView()
            }
        }
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        .fullScreenCover(isPresented: $router.showAd, onDismiss: {
            if router.gatedEditor != nil { router.adFinished() }
        }) {
            AdInterstitial { router.showAd = false }
        }
        .fullScreenCover(item: $router.editor) { editor in
            WorkoutEditorView(editor: editor)
                .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            WorkoutsView()
                .tabItem { Label("Workouts", systemImage: "dumbbell") }
            ExercisesView()
                .tabItem { Label("Exercises", systemImage: "books.vertical") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

/// Placeholder interstitial shown to non-subscribers before a workout.
/// Swap `adSlot` for a real ad network later.
struct AdInterstitial: View {
    let onContinue: () -> Void
    @State private var remaining = 5

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Ad").font(.title.bold())
            Text("Subscribe for €2/month in Settings to remove ads.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6]))
                .foregroundStyle(.secondary)
                .frame(height: 180)
                .overlay { Text("Your ad could be here").foregroundStyle(.secondary) }
            Spacer()
            Button(remaining == 0 ? "Continue" : "Continue in \(remaining)s", action: onContinue)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(remaining > 0)
        }
        .padding(24)
        .interactiveDismissDisabled()
        .task {
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                remaining -= 1
            }
        }
    }
}
