import Foundation
import SwiftData

// Local database. Rows reference each other by id (no SwiftData relationships)
// so they can be synced in any order. `needsSync` marks rows to push.

@Model
final class Exercise {
    @Attribute(.unique) var id: UUID
    var name: String
    var info: String?
    var typeRaw: String
    var equipmentRaw: String
    var isDefault: Bool
    var updatedAt: Date
    var needsSync: Bool

    init(id: UUID = UUID(), name: String, info: String?, type: ExerciseType, equipment: Equipment, isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.info = info
        self.typeRaw = type.rawValue
        self.equipmentRaw = equipment.rawValue
        self.isDefault = isDefault
        self.updatedAt = .nowMillis
        self.needsSync = !isDefault
    }

    var type: ExerciseType {
        get { ExerciseType(rawValue: typeRaw) ?? .reps }
        set { typeRaw = newValue.rawValue }
    }

    var equipment: Equipment {
        get { Equipment(rawValue: equipmentRaw) ?? .barbell }
        set { equipmentRaw = newValue.rawValue }
    }
}

@Model
final class Workout {
    @Attribute(.unique) var id: UUID
    var name: String
    var planned: Bool
    var info: String?
    var note: String?
    var rpe: Double?
    var createdAt: Date
    var sourceWorkoutId: UUID?
    var updatedAt: Date
    var needsSync: Bool

    init(id: UUID = UUID(), name: String, planned: Bool, info: String?, note: String?, rpe: Double?, sourceWorkoutId: UUID?) {
        self.id = id
        self.name = name
        self.planned = planned
        self.info = info
        self.note = note
        self.rpe = rpe
        self.createdAt = .nowMillis
        self.sourceWorkoutId = sourceWorkoutId
        self.updatedAt = .nowMillis
        self.needsSync = true
    }
}

@Model
final class WorkoutExercise {
    @Attribute(.unique) var id: UUID
    var workoutId: UUID
    var exerciseId: UUID
    var position: Int
    var note: String?
    var updatedAt: Date
    var needsSync: Bool

    init(id: UUID = UUID(), workoutId: UUID, exerciseId: UUID, position: Int, note: String?) {
        self.id = id
        self.workoutId = workoutId
        self.exerciseId = exerciseId
        self.position = position
        self.note = note
        self.updatedAt = .nowMillis
        self.needsSync = true
    }
}

@Model
final class WorkoutSet {
    @Attribute(.unique) var id: UUID
    var workoutId: UUID
    var exerciseId: UUID
    var position: Int
    var typeRaw: String
    var weight: Double?
    var rpe: Double?
    var rest: Int
    var reps: Int?
    var duration: Int?
    var updatedAt: Date
    var needsSync: Bool

    init(id: UUID = UUID(), workoutId: UUID, exerciseId: UUID) {
        self.id = id
        self.workoutId = workoutId
        self.exerciseId = exerciseId
        self.position = 0
        self.typeRaw = SetType.workset.rawValue
        self.rest = 0
        self.updatedAt = .nowMillis
        self.needsSync = true
    }

    var type: SetType {
        get { SetType(rawValue: typeRaw) ?? .workset }
        set { typeRaw = newValue.rawValue }
    }
}

/// A local delete waiting to be pushed.
@Model
final class Tombstone {
    var entityRaw: String
    var targetId: UUID

    init(_ entity: DeletedRef.Entity, _ id: UUID) {
        self.entityRaw = entity.rawValue
        self.targetId = id
    }
}

extension Notification.Name {
    /// Posted after every local change so the sync engine can push it.
    static let toaLocalChange = Notification.Name("toaLocalChange")
}

extension ModelContext {
    /// Saves local changes and schedules a sync.
    func commit() {
        do {
            try save()
        } catch {
            print("Save failed: \(error)")
        }
        NotificationCenter.default.post(name: .toaLocalChange, object: nil)
    }

    func all<T: PersistentModel>(_ type: T.Type) -> [T] {
        (try? fetch(FetchDescriptor<T>())) ?? []
    }

    func exercise(_ id: UUID) -> Exercise? {
        var descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? fetch(descriptor).first
    }

    func workout(_ id: UUID) -> Workout? {
        var descriptor = FetchDescriptor<Workout>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? fetch(descriptor).first
    }

    func workoutExercises(of workoutId: UUID) -> [WorkoutExercise] {
        let descriptor = FetchDescriptor<WorkoutExercise>(
            predicate: #Predicate { $0.workoutId == workoutId },
            sortBy: [SortDescriptor(\.position)]
        )
        return (try? fetch(descriptor)) ?? []
    }

    func sets(of workoutId: UUID) -> [WorkoutSet] {
        let descriptor = FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.workoutId == workoutId },
            sortBy: [SortDescriptor(\.position)]
        )
        return (try? fetch(descriptor)) ?? []
    }

    /// Inserts the shared default exercises that are missing locally.
    func seedDefaultExercises() {
        let existing = Set(all(Exercise.self).filter(\.isDefault).map(\.id))
        for entry in DefaultExercises.all where !existing.contains(entry.id) {
            insert(Exercise(id: entry.id, name: entry.name, info: nil, type: entry.type, equipment: entry.equipment, isDefault: true))
        }
        try? save()
    }

    // MARK: Deletes (local cascade + tombstone, mirroring the server)

    func deleteWorkout(_ workout: Workout) {
        let id = workout.id
        cascadeDeleteWorkout(id)
        delete(workout)
        insert(Tombstone(.workouts, id))
    }

    func deleteExercise(_ exercise: Exercise) {
        let id = exercise.id
        cascadeDeleteExercise(id)
        delete(exercise)
        insert(Tombstone(.exercises, id))
    }

    func deleteSet(_ set: WorkoutSet) {
        insert(Tombstone(.sets, set.id))
        delete(set)
    }

    func deleteWorkoutExercise(_ item: WorkoutExercise) {
        insert(Tombstone(.workoutExercises, item.id))
        delete(item)
    }

    func cascadeDeleteWorkout(_ id: UUID) {
        let sets = (try? fetch(FetchDescriptor<WorkoutSet>(predicate: #Predicate { $0.workoutId == id }))) ?? []
        sets.forEach { delete($0) }
        let items = (try? fetch(FetchDescriptor<WorkoutExercise>(predicate: #Predicate { $0.workoutId == id }))) ?? []
        items.forEach { delete($0) }
    }

    func cascadeDeleteExercise(_ id: UUID) {
        let sets = (try? fetch(FetchDescriptor<WorkoutSet>(predicate: #Predicate { $0.exerciseId == id }))) ?? []
        sets.forEach { delete($0) }
        let items = (try? fetch(FetchDescriptor<WorkoutExercise>(predicate: #Predicate { $0.exerciseId == id }))) ?? []
        items.forEach { delete($0) }
    }

    /// Removes everything that belongs to the current account (default exercises stay).
    func wipeUserData() {
        all(WorkoutSet.self).forEach { delete($0) }
        all(WorkoutExercise.self).forEach { delete($0) }
        all(Workout.self).forEach { delete($0) }
        all(Tombstone.self).forEach { delete($0) }
        all(Exercise.self).filter { !$0.isDefault }.forEach { delete($0) }
        try? save()
    }

    var pendingChangeCount: Int {
        let workouts: Int = (try? fetchCount(FetchDescriptor<Workout>(predicate: #Predicate { $0.needsSync }))) ?? 0
        let sets: Int = (try? fetchCount(FetchDescriptor<WorkoutSet>(predicate: #Predicate { $0.needsSync }))) ?? 0
        let items: Int = (try? fetchCount(FetchDescriptor<WorkoutExercise>(predicate: #Predicate { $0.needsSync }))) ?? 0
        let exercises: Int = (try? fetchCount(FetchDescriptor<Exercise>(predicate: #Predicate { $0.needsSync }))) ?? 0
        let deletes: Int = (try? fetchCount(FetchDescriptor<Tombstone>())) ?? 0
        return workouts + sets + items + exercises + deletes
    }
}
