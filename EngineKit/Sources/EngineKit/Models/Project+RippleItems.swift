import Foundation

extension Project {
    /// Closes the deleted range [start, end) for everything timed on the project timeline but not
    /// stored as a clip, so overlays, captions, chapters, zoom keyframes and imported media stay
    /// aligned with the footage after a ripple delete.
    mutating func rippleTimedItems(removing start: TimeInterval, to end: TimeInterval) {
        let width = end - start
        func map(_ t: TimeInterval) -> TimeInterval {
            t <= start ? t : (t >= end ? t - width : start)
        }
        func remap(_ s: TimeInterval, _ e: TimeInterval) -> (TimeInterval, TimeInterval)? {
            let (ns, ne) = (map(s), map(e))
            return ne - ns > 0.001 ? (ns, ne) : nil
        }

        overlays = overlays.compactMap { var o = $0; guard let r = remap(o.start, o.end) else { return nil }; (o.start, o.end) = r; return o }
        subtitles = subtitles.compactMap { var o = $0; guard let r = remap(o.start, o.end) else { return nil }; (o.start, o.end) = r; return o }
        chapters = chapters.compactMap { var c = $0; guard let r = remap(c.startTime, c.endTime) else { return nil }; (c.startTime, c.endTime) = r; return c }
        mediaItems = mediaItems.compactMap {
            var m = $0
            guard let r = remap(m.timelineIn, m.timelineOut) else { return nil }
            (m.timelineIn, m.duration) = (r.0, r.1 - r.0)
            return m
        }
        manualZoomKeyframes = manualZoomKeyframes?.compactMap {
            var k = $0
            if k.timestamp > start && k.timestamp < end { return nil }
            k.timestamp = map(k.timestamp)
            return k
        }
        updatedAt = Date()
    }
}
