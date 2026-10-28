import SwiftData
import SwiftUI

extension Subscriptions {
    /// Subscribed through StoreKit on this Apple ID, or on any platform per the backend.
    func removesAds(_ profile: Profile) -> Bool {
        isEntitled || profile.serverSubscribed
    }
}

extension SetType {
    var color: Color {
        switch self {
        case .warmup: .orange
        case .failure: .red
        case .dropset: .blue
        case .superset: .purple
        case .workset: .gray
        }
    }
}

struct SetTypeBadge: View {
    let type: SetType
    var text: String?

    var body: some View {
        Text(text ?? type.rawValue)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .frame(minWidth: 26)
            .background(type.color.opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(type.color.opacity(0.45)))
            .foregroundStyle(type == .workset ? Color.primary : type.color)
    }
}

/// Lookup tables built once per render from the queried rows.
struct WorkoutIndex {
    let exercises: [UUID: Exercise]
    let setsByWorkout: [UUID: [WorkoutSet]]
    let itemsByWorkout: [UUID: [WorkoutExercise]]

    init(exercises: [Exercise], sets: [WorkoutSet], items: [WorkoutExercise]) {
        self.exercises = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        setsByWorkout = Dictionary(grouping: sets, by: \.workoutId).mapValues { $0.sorted { $0.position < $1.position } }
        itemsByWorkout = Dictionary(grouping: items, by: \.workoutId).mapValues { $0.sorted { $0.position < $1.position } }
    }

    /// Exercises of a workout in order, with their set count. Performed workouts
    /// only list exercises that have sets.
    func summary(of workout: Workout) -> [(exercise: Exercise, sets: [WorkoutSet])] {
        let sets = setsByWorkout[workout.id] ?? []
        var order: [UUID] = []
        for item in itemsByWorkout[workout.id] ?? [] where !order.contains(item.exerciseId) {
            if workout.planned || sets.contains(where: { $0.exerciseId == item.exerciseId }) {
                order.append(item.exerciseId)
            }
        }
        for set in sets where !order.contains(set.exerciseId) {
            order.append(set.exerciseId)
        }
        return order.compactMap { id in
            exercises[id].map { exercise in (exercise: exercise, sets: sets.filter { $0.exerciseId == id }) }
        }
    }

    func volume(of workoutId: UUID, bodyweight: Double?) -> Double {
        Records.volume(
            of: (setsByWorkout[workoutId] ?? []).map { (weight: $0.weight, reps: $0.reps, equipment: exercises[$0.exerciseId]?.equipment) },
            bodyweight: bodyweight
        )
    }
}

struct WorkoutsView: View {
    @Query(sort: \Workout.createdAt, order: .reverse) private var workouts: [Workout]
    @Query private var exercises: [Exercise]
    @Query private var items: [WorkoutExercise]
    @Query private var sets: [WorkoutSet]
    @Environment(Router.self) private var router
    @Environment(SyncEngine.self) private var sync
    @Environment(Subscriptions.self) private var subscriptions
    @Environment(Profile.self) private var profile

    var body: some View {
        let index = WorkoutIndex(exercises: exercises, sets: sets, items: items)
        let planned = workouts.filter(\.planned)
        let history = workouts.filter { !$0.planned }

        NavigationStack {
            List {
                Section("Planned") {
                    if planned.isEmpty {
                        Text("No planned workouts.").foregroundStyle(.secondary)
                    }
                    ForEach(planned) { workout in
                        NavigationLink(value: workout.id) {
                            WorkoutCard(workout: workout, summary: index.summary(of: workout))
                        }
                    }
                }
                Section("History") {
                    if history.isEmpty {
                        Text("No completed workouts yet.").foregroundStyle(.secondary)
                    }
                    ForEach(history) { workout in
                        NavigationLink(value: workout.id) {
                            WorkoutCard(workout: workout, summary: index.summary(of: workout))
                        }
                    }
                }
            }
            .navigationTitle("Workouts")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New workout", systemImage: "plus") {
                        router.open(.new, hasAds: !subscriptions.removesAds(profile))
                    }
                }
            }
            .refreshable { await sync.syncNow() }
            .navigationDestination(for: UUID.self) { id in
                WorkoutDetailView(workoutId: id)
            }
        }
    }
}

private struct WorkoutCard: View {
    let workout: Workout
    let summary: [(exercise: Exercise, sets: [WorkoutSet])]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(workout.name).font(.headline)
                Spacer()
                if !workout.planned {
                    VStack(alignment: .trailing) {
                        Text(Fmt.dateTime(workout.createdAt))
                        if let rpe = workout.rpe {
                            Text("RPE: \(Fmt.number(rpe))").fontWeight(.semibold).foregroundStyle(.primary)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            if let info = workout.info, !info.isEmpty {
                Text(info).font(.subheadline)
            }
            if summary.isEmpty {
                Text("No exercises added yet.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(summary, id: \.exercise.id) { entry in
                    Text("\(entry.sets.count) x \(entry.exercise.name)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct WorkoutDetailView: View {
    let workoutId: UUID
    @Query private var workouts: [Workout]
    @Query private var exercises: [Exercise]
    @Query private var items: [WorkoutExercise]
    @Query private var sets: [WorkoutSet]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router
    @Environment(Subscriptions.self) private var subscriptions
    @Environment(Profile.self) private var profile
    @State private var confirmDelete = false

    var body: some View {
        if let workout = workouts.first(where: { $0.id == workoutId }) {
            content(workout)
        } else {
            ContentUnavailableView("Workout not found", systemImage: "dumbbell")
        }
    }

    private func content(_ workout: Workout) -> some View {
        let index = WorkoutIndex(exercises: exercises, sets: sets, items: items)
        let volume = index.volume(of: workout.id, bodyweight: profile.bodyweight)
        let heaviest = Records.descendants(of: workout.id, in: workouts, id: \.id, source: \.sourceWorkoutId)
            .filter { !$0.planned }
            .map { index.volume(of: $0.id, bodyweight: profile.bodyweight) }
            .max()
        let groups = index.summary(of: workout)
        let notes = Dictionary((index.itemsByWorkout[workout.id] ?? []).map { ($0.exerciseId, $0.note) }, uniquingKeysWith: { a, _ in a })

        return List {
            Section {
                LabeledContent(workout.planned ? "Created on" : "Completed on", value: Fmt.dateTime(workout.createdAt))
                LabeledContent(workout.planned ? "Planned total volume" : "Total volume", value: Fmt.volume(volume))
                if workout.planned {
                    LabeledContent("Heaviest total volume", value: heaviest.map(Fmt.volume) ?? "—")
                }
                if let rpe = workout.rpe {
                    LabeledContent("RPE", value: Fmt.number(rpe))
                }
                if let info = workout.info, !info.isEmpty {
                    Text(info)
                }
                if let note = workout.note, !note.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Post workout note").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(note)
                    }
                }
            }

            if groups.isEmpty {
                Text("No exercises recorded for this workout yet.").foregroundStyle(.secondary)
            }
            ForEach(groups, id: \.exercise.id) { group in
                Section(group.exercise.name) {
                    if let note = notes[group.exercise.id] ?? nil, !note.isEmpty {
                        Text(note).font(.subheadline).italic().foregroundStyle(.secondary)
                    }
                    if group.sets.isEmpty {
                        Text("No sets for this exercise.").font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        SetTable(exercise: group.exercise, sets: group.sets)
                    }
                }
            }
        }
        .navigationTitle(workout.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Start") {
                    router.open(.start(workout.id), hasAds: !subscriptions.removesAds(profile))
                }
                .fontWeight(.semibold)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu("More", systemImage: "ellipsis.circle") {
                    if workout.planned {
                        Button("Edit", systemImage: "pencil") { router.editor = .edit(workout.id) }
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .alert("Delete workout \"\(workout.name)\"?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                context.deleteWorkout(workout)
                context.commit()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct SetTable: View {
    let exercise: Exercise
    let sets: [WorkoutSet]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("Set")
                Text("Type")
                Text(exercise.equipment.weightLabel)
                Text(exercise.type == .reps ? "Reps" : "Sec")
                Text("RPE")
                Text("Rest")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            ForEach(Array(sets.enumerated()), id: \.element.id) { offset, set in
                GridRow {
                    Text("\(offset + 1)")
                    SetTypeBadge(type: set.type)
                    Text(Fmt.number(set.weight ?? 0))
                    Text("\(exercise.type == .reps ? (set.reps ?? 0) : (set.duration ?? 0))")
                    Text(Fmt.number(set.rpe ?? 0))
                    Text("\(set.rest)s")
                }
                .font(.subheadline.monospacedDigit())
            }
        }
    }
}
