import Foundation

enum ExerciseType: String, Codable, CaseIterable, Identifiable {
    case reps = "REPS"
    case duration = "DURATION"

    var id: String { rawValue }
    var label: String { self == .reps ? "Rep-based" : "Duration-based" }
    var shortLabel: String { self == .reps ? "Reps" : "Duration" }
}

enum Equipment: String, Codable, CaseIterable, Identifiable {
    case barbell = "BARBELL"
    case dumbbell = "DUMBBELL"
    case machine = "MACHINE"
    case bodyweight = "BODYWEIGHT"
    case assistedBodyweight = "ASSISTED_BODYWEIGHT"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .barbell: "Barbell"
        case .dumbbell: "Dumbbell"
        case .machine: "Machine"
        case .bodyweight: "Bodyweight"
        case .assistedBodyweight: "Assisted Bodyweight"
        }
    }

    /// Unit shown above the weight column: assistance is subtracted, bodyweight load is added.
    var weightLabel: String {
        switch self {
        case .assistedBodyweight: "-kg"
        case .bodyweight: "+kg"
        default: "kg"
        }
    }
}

enum SetType: String, Codable, CaseIterable, Identifiable {
    case workset = "WORKSET"
    case warmup = "WARMUP"
    case dropset = "DROPSET"
    case superset = "SUPERSET"
    case failure = "FAILURE"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .workset: "Workset"
        case .warmup: "Warmup"
        case .dropset: "Dropset"
        case .superset: "Superset"
        case .failure: "Failure"
        }
    }

    var shortLabel: String {
        switch self {
        case .workset: ""
        case .warmup: "W"
        case .dropset: "D"
        case .superset: "S"
        case .failure: "F"
        }
    }
}

enum Fmt {
    /// Locale-aware number without grouping, e.g. "62.5" or "62,5".
    static func number(_ value: Double, maxFractionDigits: Int = 2) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = maxFractionDigits
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// Grouped number for totals, e.g. "12,345.5 kg".
    static func volume(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return "\(formatter.string(from: NSNumber(value: value)) ?? String(value)) kg"
    }

    static func dateTime(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    static func date(_ date: Date) -> String {
        date.formatted(date: .numeric, time: .omitted)
    }

    static func repUnit(_ count: Int) -> String {
        count > 1 ? "reps" : "rep"
    }

    /// Accepts both "62.5" and "62,5" (decimal pads use the locale separator).
    static func parseDouble(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !trimmed.isEmpty, let value = Double(trimmed), value.isFinite else { return nil }
        return value
    }

    static func parseInt(_ text: String) -> Int? {
        parseDouble(text).map { Int($0.rounded()) }
    }
}

extension Date {
    /// Timestamps are compared across devices with millisecond precision (see backend/SYNC.md).
    static var nowMillis: Date {
        let ms = (Date().timeIntervalSince1970 * 1000).rounded(.down)
        return Date(timeIntervalSince1970: ms / 1000)
    }
}
