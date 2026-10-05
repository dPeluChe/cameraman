import Foundation

extension Project {
    /// Closes the deleted range [start, end) for everything timed on the project timeline but not
    /// stored as a clip, so overlays, captions, chapters, zoom keyframes and imported media stay
    /// aligned with the footage after a ripple delete.
    mutating func rippleTimedItems(removing start: TimeInterval, to end: TimeInterval) {
        let width = end - start
        retimeTimedItems(
            map: { t in t <= start ? t : (t >= end ? t - width : start) },
            dropsKeyframe: { $0 > start && $0 < end }
        )
    }

    /// Opens `width` seconds at `time`: items at or after it move later, spanning ones stretch.
    mutating func rippleTimedItems(insertingAt time: TimeInterval, width: TimeInterval) {
        retimeTimedItems(map: { $0 >= time ? $0 + width : $0 }, dropsKeyframe: { _ in false })
    }

    private mutating func retimeTimedItems(
        map: (TimeInterval) -> TimeInterval,
        dropsKeyframe: (TimeInterval) -> Bool
    ) {
        // Items that collapse to nothing (fully inside a removed range) are dropped.
        func retime<T>(_ items: [T], _ span: WritableKeyPath<T, (TimeInterval, TimeInterval)>) -> [T] {
            items.compactMap { item in
                let (s, e) = item[keyPath: span]
                let (ns, ne) = (map(s), map(e))
                guard ne - ns > 0.001 else { return nil }
                var out = item
                out[keyPath: span] = (ns, ne)
                return out
            }
        }

        overlays = retime(overlays, \.span)
        subtitles = retime(subtitles, \.span)
        chapters = retime(chapters, \.span)
        mediaItems = retime(mediaItems, \.span)
        manualZoomKeyframes = manualZoomKeyframes?
            .filter { !dropsKeyframe($0.timestamp) }
            .map { var k = $0; k.timestamp = map(k.timestamp); return k }
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
