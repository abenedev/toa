import Foundation

/// A completed set of one exercise, as used for personal records.
struct PerformedSet {
    var weight: Double?
    var rpe: Double?
    var reps: Int?
    var duration: Int?
    var date: Date
}

enum RecordKind: String {
    case additionalWeight = "ADDITIONAL_WEIGHT"
    case totalWeight = "TOTAL_WEIGHT"
    case heaviestWeight = "HEAVIEST_WEIGHT"
    case longestDuration = "LONGEST_DURATION"
    case estimated1RM = "ESTIMATED_1RM"
    case maxVolume = "MAX_VOLUME"
}

struct PersonalRecord: Identifiable {
    let kind: RecordKind
    let label: String
    let value: Double
    let unit: String
    let date: Date?
    var detail: String? = nil

    var id: String { kind.rawValue }
}

struct WeightBest: Identifiable {
    let weight: Double
    let value: Int
    let date: Date?

    var id: Double { weight }
}

struct ExerciseRecords {
    var records: [PersonalRecord] = []
    var repsPerWeight: [WeightBest] = []
    var durationPerWeight: [WeightBest] = []

    var isEmpty: Bool { records.isEmpty && repsPerWeight.isEmpty && durationPerWeight.isEmpty }

    func value(of kind: RecordKind) -> Double? {
        records.first { $0.kind == kind }?.value
    }
}

/// Personal records & volume, computed on device from the set history
/// (ported from the former backend prs.py / volume.py).
enum Records {
    /// Epley estimate; reps in reserve (10 - RPE) are added to the reps.
    static func estimated1RM(load: Double, reps: Int, rpe: Double?) -> Double {
        let reserve = max(0, 10 - (rpe ?? 10))
        let effectiveReps = Double(reps) + reserve
        return effectiveReps > 1 ? load * (1 + effectiveReps / 30) : load
    }

    static func round1(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    /// `sets` must only contain sets from performed (non planned) workouts of this exercise.
    static func compute(
        type: ExerciseType,
        equipment: Equipment,
        sets unsorted: [PerformedSet],
        bodyweight: Double?
    ) -> ExerciseRecords {
        let sets = unsorted.sorted { $0.date < $1.date }
        let isBodyweight = equipment == .bodyweight
        let isAssisted = equipment == .assistedBodyweight
        var result = ExerciseRecords()

        if type == .duration {
            let durationSets = sets.filter { $0.duration != nil }
            let weighted = durationSets.filter { ($0.weight ?? 0) > 0 }
            let valid = durationSets.filter { ($0.duration ?? 0) > 0 }
            var best: (Double, Date)?
            var byWeight: [Double: (Int, Date)] = [:]
            for set in valid {
                let duration = set.duration ?? 0
                if best == nil || Double(duration) > best!.0 { best = (Double(duration), set.date) }
                let weight = set.weight ?? 0
                if let current = byWeight[weight], current.0 >= duration { continue }
                byWeight[weight] = (duration, set.date)
            }

            if isBodyweight {
                if let top = weighted.max(by: { ($0.weight ?? 0) < ($1.weight ?? 0) }) {
                    result.records.append(.init(
                        kind: .additionalWeight, label: "Additional weight",
                        value: top.weight ?? 0, unit: "kg", date: top.date))
                }
                if let bodyweight, let top = valid.max(by: { ($0.weight ?? 0) < ($1.weight ?? 0) }) {
                    result.records.append(.init(
                        kind: .totalWeight, label: "Total weight (bodyweight + added)",
                        value: bodyweight + (top.weight ?? 0), unit: "kg", date: top.date))
                }
            } else if isAssisted {
                if let top = weighted.min(by: { ($0.weight ?? 0) < ($1.weight ?? 0) }) {
                    result.records.append(.init(
                        kind: .heaviestWeight, label: "Least assistance",
                        value: top.weight ?? 0, unit: "kg", date: top.date))
                }
            } else if let top = weighted.max(by: { ($0.weight ?? 0) < ($1.weight ?? 0) }) {
                result.records.append(.init(
                    kind: .heaviestWeight, label: "Heaviest weight held",
                    value: top.weight ?? 0, unit: "kg", date: top.date))
            }
            if let best {
                result.records.append(.init(
                    kind: .longestDuration, label: "Longest duration",
                    value: best.0, unit: "s", date: best.1))
            }
            result.durationPerWeight = byWeight
                .map { WeightBest(weight: $0.key, value: $0.value.0, date: $0.value.1) }
                .sorted { $0.weight < $1.weight }
            return result
        }

        let repSets = sets.filter { $0.reps != nil }
        let weighted = repSets.filter { ($0.weight ?? 0) > 0 }

        if isBodyweight {
            if let top = weighted.max(by: { ($0.weight ?? 0) < ($1.weight ?? 0) }) {
                result.records.append(.init(
                    kind: .additionalWeight, label: "Additional weight",
                    value: top.weight ?? 0, unit: "kg", date: top.date))
            }
            if let bodyweight, let top = repSets.max(by: { ($0.weight ?? 0) < ($1.weight ?? 0) }) {
                result.records.append(.init(
                    kind: .totalWeight, label: "Total weight (bodyweight + added)",
                    value: bodyweight + (top.weight ?? 0), unit: "kg", date: top.date))
            }
        } else if isAssisted {
            if let top = weighted.min(by: { ($0.weight ?? 0) < ($1.weight ?? 0) }) {
                result.records.append(.init(
                    kind: .heaviestWeight, label: "Least assistance",
                    value: top.weight ?? 0, unit: "kg", date: top.date))
            }
        } else if let top = weighted.max(by: { ($0.weight ?? 0) < ($1.weight ?? 0) }) {
            result.records.append(.init(
                kind: .heaviestWeight, label: "Heaviest weight lifted",
                value: top.weight ?? 0, unit: "kg", date: top.date))
        }

        // Estimated 1RM is skipped for assisted exercises (inverted logic)
        if !isAssisted {
            var best: (Double, Date)?
            for set in repSets {
                guard let reps = set.reps, reps > 0, let load = load(of: set, isBodyweight: isBodyweight, bodyweight: bodyweight)
                else { continue }
                let estimate = estimated1RM(load: load, reps: reps, rpe: set.rpe)
                if best == nil || estimate > best!.0 { best = (estimate, set.date) }
            }
            if let best {
                result.records.append(.init(
                    kind: .estimated1RM, label: "Estimated 1RM",
                    value: round1(best.0), unit: "kg", date: best.1))
            }
        }

        var byWeight: [Double: (Int, Date)] = [:]
        var bestVolume: (volume: Double, reps: Int, load: Double, date: Date)?
        for set in repSets {
            guard let reps = set.reps, reps > 0 else { continue }
            let weight = set.weight ?? 0
            if byWeight[weight].map({ $0.0 < reps }) ?? true {
                byWeight[weight] = (reps, set.date)
            }

            let load: Double
            if isBodyweight, let bodyweight {
                load = bodyweight + weight
            } else if weight > 0 {
                load = weight
            } else {
                continue
            }
            let volume = load * Double(reps)
            if bestVolume == nil || volume > bestVolume!.volume {
                bestVolume = (volume, reps, load, set.date)
            }
        }
        result.repsPerWeight = byWeight
            .map { WeightBest(weight: $0.key, value: $0.value.0, date: $0.value.1) }
            .sorted { $0.weight < $1.weight }
        if let bestVolume {
            result.records.append(.init(
                kind: .maxVolume, label: "Most volume (single set)",
                value: bestVolume.volume, unit: "kg", date: bestVolume.date,
                detail: "\(bestVolume.reps) \(Fmt.repUnit(bestVolume.reps)) x \(Fmt.number(bestVolume.load)) kg"))
        }
        return result
    }

    /// Load used for the 1RM estimate: bodyweight exercises add the bodyweight when known.
    static func load(of set: PerformedSet, isBodyweight: Bool, bodyweight: Double?) -> Double? {
        let weight = set.weight ?? 0
        if weight > 0 {
            if isBodyweight, let bodyweight { return bodyweight + weight }
            return weight
        }
        if isBodyweight, let bodyweight { return bodyweight }
        return nil
    }

    /// Total volume of a workout: sum of load x reps; duration sets count for nothing.
    static func volume(
        of sets: [(weight: Double?, reps: Int?, equipment: Equipment?)],
        bodyweight: Double?
    ) -> Double {
        var total = 0.0
        for set in sets {
            guard let reps = set.reps, reps > 0 else { continue }
            if set.equipment == .bodyweight, let bodyweight {
                total += (bodyweight + (set.weight ?? 0)) * Double(reps)
            } else if let weight = set.weight, weight > 0 {
                total += weight * Double(reps)
            }
        }
        return total
    }

    /// Performed workouts started (directly or transitively) from `sourceId`.
    static func descendants<W>(
        of sourceId: UUID,
        in workouts: [W],
        id: (W) -> UUID,
        source: (W) -> UUID?
    ) -> [W] {
        var children: [UUID: [W]] = [:]
        for workout in workouts {
            if let parent = source(workout) { children[parent, default: []].append(workout) }
        }
        var visited: Set<UUID> = [sourceId]
        var queue = [sourceId]
        var result: [W] = []
        while !queue.isEmpty {
            let parent = queue.removeFirst()
            for child in children[parent] ?? [] where !visited.contains(id(child)) {
                visited.insert(id(child))
                result.append(child)
                queue.append(id(child))
            }
        }
        return result
    }
}
