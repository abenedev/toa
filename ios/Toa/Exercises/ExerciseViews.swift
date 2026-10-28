import SwiftData
import SwiftUI

private func matches(_ exercise: Exercise, _ query: String) -> Bool {
    let query = query.trimmed.lowercased()
    guard !query.isEmpty else { return true }
    return exercise.name.lowercased().contains(query)
        || (exercise.info?.lowercased().contains(query) ?? false)
        || exercise.typeRaw.lowercased().contains(query)
        || exercise.equipment.label.lowercased().contains(query)
}

struct ExercisesView: View {
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var search = ""
    @State private var creating = false

    var body: some View {
        let filtered = exercises.filter { matches($0, search) }
        NavigationStack {
            List {
                if filtered.isEmpty {
                    Text(search.isEmpty ? "No exercises yet." : "No exercises match your search.")
                        .foregroundStyle(.secondary)
                }
                ForEach(filtered) { exercise in
                    NavigationLink(value: exercise.id) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(exercise.name).font(.headline)
                                if exercise.isDefault { DefaultBadge() }
                            }
                            if let info = exercise.info, !info.isEmpty {
                                Text(info).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Text("\(exercise.type.shortLabel) · \(exercise.equipment.label)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search exercises")
            .navigationTitle("Exercises")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Create exercise", systemImage: "plus") { creating = true }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                ExerciseDetailView(exerciseId: id)
            }
            .sheet(isPresented: $creating) {
                ExerciseFormView(exercise: nil)
            }
        }
    }
}

struct DefaultBadge: View {
    var body: some View {
        Text("Default")
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15), in: Capsule())
            .foregroundStyle(.secondary)
    }
}

struct ExerciseDetailView: View {
    let exerciseId: UUID
    @Query private var exercises: [Exercise]
    @Query private var sets: [WorkoutSet]
    @Query private var workouts: [Workout]
    @Environment(Profile.self) private var profile
    @State private var editing = false
    @State private var showInfo = false

    init(exerciseId: UUID) {
        self.exerciseId = exerciseId
        _sets = Query(filter: #Predicate<WorkoutSet> { $0.exerciseId == exerciseId })
    }

    var body: some View {
        if let exercise = exercises.first(where: { $0.id == exerciseId }) {
            content(exercise)
        } else {
            ContentUnavailableView("Exercise not found", systemImage: "books.vertical")
        }
    }

    private func content(_ exercise: Exercise) -> some View {
        let dates = Dictionary(workouts.filter { !$0.planned }.map { ($0.id, $0.createdAt) }, uniquingKeysWith: { a, _ in a })
        let history = sets.compactMap { set in
            dates[set.workoutId].map { PerformedSet(weight: set.weight, rpe: set.rpe, reps: set.reps, duration: set.duration, date: $0) }
        }
        let records = Records.compute(type: exercise.type, equipment: exercise.equipment, sets: history, bodyweight: profile.bodyweight)

        return List {
            Section {
                if let info = exercise.info, !info.isEmpty { Text(info) }
                LabeledContent("Type", value: exercise.type.label)
                LabeledContent("Equipment", value: exercise.equipment.label)
            }
            Section("Personal Records") {
                if records.isEmpty {
                    Text("No personal records yet — log some workouts to see them here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(records.records) { record in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(record.label).fontWeight(.medium)
                                if record.kind == .estimated1RM {
                                    Button { showInfo = true } label: {
                                        Image(systemName: "questionmark.circle")
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("How is Estimated 1RM calculated?")
                                    .popover(isPresented: $showInfo) {
                                        Text("Calculated with the Epley formula, taking into account weight, reps & RPE (reps in reserve are added to your reps).")
                                            .font(.footnote)
                                            .padding()
                                            .frame(width: 260)
                                            .presentationCompactAdaptation(.popover)
                                    }
                                }
                            }
                            if let date = record.date {
                                Text(Fmt.date(date)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(recordValue(record)).fontWeight(.semibold).multilineTextAlignment(.trailing)
                    }
                }
            }
            if !records.repsPerWeight.isEmpty {
                Section("Most reps per weight") {
                    ForEach(records.repsPerWeight) { best in
                        bestRow(weight: best.weight, value: "\(best.value) \(Fmt.repUnit(best.value))", date: best.date)
                    }
                }
            }
            if !records.durationPerWeight.isEmpty {
                Section("Longest duration per weight") {
                    ForEach(records.durationPerWeight) { best in
                        bestRow(weight: best.weight, value: "\(best.value) s", date: best.date)
                    }
                }
            }
        }
        .navigationTitle(exercise.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if exercise.isDefault {
                    DefaultBadge()
                } else {
                    Button("Edit") { editing = true }
                }
            }
        }
        .sheet(isPresented: $editing) {
            ExerciseFormView(exercise: exercise)
        }
    }

    private func recordValue(_ record: PersonalRecord) -> String {
        let value = "\(Fmt.number(record.value)) \(record.unit)"
        if record.kind == .maxVolume, let detail = record.detail { return "\(value) (\(detail))" }
        return value
    }

    private func bestRow(weight: Double, value: String, date: Date?) -> some View {
        HStack {
            Text("\(Fmt.number(weight)) kg")
            Spacer()
            Text(value).fontWeight(.semibold)
            if let date {
                Text(Fmt.date(date)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Create (exercise == nil) or edit a private exercise.
struct ExerciseFormView: View {
    let exercise: Exercise?
    var prefilledName = ""
    var onCreated: ((Exercise) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var exercises: [Exercise]
    @State private var name = ""
    @State private var info = ""
    @State private var type = ExerciseType.reps
    @State private var equipment: Equipment?
    @State private var confirmDelete = false
    @State private var loaded = false

    private var duplicate: Bool {
        let key = name.trimmed.lowercased()
        return exercises.contains { $0.id != exercise?.id && $0.name.lowercased() == key }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Description (optional)", text: $info, axis: .vertical)
                } footer: {
                    if duplicate { Text("An exercise with this name already exists.").foregroundStyle(.red) }
                }
                Section {
                    Picker("Type", selection: $type) {
                        ForEach(ExerciseType.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Equipment", selection: $equipment) {
                        Text("Select equipment").tag(Equipment?.none)
                        ForEach(Equipment.allCases) { Text($0.label).tag(Equipment?.some($0)) }
                    }
                }
                if let exercise {
                    Section {
                        Button("Delete exercise", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Its sets are removed from all your workouts.")
                    }
                    .alert("Are you sure you want to delete this exercise?", isPresented: $confirmDelete) {
                        Button("Delete", role: .destructive) {
                            context.deleteExercise(exercise)
                            context.commit()
                            dismiss()
                        }
                        Button("Cancel", role: .cancel) {}
                    }
                }
            }
            .navigationTitle(exercise == nil ? "Create Exercise" : "Edit Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(exercise == nil ? (onCreated == nil ? "Create" : "Create & Add") : "Save", action: save)
                        .disabled(name.trimmed.isEmpty || equipment == nil || duplicate)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let exercise {
            name = exercise.name
            info = exercise.info ?? ""
            type = exercise.type
            equipment = exercise.equipment
        } else {
            name = prefilledName
        }
    }

    private func save() {
        guard let equipment else { return }
        if let exercise {
            exercise.name = name.trimmed
            exercise.info = info.nilIfEmpty
            exercise.type = type
            exercise.equipment = equipment
            exercise.updatedAt = .nowMillis
            exercise.needsSync = true
            context.commit()
        } else {
            let created = Exercise(name: name.trimmed, info: info.nilIfEmpty, type: type, equipment: equipment)
            context.insert(created)
            context.commit()
            onCreated?(created)
        }
        dismiss()
    }
}

/// Exercise search used by the workout editor, with inline creation.
struct ExercisePickerView: View {
    let onSelect: (Exercise) -> Void
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var creating = false

    var body: some View {
        let filtered = exercises.filter { matches($0, search) }
        NavigationStack {
            List {
                if filtered.isEmpty {
                    Button(search.isEmpty ? "Create exercise" : "Create \"\(search.trimmed)\"", systemImage: "plus") {
                        creating = true
                    }
                }
                ForEach(filtered) { exercise in
                    Button {
                        onSelect(exercise)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(exercise.name).foregroundStyle(.primary)
                                if let info = exercise.info, !info.isEmpty {
                                    Text(info).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer()
                            Text(exercise.equipment.label).font(.caption).foregroundStyle(.secondary)
                            Text(exercise.type.shortLabel).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search by name or equipment")
            .navigationTitle("Select Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Create", systemImage: "plus") { creating = true }
                }
            }
            .sheet(isPresented: $creating) {
                ExerciseFormView(exercise: nil, prefilledName: search.trimmed) { created in
                    onSelect(created)
                    dismiss()
                }
            }
        }
    }
}
