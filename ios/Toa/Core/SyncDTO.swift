import Foundation

// Wire format of POST /sync (see backend/SYNC.md). Optionals are always encoded
// (as null) so the server never sees a missing key.

struct ExerciseDTO: Codable {
    var id: UUID
    var name: String
    var description: String?
    var type: String
    var equipment: String
    var updatedAt: Date

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(description, forKey: .description)
        try c.encode(type, forKey: .type)
        try c.encode(equipment, forKey: .equipment)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

struct WorkoutDTO: Codable {
    var id: UUID
    var name: String
    var planned: Bool
    var description: String?
    var note: String?
    var rpe: Double?
    var createdAt: Date
    var sourceWorkoutId: UUID?
    var updatedAt: Date

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(planned, forKey: .planned)
        try c.encode(description, forKey: .description)
        try c.encode(note, forKey: .note)
        try c.encode(rpe, forKey: .rpe)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(sourceWorkoutId, forKey: .sourceWorkoutId)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

struct WorkoutExerciseDTO: Codable {
    var id: UUID
    var workoutId: UUID
    var exerciseId: UUID
    var position: Int
    var note: String?
    var updatedAt: Date

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(workoutId, forKey: .workoutId)
        try c.encode(exerciseId, forKey: .exerciseId)
        try c.encode(position, forKey: .position)
        try c.encode(note, forKey: .note)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

struct SetDTO: Codable {
    var id: UUID
    var workoutId: UUID
    var exerciseId: UUID
    var position: Int
    var type: String
    var weight: Double?
    var rpe: Double?
    var rest: Int
    var reps: Int?
    var duration: Int?
    var updatedAt: Date

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(workoutId, forKey: .workoutId)
        try c.encode(exerciseId, forKey: .exerciseId)
        try c.encode(position, forKey: .position)
        try c.encode(type, forKey: .type)
        try c.encode(weight, forKey: .weight)
        try c.encode(rpe, forKey: .rpe)
        try c.encode(rest, forKey: .rest)
        try c.encode(reps, forKey: .reps)
        try c.encode(duration, forKey: .duration)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

struct DeletedRef: Codable, Hashable {
    enum Entity: String, Codable {
        case exercises, workouts, workoutExercises = "workout_exercises", sets
    }

    var entity: Entity
    var id: UUID
}

struct ProfilePush: Encodable {
    var bodyweight: Double?
    var updatedAt: Date

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(bodyweight, forKey: .bodyweight)
        try c.encode(updatedAt, forKey: .updatedAt)
    }

    enum CodingKeys: String, CodingKey { case bodyweight, updatedAt }
}

struct ProfileDTO: Decodable {
    var email: String?
    var bodyweight: Double?
    var updatedAt: Date?
    var isSubscribed: Bool
}

struct SyncRequest: Encodable {
    var cursor: Int64
    var profile: ProfilePush?
    var exercises: [ExerciseDTO]
    var workouts: [WorkoutDTO]
    var workoutExercises: [WorkoutExerciseDTO]
    var sets: [SetDTO]
    var deleted: [DeletedRef]

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(cursor, forKey: .cursor)
        try c.encode(profile, forKey: .profile)
        try c.encode(exercises, forKey: .exercises)
        try c.encode(workouts, forKey: .workouts)
        try c.encode(workoutExercises, forKey: .workoutExercises)
        try c.encode(sets, forKey: .sets)
        try c.encode(deleted, forKey: .deleted)
    }

    enum CodingKeys: String, CodingKey {
        case cursor, profile, exercises, workouts, workoutExercises, sets, deleted
    }

    var isEmpty: Bool {
        profile == nil && exercises.isEmpty && workouts.isEmpty && workoutExercises.isEmpty
            && sets.isEmpty && deleted.isEmpty
    }
}

struct SyncResponse: Decodable {
    var cursor: Int64
    var profile: ProfileDTO
    var exercises: [ExerciseDTO]
    var workouts: [WorkoutDTO]
    var workoutExercises: [WorkoutExerciseDTO]
    var sets: [SetDTO]
    var deleted: [DeletedRef]
}

enum WireJSON {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(format(date))
        }
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let text = try c.decode(String.self)
            guard let date = parse(text) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid date \(text)")
            }
            return date
        }
        return decoder
    }()

    /// `2026-10-26T12:00:00.123Z`
    static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// Accepts any number of fractional digits (or none) and any UTC offset.
    static func parse(_ text: String) -> Date? {
        var normalized = text
        if let dot = text.firstIndex(of: "."), let end = text[dot...].firstIndex(where: { !$0.isNumber && $0 != "." }) {
            let digits = text[text.index(after: dot)..<end]
            normalized = String(text[..<dot]) + "." + String(digits.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0) + String(text[end...])
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: normalized) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: normalized)
    }
}
