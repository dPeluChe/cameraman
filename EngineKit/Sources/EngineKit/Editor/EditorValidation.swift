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

    public static func validateAdjustment(
        _ adjustment: Project.Adjustment,
        clipDuration: TimeInterval
    ) -> EditorError? {
        guard !adjustment.kind.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return invalid("adjustment kind must not be empty")
        }
        guard adjustment.parameters.values.allSatisfy(\.isFinite) else {
            return invalid("adjustment parameters must be finite")
        }
        guard adjustment.kind.isAudio == (adjustment.target == .audio) else {
            return invalid("audio adjustments must target audio and visual adjustments must target video")
        }
        if let start = adjustment.start,
           (!start.isFinite || start < 0 || start > clipDuration) {
            return invalid("adjustment start must be inside the clip duration")
        }
        if let end = adjustment.end,
           (!end.isFinite || end <= 0 || end > clipDuration) {
            return invalid("adjustment end must be inside the clip duration")
        }
        if let start = adjustment.start, let end = adjustment.end, start >= end {
            return invalid("adjustment start must be before its end")
        }

        let ranges: [String: ClosedRange<Double>]
        switch adjustment.kind {
        case .sepia:
            ranges = ["intensity": 0...1]
        case .brightness:
            ranges = ["brightness": -1...1]
        case .contrast:
            ranges = ["contrast": 0...4]
        case .saturation:
            ranges = ["saturation": 0...2]
        case .colorControls:
            ranges = ["brightness": -1...1, "contrast": 0...4, "saturation": 0...2]
        case .vibrance:
            ranges = ["amount": -1...1]
        case .vignette:
            ranges = ["intensity": 0...1, "radius": 0...2]
        case .gaussianBlur:
            ranges = ["radius": 0...100]
        case .audioPitch:
            ranges = ["cents": -2400...2400, "semitones": -24...24]
        case .audioGain:
            ranges = ["gain": 0...4]
        default:
            ranges = [:]
        }
        for (key, range) in ranges {
            if let value = adjustment.parameters[key], !range.contains(value) {
                return invalid("adjustment parameter \(key) must be between \(range.lowerBound) and \(range.upperBound)")
            }
        }
        return nil
    }

    public static func validateOverlay(
        _ overlay: Project.Overlay,
        timelineDuration: TimeInterval
    ) -> EditorError? {
        guard timelineDuration.isFinite, timelineDuration >= 0,
              overlay.start.isFinite, overlay.end.isFinite,
              overlay.start >= 0, overlay.start < overlay.end,
              overlay.end <= timelineDuration else {
            return invalid("overlay timing must be finite, non-empty, and inside the timeline")
        }
        let transform = overlay.transform
        guard [transform.x, transform.y, transform.scale, transform.rotation].allSatisfy(\.isFinite),
              transform.scale > 0 else {
            return invalid("overlay transform must be finite with a positive scale")
        }
        let style = overlay.style
        guard style.strokeWidth.isFinite, style.strokeWidth >= 0 else {
            return invalid("overlay stroke width must be finite and non-negative")
        }
        if let size = style.size, (!size.isFinite || size <= 0) {
            return invalid("overlay font size must be finite and greater than zero")
        }
        if let opacity = style.imageOpacity, !isUnitValue(opacity) {
            return invalid("overlay image opacity must be finite and between 0 and 1")
        }
        if overlay.type == .text,
           style.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            return invalid("text overlays require non-empty text")
        }
        if overlay.type == .image,
           style.imagePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            return invalid("image overlays require a non-empty image path")
        }
        if let animation = overlay.animation {
            let values = [animation.fadeInDuration, animation.fadeOutDuration]
            guard values.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
                return invalid("overlay animation durations must be finite and non-negative")
            }
            if let drawOn = animation.drawOnDuration,
               (!drawOn.isFinite || drawOn < 0) {
                return invalid("overlay draw-on duration must be finite and non-negative")
            }
            let duration = overlay.end - overlay.start
            switch animation.type {
            case .fadeIn where animation.fadeInDuration > duration,
                 .fadeOut where animation.fadeOutDuration > duration,
                 .fadeInOut where animation.fadeInDuration + animation.fadeOutDuration > duration,
                 .drawOn where (animation.drawOnDuration ?? 0) > duration:
                return invalid("overlay animation exceeds the overlay duration")
            default:
                break
            }
        }
        return nil
    }

    public static func validateMediaItem(_ item: Project.MediaItem) -> EditorError? {
        guard !item.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return invalid("media item path must not be empty")
        }
        guard item.timelineIn.isFinite, item.timelineIn >= 0,
              item.duration.isFinite, item.duration > 0,
              item.timelineOut.isFinite else {
            return invalid("media item timing must be finite, non-negative, and non-empty")
        }
        guard isUnitValue(item.volume), isUnitValue(item.opacity) else {
            return invalid("media item volume and opacity must be finite and between 0 and 1")
        }
        if let position = item.position, let error = validatePosition(position) {
            return error
        }
        return nil
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
