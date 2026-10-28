import Foundation
import Network
import Observation
import SwiftData

/// Settings of the user that aren't rows: bodyweight (synced) and the server-side
/// subscription flag (e.g. a subscription bought on the web).
@MainActor
@Observable
final class Profile {
    private let defaults = UserDefaults.standard

    private(set) var bodyweight: Double?
    private(set) var bodyweightUpdatedAt: Date?
    private(set) var bodyweightDirty = false
    private(set) var serverSubscribed = false

    init() {
        bodyweight = defaults.object(forKey: "profile.bodyweight") as? Double
        bodyweightUpdatedAt = defaults.object(forKey: "profile.bodyweightUpdatedAt") as? Date
        bodyweightDirty = defaults.bool(forKey: "profile.bodyweightDirty")
        serverSubscribed = defaults.bool(forKey: "profile.serverSubscribed")
    }

    func setBodyweight(_ value: Double?, updatedAt: Date = .nowMillis, dirty: Bool = true) {
        bodyweight = value
        bodyweightUpdatedAt = updatedAt
        defaults.set(value, forKey: "profile.bodyweight")
        defaults.set(updatedAt, forKey: "profile.bodyweightUpdatedAt")
        setBodyweightDirty(dirty)
        if dirty { NotificationCenter.default.post(name: .toaLocalChange, object: nil) }
    }

    func setBodyweightDirty(_ dirty: Bool) {
        bodyweightDirty = dirty
        defaults.set(dirty, forKey: "profile.bodyweightDirty")
    }

    func setServerSubscribed(_ subscribed: Bool) {
        serverSubscribed = subscribed
        defaults.set(subscribed, forKey: "profile.serverSubscribed")
    }

    func reset() {
        for key in ["profile.bodyweight", "profile.bodyweightUpdatedAt"] { defaults.removeObject(forKey: key) }
        bodyweight = nil
        bodyweightUpdatedAt = nil
        setBodyweightDirty(false)
        setServerSubscribed(false)
    }
}

/// Pushes local changes and pulls the other devices' changes (backend/SYNC.md).
@MainActor
@Observable
final class SyncEngine {
    private(set) var isSyncing = false
    private(set) var lastSyncedAt: Date?
    private(set) var lastError: String?
    private(set) var isOnline = true

    private let context: ModelContext
    private let session: Session
    private let profile: Profile
    private let defaults = UserDefaults.standard
    private var pending: Task<Void, Never>?
    private var rerun = false
    private let monitor = NWPathMonitor()
    private var observer: NSObjectProtocol?

    /// Called after each successful sync (e.g. to upload a pending purchase).
    var afterSync: () async -> Void = {}

    init(context: ModelContext, session: Session, profile: Profile) {
        self.context = context
        self.session = session
        self.profile = profile
        lastSyncedAt = defaults.object(forKey: "sync.lastSyncedAt") as? Date

        observer = NotificationCenter.default.addObserver(forName: .toaLocalChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedule() }
        }
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                let cameOnline = online && !self.isOnline
                self.isOnline = online
                if cameOnline { self.schedule(after: 0) }
            }
        }
        monitor.start(queue: DispatchQueue(label: "toa.network"))
    }

    private var cursor: Int64 {
        get { Int64(defaults.integer(forKey: "sync.cursor")) }
        set { defaults.set(Int(newValue), forKey: "sync.cursor") }
    }

    /// Debounced so a burst of edits becomes one request.
    func schedule(after delay: Double = 1.5) {
        guard session.isSignedIn else { return }
        pending?.cancel()
        pending = Task {
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            await syncNow()
        }
    }

    func reset() {
        cursor = 0
        lastSyncedAt = nil
        lastError = nil
        defaults.removeObject(forKey: "sync.lastSyncedAt")
    }

    func syncNow() async {
        guard session.isSignedIn, !session.needsReauth, let baseURL = AppConfig.apiBaseURL else { return }
        if isSyncing {
            rerun = true
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        repeat {
            rerun = false
            do {
                try await runOnce(baseURL: baseURL)
                lastError = nil
                lastSyncedAt = Date()
                defaults.set(lastSyncedAt, forKey: "sync.lastSyncedAt")
            } catch APIError.offline {
                lastError = "Waiting for internet connection"
                return
            } catch {
                lastError = error.localizedDescription
                return
            }
        } while rerun
        await afterSync()
    }

    var api: APIClient? {
        guard let baseURL = AppConfig.apiBaseURL else { return nil }
        let session = session
        return APIClient(baseURL: baseURL) { force in try await session.idToken(forceRefresh: force) }
    }

    private func runOnce(baseURL: URL) async throws {
        guard let api else { throw APIError.notConfigured }

        // Snapshot what is pushed; rows edited during the request stay dirty.
        let exercises = context.all(Exercise.self).filter { $0.needsSync && !$0.isDefault }
        let workouts = context.all(Workout.self).filter(\.needsSync)
        let items = context.all(WorkoutExercise.self).filter(\.needsSync)
        let sets = context.all(WorkoutSet.self).filter(\.needsSync)
        let tombstones = context.all(Tombstone.self)
        let pushedProfileAt = profile.bodyweightDirty ? profile.bodyweightUpdatedAt : nil

        let request = SyncRequest(
            cursor: cursor,
            profile: pushedProfileAt.map { ProfilePush(bodyweight: profile.bodyweight, updatedAt: $0) },
            exercises: exercises.map(\.dto),
            workouts: workouts.map(\.dto),
            workoutExercises: items.map(\.dto),
            sets: sets.map(\.dto),
            deleted: Array(Set(tombstones.compactMap { tombstone in
                DeletedRef.Entity(rawValue: tombstone.entityRaw).map { DeletedRef(entity: $0, id: tombstone.targetId) }
            }))
        )
        var pushedAt: [UUID: Date] = [:]
        for row in exercises { pushedAt[row.id] = row.updatedAt }
        for row in workouts { pushedAt[row.id] = row.updatedAt }
        for row in items { pushedAt[row.id] = row.updatedAt }
        for row in sets { pushedAt[row.id] = row.updatedAt }

        let response = try await api.sync(request)

        func markClean(_ id: UUID, _ updatedAt: Date, _ clean: () -> Void) {
            if pushedAt[id] == updatedAt { clean() }
        }
        for row in exercises { markClean(row.id, row.updatedAt) { row.needsSync = false } }
        for row in workouts { markClean(row.id, row.updatedAt) { row.needsSync = false } }
        for row in items { markClean(row.id, row.updatedAt) { row.needsSync = false } }
        for row in sets { markClean(row.id, row.updatedAt) { row.needsSync = false } }
        tombstones.forEach { context.delete($0) }

        apply(response)
        cursor = max(cursor, response.cursor)

        if let pushedProfileAt, profile.bodyweightUpdatedAt == pushedProfileAt {
            profile.setBodyweightDirty(false)
        }
        let server = response.profile
        if !profile.bodyweightDirty, let serverAt = server.updatedAt,
           serverAt > (profile.bodyweightUpdatedAt ?? .distantPast) || pushedProfileAt != nil {
            profile.setBodyweight(server.bodyweight, updatedAt: serverAt, dirty: false)
        }
        profile.setServerSubscribed(server.isSubscribed)
        try context.save()
    }

    /// Server rows win unless the local row is dirty and newer.
    private func apply(_ response: SyncResponse) {
        var localExercises = Dictionary(context.all(Exercise.self).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for dto in response.exercises {
            if let local = localExercises[dto.id] {
                guard !local.isDefault, !(local.needsSync && local.updatedAt > dto.updatedAt) else { continue }
                local.update(from: dto)
            } else {
                let row = Exercise(id: dto.id, name: dto.name, info: dto.description, type: .reps, equipment: .barbell)
                row.update(from: dto)
                context.insert(row)
                localExercises[dto.id] = row
            }
        }

        var localWorkouts = Dictionary(context.all(Workout.self).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for dto in response.workouts {
            if let local = localWorkouts[dto.id] {
                guard !(local.needsSync && local.updatedAt > dto.updatedAt) else { continue }
                local.update(from: dto)
            } else {
                let row = Workout(id: dto.id, name: dto.name, planned: dto.planned, info: nil, note: nil, rpe: nil, sourceWorkoutId: nil)
                row.update(from: dto)
                context.insert(row)
                localWorkouts[dto.id] = row
            }
        }

        let localItems = Dictionary(context.all(WorkoutExercise.self).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for dto in response.workoutExercises {
            if let local = localItems[dto.id] {
                guard !(local.needsSync && local.updatedAt > dto.updatedAt) else { continue }
                local.update(from: dto)
            } else {
                let row = WorkoutExercise(id: dto.id, workoutId: dto.workoutId, exerciseId: dto.exerciseId, position: dto.position, note: dto.note)
                row.update(from: dto)
                context.insert(row)
            }
        }

        let localSets = Dictionary(context.all(WorkoutSet.self).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for dto in response.sets {
            if let local = localSets[dto.id] {
                guard !(local.needsSync && local.updatedAt > dto.updatedAt) else { continue }
                local.update(from: dto)
            } else {
                let row = WorkoutSet(id: dto.id, workoutId: dto.workoutId, exerciseId: dto.exerciseId)
                row.update(from: dto)
                context.insert(row)
            }
        }

        for ref in response.deleted {
            switch ref.entity {
            case .workouts:
                context.cascadeDeleteWorkout(ref.id)
                if let row = localWorkouts[ref.id] { context.delete(row) }
            case .exercises:
                context.cascadeDeleteExercise(ref.id)
                if let row = localExercises[ref.id], !row.isDefault { context.delete(row) }
            case .workoutExercises:
                if let row = localItems[ref.id] { context.delete(row) }
            case .sets:
                if let row = localSets[ref.id] { context.delete(row) }
            }
        }
    }
}

// MARK: - Row <-> wire format

extension Exercise {
    var dto: ExerciseDTO {
        ExerciseDTO(id: id, name: name, description: info, type: typeRaw, equipment: equipmentRaw, updatedAt: updatedAt)
    }

    func update(from dto: ExerciseDTO) {
        name = dto.name
        info = dto.description
        typeRaw = dto.type
        equipmentRaw = dto.equipment
        updatedAt = dto.updatedAt
        needsSync = false
    }
}

extension Workout {
    var dto: WorkoutDTO {
        WorkoutDTO(id: id, name: name, planned: planned, description: info, note: note, rpe: rpe,
                   createdAt: createdAt, sourceWorkoutId: sourceWorkoutId, updatedAt: updatedAt)
    }

    func update(from dto: WorkoutDTO) {
        name = dto.name
        planned = dto.planned
        info = dto.description
        note = dto.note
        rpe = dto.rpe
        createdAt = dto.createdAt
        sourceWorkoutId = dto.sourceWorkoutId
        updatedAt = dto.updatedAt
        needsSync = false
    }
}

extension WorkoutExercise {
    var dto: WorkoutExerciseDTO {
        WorkoutExerciseDTO(id: id, workoutId: workoutId, exerciseId: exerciseId, position: position, note: note, updatedAt: updatedAt)
    }

    func update(from dto: WorkoutExerciseDTO) {
        workoutId = dto.workoutId
        exerciseId = dto.exerciseId
        position = dto.position
        note = dto.note
        updatedAt = dto.updatedAt
        needsSync = false
    }
}

extension WorkoutSet {
    var dto: SetDTO {
        SetDTO(id: id, workoutId: workoutId, exerciseId: exerciseId, position: position, type: typeRaw,
               weight: weight, rpe: rpe, rest: rest, reps: reps, duration: duration, updatedAt: updatedAt)
    }

    func update(from dto: SetDTO) {
        workoutId = dto.workoutId
        exerciseId = dto.exerciseId
        position = dto.position
        typeRaw = dto.type
        weight = dto.weight
        rpe = dto.rpe
        rest = dto.rest
        reps = dto.reps
        duration = dto.duration
        updatedAt = dto.updatedAt
        needsSync = false
    }
}
