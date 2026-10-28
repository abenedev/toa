import SwiftData
import SwiftUI
import UIKit

/// Loads the draft for the requested editor, then shows it.
struct WorkoutEditorView: View {
    let editor: Router.Editor
    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router
    @State private var draft: WorkoutDraft?

    var body: some View {
        Group {
            if let draft {
                DraftEditorView(initial: draft)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            guard draft == nil else { return }
            if let made = context.makeDraft(editor) {
                draft = made
            } else {
                router.discardDraft()
            }
        }
    }
}

private enum Confirmation: Identifiable {
    case cancel, save, finish
    var id: Self { self }
}

struct DraftEditorView: View {
    @State private var draft: WorkoutDraft
    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router
    @Environment(Profile.self) private var profile
    @Query private var exercises: [Exercise]

    @State private var restTimer = RestTimer()
    @State private var confetti = 0
    @State private var sessionBest: [UUID: Double] = [:]
    @State private var showPicker = false
    @State private var showRestTimer = false
    @State private var showReorder = false
    @State private var showSummary = false
    @State private var confirmation: Confirmation?

    init(initial: WorkoutDraft) {
        _draft = State(initialValue: initial)
    }

    private var exerciseById: [UUID: Exercise] {
        Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        let byId = exerciseById
        NavigationStack {
            List {
                header
                ForEach(draft.groups) { group in
                    groupSection(group, exercise: byId[group.exerciseId])
                }
                Section {
                    Button("Add exercise", systemImage: "plus") { showPicker = true }
                    if draft.groups.count > 1 {
                        Button("Reorder exercises", systemImage: "arrow.up.arrow.down") { showReorder = true }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .overlay { ConfettiView(trigger: confetti) }
        .sensoryFeedback(.success, trigger: draft.completedSetCount)
        .onChange(of: draft) { DraftStore.save(draft) }
        .onAppear { DraftStore.save(draft) }
        .sheet(isPresented: $showPicker) {
            ExercisePickerView { exercise in
                draft.addExercise(id: exercise.id, isDuration: exercise.type == .duration)
            }
        }
        .sheet(isPresented: $showRestTimer) { RestTimerSheet(timer: restTimer) }
        .sheet(isPresented: $showReorder) {
            ReorderSheet(groups: $draft.groups, names: byId.mapValues(\.name))
        }
        .sheet(isPresented: $showSummary) {
            PostWorkoutSheet(draft: $draft) {
                context.finishDraft(draft)
                close()
            }
        }
        .alert(confirmationTitle, isPresented: confirmationShown, presenting: confirmation) { kind in
            Button("No", role: .cancel) {}
            Button("Yes") { confirm(kind) }
        } message: { kind in
            Text(confirmationMessage(kind))
        }
    }

    // MARK: Sections

    @ViewBuilder private var header: some View {
        Section {
            TextField("Workout name", text: $draft.name)
                .font(.title2.bold())
            TextField("Description (optional)", text: $draft.info, axis: .vertical)
            if draft.isActive {
                HStack {
                    Label {
                        Text(draft.startedAt, style: .timer).monospacedDigit()
                    } icon: {
                        Image(systemName: "stopwatch")
                    }
                    .font(.title3.weight(.semibold))
                    Spacer()
                    Button("Rest Timer", systemImage: "timer") { showRestTimer = true }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                }
                if let end = restTimer.endDate, restTimer.isRunning {
                    HStack {
                        Text("Rest: \(Text(timerInterval: Date.now...max(end, Date.now), countsDown: true))")
                            .monospacedDigit()
                            .fontWeight(.semibold)
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("-15s") { restTimer.adjust(by: -15) }
                        Button("+15s") { restTimer.adjust(by: 15) }
                        Button("Skip", role: .destructive) { restTimer.stop() }
                    }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
                }
            }
        }
    }

    private func groupSection(_ group: DraftGroup, exercise: Exercise?) -> some View {
        let equipment = exercise?.equipment ?? .barbell
        return Section {
            HStack {
                Text(exercise?.name ?? "Deleted exercise").font(.headline)
                Spacer()
                Button(role: .destructive) {
                    draft.groups.removeAll { $0.id == group.id }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            TextField("Add a note", text: groupNote(group.id), axis: .vertical)
                .font(.subheadline)
            HStack {
                Text("Rest (s)").font(.subheadline.weight(.medium))
                TextField("0", value: groupRest(group.id), format: .number)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                Spacer()
            }
            HStack(spacing: 8) {
                Text("Type").frame(width: 44)
                Text(equipment.weightLabel).frame(maxWidth: .infinity)
                Text(group.isDuration ? "Sec" : "Reps").frame(maxWidth: .infinity)
                Text("RPE").frame(width: 52)
                if draft.isActive { Color.clear.frame(width: 40, height: 1) }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            ForEach(group.sets) { set in
                setRow(set, in: group, exercise: exercise)
                    .listRowBackground(set.completed ? Color.green.opacity(0.18) : nil)
                    .swipeActions {
                        Button(role: .destructive) {
                            draft.deleteSet(set.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
            Button("Add set", systemImage: "plus") { draft.addSet(toGroup: group.id) }
                .buttonStyle(.borderless)
        }
    }

    private func setRow(_ set: DraftSet, in group: DraftGroup, exercise: Exercise?) -> some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(SetType.allCases) { type in
                    Button(type.label) { draft.setType(type, forSet: set.id) }
                }
            } label: {
                SetTypeBadge(type: set.type, text: WorkoutDraft.typeDisplay(of: set, in: group))
                    .frame(width: 44)
            }
            numberField(set.planned.weight.map { Fmt.number($0) } ?? "0", text: field(set.id, \.weight), decimal: true)
            if group.isDuration {
                numberField(set.planned.duration.map { String($0) } ?? "0", text: field(set.id, \.duration), decimal: false)
            } else {
                numberField(set.planned.reps.map { String($0) } ?? "0", text: field(set.id, \.reps), decimal: false)
            }
            numberField(set.planned.rpe.map { Fmt.number($0) } ?? "", text: field(set.id, \.rpe), decimal: true)
                .frame(width: 52)
            if draft.isActive {
                Button {
                    complete(set, in: group, exercise: exercise)
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "checkmark")
                            .fontWeight(.bold)
                            .frame(width: 40, height: 34)
                            .foregroundStyle(set.completed ? Color.white : Color.green)
                            .background(set.completed ? Color.green : Color.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                        if set.completed && set.isRecord {
                            Image(systemName: "trophy.fill")
                                .font(.caption2)
                                .foregroundStyle(Color.yellow)
                                .offset(x: 4, y: -6)
                                .accessibilityLabel("New personal record")
                        }
                    }
                }
            }
        }
        .buttonStyle(.borderless)
    }

    private func numberField(_ placeholder: String, text: Binding<String>, decimal: Bool) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(decimal ? .decimalPad : .numberPad)
            .multilineTextAlignment(.center)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: .infinity)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(draft.mode == .edit ? "Discard" : "Cancel") { confirmation = .cancel }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(draft.isActive ? "Finish" : "Save") {
                confirmation = draft.isActive ? .finish : .save
            }
            .disabled(!draft.isActive && draft.name.trimmed.isEmpty)
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
    }

    // MARK: Bindings by id (safe when rows are removed)

    private func field(_ setId: UUID, _ keyPath: WritableKeyPath<DraftSet, String>) -> Binding<String> {
        Binding(
            get: {
                for group in draft.groups {
                    if let set = group.sets.first(where: { $0.id == setId }) { return set[keyPath: keyPath] }
                }
                return ""
            },
            set: { value in draft.updateSet(setId) { $0[keyPath: keyPath] = value } }
        )
    }

    private func groupNote(_ groupId: UUID) -> Binding<String> {
        Binding(
            get: { draft.groups.first { $0.id == groupId }?.note ?? "" },
            set: { value in
                if let index = draft.groups.firstIndex(where: { $0.id == groupId }) { draft.groups[index].note = value }
            }
        )
    }

    private func groupRest(_ groupId: UUID) -> Binding<Int> {
        Binding(
            get: { draft.groups.first { $0.id == groupId }?.rest ?? 0 },
            set: { value in
                if let index = draft.groups.firstIndex(where: { $0.id == groupId }) { draft.groups[index].rest = max(0, value) }
            }
        )
    }

    // MARK: Actions

    private func complete(_ set: DraftSet, in group: DraftGroup, exercise: Exercise?) {
        guard draft.toggleCompleted(set.id) else {
            restTimer.stop()
            return
        }
        Sounds.shared.playSetCheck()
        if let exercise { checkRecord(set.id, exercise: exercise) }
        if group.rest > 0 { restTimer.start(seconds: group.rest) }
    }

    /// Trophy + confetti when a set beats the stored estimated 1RM or heaviest weight.
    private func checkRecord(_ setId: UUID, exercise: Exercise) {
        guard exercise.type == .reps, exercise.equipment != .assistedBodyweight,
              let set = draft.groups.flatMap(\.sets).first(where: { $0.id == setId }),
              let weight = Fmt.parseDouble(set.weight), weight > 0,
              let reps = Fmt.parseInt(set.reps), reps > 0
        else { return }

        let prior = Records.compute(type: exercise.type, equipment: exercise.equipment,
                                    sets: context.history(of: exercise.id), bodyweight: profile.bodyweight)
        let priorE1RM = prior.value(of: .estimated1RM)
        let priorWeight = prior.value(of: .heaviestWeight) ?? prior.value(of: .additionalWeight)
        // Without history there is nothing to beat
        guard priorE1RM != nil || priorWeight != nil else { return }

        let performed = PerformedSet(weight: weight, rpe: Fmt.parseDouble(set.rpe), reps: reps, date: Date())
        let load = Records.load(of: performed, isBodyweight: exercise.equipment == .bodyweight, bodyweight: profile.bodyweight) ?? weight
        let estimate = Records.estimated1RM(load: load, reps: reps, rpe: performed.rpe)
        let best = sessionBest[exercise.id] ?? 0
        let beatsE1RM = priorE1RM.map { Records.round1(estimate) > max($0, best) } ?? false
        let beatsWeight = priorWeight.map { weight > $0 } ?? false
        sessionBest[exercise.id] = max(best, estimate)
        guard beatsE1RM || beatsWeight else { return }

        draft.updateSet(setId) { $0.isRecord = true }
        confetti += 1
    }

    private func confirm(_ kind: Confirmation) {
        switch kind {
        case .cancel:
            close()
        case .save:
            context.saveDraft(draft)
            close()
        case .finish:
            showSummary = true
        }
    }

    private func close() {
        restTimer.stop()
        router.discardDraft()
    }

    // MARK: Texts

    private var title: String {
        switch draft.mode {
        case .new: "New workout"
        case .edit: "Edit workout"
        case .active: "Workout"
        }
    }

    private var confirmationShown: Binding<Bool> {
        Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })
    }

    private var confirmationTitle: String {
        switch confirmation {
        case .cancel: draft.mode == .edit ? "Discard changes" : "Cancel workout"
        case .save: "Save workout"
        case .finish: "Finish workout"
        case nil: ""
        }
    }

    private func confirmationMessage(_ kind: Confirmation) -> String {
        switch (kind, draft.mode) {
        case (.cancel, .new): "Are you sure you want to cancel creating this workout?"
        case (.cancel, .edit): "Are you sure you want to discard your changes?"
        case (.cancel, .active): "Are you sure you want to cancel your workout?"
        case (.save, _): "Are you sure you want to save your workout?"
        case (.finish, _): "Are you sure you want to finish your workout?"
        }
    }
}

private struct PostWorkoutSheet: View {
    @Binding var draft: WorkoutDraft
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 4) {
                        ForEach(1...10, id: \.self) { value in
                            Button {
                                draft.rpe = draft.rpe == value ? nil : value
                            } label: {
                                Text("\(value)")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(width: 28, height: 28)
                                    .background(Circle().fill(draft.rpe == value ? Color.accentColor : Color.secondary.opacity(0.15)))
                                    .foregroundStyle(draft.rpe == value ? Color.white : Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity)
                } header: {
                    Text("Overall RPE")
                } footer: {
                    Text("Rate the perceived difficulty of the entire workout (1-10).")
                }
                Section("Note") {
                    TextField("How did this workout feel? PRs, fatigue, reflections...", text: $draft.note, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle("Post Workout Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Workout") {
                        dismiss()
                        onSave()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ReorderSheet: View {
    @Binding var groups: [DraftGroup]
    let names: [UUID: String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups) { group in
                    Text(names[group.exerciseId] ?? "Exercise")
                }
                .onMove { groups.move(fromOffsets: $0, toOffset: $1) }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

struct RestTimerSheet: View {
    let timer: RestTimer
    @Environment(\.dismiss) private var dismiss
    @State private var minutes = 1
    @State private var seconds = 30

    private let presets: [(String, Int)] = [
        ("30s", 30), ("60s", 60), ("90s", 90), ("2m", 120), ("2m 30s", 150), ("3m", 180), ("5m", 300),
    ]

    var body: some View {
        NavigationStack {
            Form {
                if let end = timer.endDate, timer.isRunning {
                    Section("Active timer running") {
                        VStack(spacing: 12) {
                            Text(timerInterval: Date.now...max(end, Date.now), countsDown: true)
                                .font(.system(size: 44, weight: .bold, design: .monospaced))
                                .foregroundStyle(.orange)
                            HStack {
                                Button("-15s") { timer.adjust(by: -15) }
                                Button("+15s") { timer.adjust(by: 15) }
                                Button("Stop Timer", role: .destructive) {
                                    timer.stop()
                                    dismiss()
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                Section("Quick presets") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4)) {
                        ForEach(presets, id: \.1) { preset in
                            Button(preset.0) {
                                timer.start(seconds: preset.1)
                                dismiss()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                Section("Custom duration") {
                    Stepper("Minutes: \(minutes)", value: $minutes, in: 0...60)
                    Stepper("Seconds: \(seconds)", value: $seconds, in: 0...59, step: 5)
                    Button("Start Timer") {
                        timer.start(seconds: minutes * 60 + seconds)
                        dismiss()
                    }
                    .disabled(minutes * 60 + seconds == 0)
                }
            }
            .navigationTitle("Rest Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
