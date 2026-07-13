import Foundation

public enum EditorValidation {
    public static func validateClip(_ clip: Project.TimelineClip) -> EditorError? {
        guard clip.timelineIn.isFinite, clip.timelineIn >= 0 else {
            return invalid("timelineIn must be finite and non-negative")
        }
        guard clip.speed.isFinite, clip.speed > 0 else {
            return invalid("speed must be finite and greater than zero")
        }
        if let volume = clip.volume, !isUnitValue(volume) {
            return invalid("volume must be finite and between 0 and 1")
        }
        if let opacity = clip.opacity, !isUnitValue(opacity) {
            return invalid("opacity must be finite and between 0 and 1")
        }
        if let position = clip.position, let error = validatePosition(position) {
            return error
        }

        switch clip.content {
        case .recording(let reference):
            if let error = validateSourceRange(sourceIn: reference.sourceIn, sourceOut: reference.sourceOut) {
                return error
            }
        case .video(let reference):
            guard !reference.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return invalid("video path must not be empty")
            }
            if let error = validateSourceRange(sourceIn: reference.sourceIn, sourceOut: reference.sourceOut) {
                return error
            }
        case .image(let reference):
            guard !reference.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return invalid("image path must not be empty")
            }
            if let error = validateDuration(reference.duration) { return error }
        case .audio(let reference):
            guard !reference.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return invalid("audio path must not be empty")
            }
            guard reference.sourceIn.isFinite, reference.sourceIn >= 0 else {
                return invalid("sourceIn must be finite and non-negative")
            }
            if let error = validateDuration(reference.duration) { return error }
        case .color(let reference):
            if let error = validateDuration(reference.duration) { return error }
        }

        guard clip.duration.isFinite, clip.duration > 0, clip.timelineOut.isFinite else {
            return invalid("derived clip timing must be finite and greater than zero")
        }
        return nil
    }

    public static func validateUnitValue(_ value: Double, field: String) -> EditorError? {
        isUnitValue(value) ? nil : invalid("\(field) must be finite and between 0 and 1")
    }

    private static func validatePosition(_ position: Project.MediaPosition) -> EditorError? {
        let values = [position.x, position.y, position.w, position.h]
        guard values.allSatisfy(\.isFinite),
              position.x >= 0, position.y >= 0,
              position.w > 0, position.h > 0,
              position.x + position.w <= 1,
              position.y + position.h <= 1 else {
            return invalid("position must define a finite rectangle inside the normalized canvas")
        }
        return nil
    }

    private static func validateSourceRange(sourceIn: Double, sourceOut: Double) -> EditorError? {
        guard sourceIn.isFinite, sourceOut.isFinite, sourceIn >= 0, sourceOut > sourceIn else {
            return invalid("source range must be finite, non-negative, and non-empty")
        }
        return nil
    }

    private static func validateDuration(_ duration: Double) -> EditorError? {
        guard duration.isFinite, duration > 0 else {
            return invalid("duration must be finite and greater than zero")
        }
        return nil
    }

    private static func isUnitValue(_ value: Double) -> Bool {
        value.isFinite && (0...1).contains(value)
    }

    private static func invalid(_ reason: String) -> EditorError {
        .invalidClipContent(reason: reason)
    }
}
