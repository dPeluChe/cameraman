//
//  MotionAdapter.swift
//  EngineKit
//
//  Page-side script that gives any page the `window.__hf` seek contract the renderer needs.
//

import Foundation

enum MotionAdapter {
    /// Keeps an explicit `window.__hf`. Otherwise drives GSAP timelines in `window.__timelines`
    /// (HyperFrames-compatible) and every CSS/WAAPI animation by pausing them and setting the time.
    static let script = """
    (() => {
      if (window.__hf && typeof window.__hf.seek === 'function') return;
      const timelines = () => Object.values(window.__timelines || {});
      const finiteEnd = (a) => {
        const t = a.effect && a.effect.getComputedTiming ? a.effect.getComputedTiming() : null;
        return t && isFinite(t.endTime) ? t.endTime / 1000 : 0;
      };
      window.__hf = {
        get duration() {
          const gsap = timelines().reduce((m, tl) => Math.max(m, tl.duration()), 0);
          const css = document.getAnimations().reduce((m, a) => Math.max(m, finiteEnd(a)), 0);
          return Math.max(gsap, css);
        },
        seek(t) {
          timelines().forEach((tl) => { tl.pause(); tl.totalTime(t, false); });
          document.getAnimations().forEach((a) => { a.pause(); a.currentTime = t * 1000; });
        }
      };
    })();
    """
}
