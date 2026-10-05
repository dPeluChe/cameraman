import Foundation

extension Project {
    /// Closes the deleted range [start, end) for everything timed on the project timeline but not
    /// stored as a clip, so overlays, captions, chapters, zoom keyframes and imported media stay
    /// aligned with the footage after a ripple delete.
    mutating func rippleTimedItems(removing start: TimeInterval, to end: TimeInterval) {
        let width = end - start
        func rippled(_ t: TimeInterval) -> TimeInterval {
            if t <= start { return t }
            return t >= end ? t - width : start
        }
        // Items that collapse to nothing (fully inside the range) are dropped.
        func ripple<T>(_ items: [T], _ span: WritableKeyPath<T, (TimeInterval, TimeInterval)>) -> [T] {
            items.compactMap { item in
                let (s, e) = item[keyPath: span]
                let (ns, ne) = (rippled(s), rippled(e))
                guard ne - ns > 0.001 else { return nil }
                var out = item
                out[keyPath: span] = (ns, ne)
                return out
            }
        }

        overlays = ripple(overlays, \.span)
        subtitles = ripple(subtitles, \.span)
        chapters = ripple(chapters, \.span)
        mediaItems = ripple(mediaItems, \.span)
        manualZoomKeyframes = manualZoomKeyframes?
            .filter { !($0.timestamp > start && $0.timestamp < end) }
            .map { var k = $0; k.timestamp = rippled(k.timestamp); return k }
        updatedAt = Date()
    }
}

private extension Project.Overlay {
    var span: (TimeInterval, TimeInterval) {
        get { (start, end) }
        set { (start, end) = newValue }
    }
}

private extension Project.Chapter {
    var span: (TimeInterval, TimeInterval) {
        get { (startTime, endTime) }
        set { (startTime, endTime) = newValue }
    }
}

private extension Project.MediaItem {
    var span: (TimeInterval, TimeInterval) {
        get { (timelineIn, timelineOut) }
        set { (timelineIn, duration) = (newValue.0, newValue.1 - newValue.0) }
    }
}
