import Foundation

/// Values coming from the workout the editor was opened from, shown as placeholders.
struct PlannedValues: Codable, Equatable {
    var weight: Double?
    var reps: Int?
    var duration: Int?
    var rpe: Double?
}

struct DraftSet: Codable, Equatable, Identifiable {
    var id = UUID()
    var type: SetType = .workset
    var planned = PlannedValues()
    var weight = ""
    var reps = ""
    var duration = ""
    var rpe = ""
    var completed = false
    var isRecord = false
}

struct DraftGroup: Codable, Equatable, Identifiable {
    var id = UUID()
    var exerciseId: UUID
    var isDuration: Bool
    var note = ""
    var rest = 0
    var sets: [DraftSet] = []
}

/// In-progress state of the workout editor. It's autosaved so an active workout
/// survives the app being killed.
struct WorkoutDraft: Codable, Equatable {
    enum Mode: String, Codable {
        /// Create a planned workout.
        case new
        /// Edit an existing workout in place.
        case edit
        /// Perform a workout; finishing it creates a new performed workout.
        case active
    }

    var mode: Mode
    /// new: id of the workout to create; edit: edited workout; active: source workout.
    var workoutId: UUID
    var name = ""
    var info = ""
    var note = ""
    var rpe: Int?
    var groups: [DraftGroup] = []
    var startedAt = Date()

    var isActive: Bool { mode == .active }

    var completedSetCount: Int {
        groups.reduce(0) { $0 + $1.sets.filter(\.completed).count }
    }

    mutating func addExercise(id: UUID, isDuration: Bool) {
        groups.append(DraftGroup(exerciseId: id, isDuration: isDuration, sets: [DraftSet()]))
    }

    mutating func addSet(toGroup groupId: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return }
        groups[index].sets.append(DraftSet())
    }

    /// Removes a set; an exercise left without sets is removed too.
    mutating func deleteSet(_ setId: UUID) {
        for index in groups.indices {
            groups[index].sets.removeAll { $0.id == setId }
        }
        groups.removeAll { $0.sets.isEmpty }
    }

    mutating func setType(_ type: SetType, forSet setId: UUID) {
        updateSet(setId) { set in
            set.type = type
            if type == .failure { set.rpe = "10" }
        }
    }

    /// Marks a set done with the typed values, falling back to the planned ones.
    /// Returns false when the set was un-completed instead.
    @discardableResult
    mutating func toggleCompleted(_ setId: UUID) -> Bool {
        var nowCompleted = false
        updateSet(setId) { set in
            if set.completed {
                set.completed = false
                set.isRecord = false
                return
            }
            if set.weight.trimmingCharacters(in: .whitespaces).isEmpty {
                set.weight = set.planned.weight.map { Fmt.number($0) } ?? "0"
            }
            if set.rpe.trimmingCharacters(in: .whitespaces).isEmpty, let rpe = set.planned.rpe, rpe > 0 {
                set.rpe = Fmt.number(rpe)
            }
            if set.reps.trimmingCharacters(in: .whitespaces).isEmpty {
                set.reps = String(set.planned.reps ?? 0)
            }
            if set.duration.trimmingCharacters(in: .whitespaces).isEmpty {
                set.duration = String(set.planned.duration ?? 0)
            }
            set.completed = true
            nowCompleted = true
        }
        return nowCompleted
    }

    mutating func updateSet(_ setId: UUID, _ change: (inout DraftSet) -> Void) {
        for g in groups.indices {
            if let s = groups[g].sets.firstIndex(where: { $0.id == setId }) {
                change(&groups[g].sets[s])
                return
            }
        }
    }

    /// "1", "2"… for worksets (counted per exercise), "W", "D", "S", "F" otherwise.
    static func typeDisplay(of set: DraftSet, in group: DraftGroup) -> String {
        guard set.type == .workset else { return set.type.shortLabel }
        var count = 0
        for other in group.sets {
            if other.type == .workset { count += 1 }
            if other.id == set.id { break }
        }
        return String(count)
    }
}

/// A set ready to be stored, resolved from the draft's text inputs.
struct ResolvedSet {
    var id: UUID
    var exerciseId: UUID
    var position: Int
    var type: SetType
    var weight: Double?
    var rpe: Double?
    var rest: Int
    var reps: Int?
    var duration: Int?
}

extension WorkoutDraft {
    /// Sets to store: every set when planning/editing, only completed ones when finishing.
    func resolvedSets(onlyCompleted: Bool) -> [ResolvedSet] {
        var result: [ResolvedSet] = []
        for (groupIndex, group) in groups.enumerated() {
            for (setIndex, set) in group.sets.enumerated() where !onlyCompleted || set.completed {
                let rpe = Fmt.parseDouble(set.rpe) ?? (onlyCompleted ? set.planned.rpe : nil)
                result.append(ResolvedSet(
                    id: set.id,
                    exerciseId: group.exerciseId,
                    position: groupIndex * 1000 + setIndex,
                    type: set.type,
                    weight: Fmt.parseDouble(set.weight) ?? (onlyCompleted ? set.planned.weight : nil),
                    rpe: (rpe ?? 0) > 0 ? rpe : nil,
                    rest: max(0, group.rest),
                    reps: group.isDuration ? nil : (Fmt.parseInt(set.reps) ?? (onlyCompleted ? set.planned.reps : nil) ?? 0),
                    duration: group.isDuration ? (Fmt.parseInt(set.duration) ?? (onlyCompleted ? set.planned.duration : nil) ?? 0) : nil
                ))
            }
        }
        return result
    }
}
