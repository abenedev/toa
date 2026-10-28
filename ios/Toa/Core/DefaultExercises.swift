import Foundation

/// Exercises shared by every user. The ids are fixed and must stay identical to
/// `DEFAULT_EXERCISES` in backend/src/workout/seed.py.
enum DefaultExercises {
    struct Entry {
        let id: UUID
        let name: String
        let type: ExerciseType
        let equipment: Equipment
    }

    private static let table: [(String, String, ExerciseType, Equipment)] = [
        ("d9e34672-cb30-563a-99ef-bfd3033bfe13", "Barbell Squat", .reps, .barbell),
        ("763fe2b4-d7ff-5606-9492-fd94732e22a9", "Front Squat", .reps, .barbell),
        ("76cac9bd-d213-560d-b9b7-3064896976fd", "Barbell Bench Press", .reps, .barbell),
        ("8ce7f702-ffc0-5380-80f6-981ec81259f7", "Incline Barbell Bench Press", .reps, .barbell),
        ("42c7760c-20dc-53e8-85e9-d252db4521b4", "Deadlift", .reps, .barbell),
        ("f246d132-cb59-5599-9f39-088c6767cdfd", "Romanian Deadlift", .reps, .barbell),
        ("ac5d0039-b229-5796-91c9-9a2ae0953269", "Overhead Press", .reps, .barbell),
        ("1cd97993-dadb-5b10-9e93-d429646b96a8", "Barbell Row", .reps, .barbell),
        ("954bbbb8-8e27-534a-87aa-4a8f1198997e", "Hip Thrust", .reps, .barbell),
        ("b451789d-b19b-5394-94cb-9d2ba6f8880d", "Dumbbell Bench Press", .reps, .dumbbell),
        ("c42aefe2-ff42-5721-8887-c96f671c02b3", "Dumbbell Shoulder Press", .reps, .dumbbell),
        ("5b62bf0e-b53d-5aa7-af35-3b6390f460a4", "Dumbbell Row", .reps, .dumbbell),
        ("f13a073d-2eb8-52ad-831a-134e4507b710", "Dumbbell Curl", .reps, .dumbbell),
        ("fac22fe6-2c7f-5939-9a9f-ec32ab5c731c", "Lateral Raise", .reps, .dumbbell),
        ("3dd04f9e-88a8-5621-a3fd-b071edd2a5d7", "Dumbbell Lunge", .reps, .dumbbell),
        ("7b3e0354-90f5-5b97-ab36-d2e37da3449c", "Leg Press", .reps, .machine),
        ("13525c6a-4c72-5980-8856-09f39e975efa", "Leg Extension", .reps, .machine),
        ("78e4819c-b4a2-5fd3-a3ac-1cee95dee134", "Leg Curl", .reps, .machine),
        ("f79b36a5-6ec4-57e9-af2f-a14e1cc63457", "Lat Pulldown", .reps, .machine),
        ("3aeec4c8-d738-50d8-a172-977cc106da5c", "Seated Cable Row", .reps, .machine),
        ("28364cdb-83cd-5694-abc4-bb08342fb4e1", "Chest Fly Machine", .reps, .machine),
        ("92864045-f23d-5ea8-9f1a-c4756243b912", "Triceps Pushdown", .reps, .machine),
        ("3975018d-9a1c-544a-b43e-7599905b7daa", "Calf Raise", .reps, .machine),
        ("f35f7437-6112-5b92-a413-24caa694b4d6", "Push-up", .reps, .bodyweight),
        ("43556fe3-2709-533e-bc79-f6cd4bf4f3d6", "Pull-up", .reps, .bodyweight),
        ("4f530491-5631-5665-b7f5-147e2bba990e", "Chin-up", .reps, .bodyweight),
        ("0695844c-4e56-585b-8458-6e87de72019a", "Dip", .reps, .bodyweight),
        ("620a9bfc-ee20-50ca-9d89-6a46dd9b3ee4", "Bodyweight Squat", .reps, .bodyweight),
        ("ed920064-3670-51e8-b2c5-d210d2fe3a0a", "Sit-up", .reps, .bodyweight),
        ("83ff2eb2-20ef-53fc-b8bc-dff26de73d29", "Assisted Pull-up", .reps, .assistedBodyweight),
        ("18ed8013-e5b8-530a-840f-1705ea75413f", "Assisted Dip", .reps, .assistedBodyweight),
        ("410cca39-f6a7-5015-bf67-225580e2ba7d", "Plank", .duration, .bodyweight),
        ("941010a0-f1d2-59de-a1fd-4331e1d28d87", "Side Plank", .duration, .bodyweight),
        ("b2e74349-533a-551f-b97c-d3ae3fdb0a33", "Dead Hang", .duration, .bodyweight),
        ("29a05a10-5769-546b-b631-3b46c46f57f9", "Wall Sit", .duration, .bodyweight),
    ]

    static let all: [Entry] = table.map { row in
        Entry(id: UUID(uuidString: row.0)!, name: row.1, type: row.2, equipment: row.3)
    }

    static let ids: Set<UUID> = Set(all.map(\.id))
}
