import Foundation
import SwiftData

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { trimmed.isEmpty ? nil : trimmed }
}

extension WorkoutSet {
    func apply(_ resolved: ResolvedSet) {
        exerciseId = resolved.exerciseId
        position = resolved.position
        type = resolved.type
        weight = resolved.weight
        rpe = resolved.rpe
        rest = resolved.rest
        reps = resolved.reps
        duration = resolved.duration
        updatedAt = .nowMillis
        needsSync = true
    }
}

/// Converts between stored workouts and the editor draft.
extension ModelContext {
    func makeDraft(_ editor: Router.Editor) -> WorkoutDraft? {
        switch editor {
        case .new:
            return WorkoutDraft(mode: .new, workoutId: UUID())
        case .resume(let draft):
            return draft
        case .edit(let id):
            return workout(id).map { draft(from: $0, mode: .edit) }
        case .start(let id):
            return workout(id).map { draft(from: $0, mode: .active) }
        }
    }

    private func draft(from workout: Workout, mode: WorkoutDraft.Mode) -> WorkoutDraft {
        let keepIds = mode == .edit
        let items = workoutExercises(of: workout.id)
        let sets = self.sets(of: workout.id)
        let setsByExercise = Dictionary(grouping: sets, by: \.exerciseId)

        func draftSets(_ list: [WorkoutSet]) -> [DraftSet] {
            list.map { set in
                DraftSet(
                    id: keepIds ? set.id : UUID(),
                    type: set.type,
                    planned: PlannedValues(weight: set.weight, reps: set.reps, duration: set.duration, rpe: set.rpe),
                    weight: set.weight.map { Fmt.number($0) } ?? "",
                    reps: set.reps.map { String($0) } ?? "",
                    duration: set.duration.map { String($0) } ?? "",
                    rpe: set.rpe.map { Fmt.number($0) } ?? ""
                )
            }
        }

        func group(id: UUID, exerciseId: UUID, note: String?, sets list: [WorkoutSet]) -> DraftGroup {
            DraftGroup(
                id: id,
                exerciseId: exerciseId,
                isDuration: exercise(exerciseId)?.type == .duration,
                note: note ?? "",
                rest: list.first?.rest ?? 0,
                sets: draftSets(list)
            )
        }

        var groups: [DraftGroup] = []
        var used: Set<UUID> = []
        for item in items {
            let list = used.contains(item.exerciseId) ? [] : (setsByExercise[item.exerciseId] ?? [])
            used.insert(item.exerciseId)
            groups.append(group(id: keepIds ? item.id : UUID(), exerciseId: item.exerciseId, note: item.note, sets: list))
        }
        // Sets whose exercise has no workout-exercise row still get a group.
        for set in sets where !used.contains(set.exerciseId) {
            used.insert(set.exerciseId)
            groups.append(group(id: UUID(), exerciseId: set.exerciseId, note: nil, sets: setsByExercise[set.exerciseId] ?? []))
        }

        // Performing a workout from history starts with an empty note & RPE.
        let keepSummary = mode == .edit || workout.planned
        return WorkoutDraft(
            mode: mode,
            workoutId: workout.id,
            name: workout.name,
            info: workout.info ?? "",
            note: keepSummary ? (workout.note ?? "") : "",
            rpe: keepSummary ? workout.rpe.map { Int($0.rounded()) } : nil,
            groups: groups,
            startedAt: Date()
        )
    }

    /// Creates (new) or updates (edit) a workout from the draft, keeping row ids stable.
    func saveDraft(_ draft: WorkoutDraft) {
        let workoutId = draft.workoutId
        let workout: Workout
        if draft.mode == .edit, let existing = self.workout(workoutId) {
            workout = existing
        } else {
            workout = Workout(id: workoutId, name: draft.name.trimmed, planned: true, info: nil, note: nil, rpe: nil, sourceWorkoutId: nil)
            insert(workout)
        }
        workout.name = draft.name.trimmed
        workout.info = draft.info.nilIfEmpty
        workout.note = draft.note.nilIfEmpty
        workout.rpe = draft.rpe.map { Double($0) }
        workout.updatedAt = .nowMillis
        workout.needsSync = true

        let existingItems = Dictionary(workoutExercises(of: workoutId).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let existingSets = Dictionary(sets(of: workoutId).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        for (index, group) in draft.groups.enumerated() {
            let item: WorkoutExercise
            if let existing = existingItems[group.id] {
                item = existing
            } else {
                item = WorkoutExercise(id: group.id, workoutId: workoutId, exerciseId: group.exerciseId, position: index, note: nil)
                insert(item)
            }
            item.exerciseId = group.exerciseId
            item.position = index
            item.note = group.note.nilIfEmpty
            item.updatedAt = .nowMillis
            item.needsSync = true
        }

        let resolved = draft.resolvedSets(onlyCompleted: false)
        for value in resolved {
            let set: WorkoutSet
            if let existing = existingSets[value.id] {
                set = existing
            } else {
                set = WorkoutSet(id: value.id, workoutId: workoutId, exerciseId: value.exerciseId)
                insert(set)
            }
            set.apply(value)
        }

        let keptItems = Set(draft.groups.map(\.id))
        let keptSets = Set(resolved.map(\.id))
        for (id, item) in existingItems where !keptItems.contains(id) { deleteWorkoutExercise(item) }
        for (id, set) in existingSets where !keptSets.contains(id) { deleteSet(set) }
        commit()
    }

    /// Records a performed workout with the completed sets only.
    func finishDraft(_ draft: WorkoutDraft) {
        let workout = Workout(
            name: draft.name.nilIfEmpty ?? "Finished workout",
            planned: false,
            info: draft.info.nilIfEmpty,
            note: draft.note.nilIfEmpty,
            rpe: draft.rpe.map { Double($0) },
            sourceWorkoutId: draft.workoutId
        )
        insert(workout)
        for (index, group) in draft.groups.enumerated() where group.sets.contains(where: \.completed) {
            insert(WorkoutExercise(workoutId: workout.id, exerciseId: group.exerciseId, position: index, note: group.note.nilIfEmpty))
        }
        for value in draft.resolvedSets(onlyCompleted: true) {
            let set = WorkoutSet(workoutId: workout.id, exerciseId: value.exerciseId)
            set.apply(value)
            insert(set)
        }
        commit()
    }

    /// Completed sets of an exercise, for personal records.
    func history(of exerciseId: UUID) -> [PerformedSet] {
        let dates = Dictionary(all(Workout.self).filter { !$0.planned }.map { ($0.id, $0.createdAt) }, uniquingKeysWith: { a, _ in a })
        let sets = (try? fetch(FetchDescriptor<WorkoutSet>(predicate: #Predicate { $0.exerciseId == exerciseId }))) ?? []
        return sets.compactMap { set in
            dates[set.workoutId].map { PerformedSet(weight: set.weight, rpe: set.rpe, reps: set.reps, duration: set.duration, date: $0) }
        }
    }
}
