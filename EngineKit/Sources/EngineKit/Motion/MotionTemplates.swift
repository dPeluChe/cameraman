//
//  MotionTemplates.swift
//  EngineKit
//
//  Ready-made motion graphics as HTML for MotionRenderer. Sizes use vw/vh so a template fits any
//  canvas. Every page ends exactly at `duration`: it animates in, holds and animates out.
//

import Foundation

public enum MotionTemplate: String, CaseIterable, Sendable {
    case lowerThird = "lower_third"
    case stat
    case barChart = "bar_chart"
    case title

    public struct Content: Sendable {
        public var title: String
        public var subtitle: String
        /// `stat`: the number to count up to, with optional prefix/suffix ("$1.2M", "42%").
        public var value: String
        public var labels: [String]
        public var values: [Double]
        public var colorHex: String

        public init(title: String = "", subtitle: String = "", value: String = "", labels: [String] = [],
                    values: [Double] = [], colorHex: String = "#0A84FF") {
            self.title = title
            self.subtitle = subtitle
            self.value = value
            self.labels = labels
            self.values = values
            self.colorHex = colorHex
        }
    }

    public static let defaultDuration: TimeInterval = 4
    /// Shorter than this there is no room to animate in and out.
    public static let minimumDuration: TimeInterval = 1.5

    /// The page for this template. Throws when `content` lacks what the template needs.
    public func html(_ content: Content, duration: TimeInterval = MotionTemplate.defaultDuration) throws -> String {
        let seconds = max(duration, Self.minimumDuration)
        let accent = Self.safeColor(content.colorHex)
        switch self {
        case .lowerThird:
            try Self.require(!content.title.isEmpty, "a title")
            return Self.lowerThird(content, accent: accent, duration: seconds)
        case .title:
            try Self.require(!content.title.isEmpty, "a title")
            return Self.titleCard(content, accent: accent, duration: seconds)
        case .stat:
            guard let stat = Self.parseStat(content.value) else {
                throw MotionError.invalidOptions("the stat template needs a value with a number, such as 42, 42% or $1.2M")
            }
            return Self.stat(content, stat: stat, accent: accent, duration: seconds)
        case .barChart:
            try Self.require(!content.values.isEmpty && content.labels.count == content.values.count,
                             "labels and values with the same length")
            try Self.require(content.values.count <= 12 && content.values.allSatisfy { $0.isFinite && $0 >= 0 && $0 < 1e15 },
                             "up to 12 non-negative values under 1e15")
            return Self.barChart(content, accent: accent, duration: seconds)
        }
    }

    private static func require(_ condition: Bool, _ what: String) throws {
        if !condition { throw MotionError.invalidOptions("this template needs \(what)") }
    }

    // MARK: Pages

    /// `.center` and the `fade`/`pop` keyframes are shared; each template adds its own layout.
    private static func page(_ css: String, body: String, script: String = "") -> String {
        """
        <!doctype html><html><head><meta charset="utf-8"><style>
        html, body { margin: 0; width: 100%; height: 100%; overflow: hidden; background: transparent;
          font-family: -apple-system, "SF Pro Display", Helvetica, sans-serif; color: #fff; }
        .center { position: absolute; inset: 0; display: flex; flex-direction: column; align-items: center;
          justify-content: center; text-align: center; }
        @keyframes fade { from { opacity: 0; } to { opacity: 1; } }
        @keyframes pop-in { from { transform: scale(.92); opacity: 0; } to { transform: none; opacity: 1; } }
        @keyframes pop-out { to { transform: scale(1.04); opacity: 0; } }
        \(css)
        </style></head><body>\(body)\(script.isEmpty ? "" : "<script>\(script)</script>")</body></html>
        """
    }

    /// In over 0.6 s, out over the last 0.5 s, so the page ends exactly at `duration`.
    private static func inOut(_ name: String, duration: Double) -> String {
        "\(name)-in 0.6s cubic-bezier(.2,.8,.2,1) both, \(name)-out 0.5s ease-in \(duration - 0.5)s forwards"
    }

    /// `<div id="...">text</div>`, or nothing when there is no text.
    private static func line(_ id: String, _ text: String) -> String {
        text.isEmpty ? "" : "<div id=\"\(id)\">\(escape(text))</div>"
    }

    private static func lowerThird(_ c: Content, accent: String, duration: Double) -> String {
        page("""
        #card { position: absolute; left: 5vw; bottom: 11vh; display: flex; align-items: stretch; gap: 1.4vh;
          animation: \(inOut("slide", duration: duration)); }
        #bar { width: 0.8vh; background: \(accent); border-radius: 1vh; }
        #text { background: rgba(12,12,16,.82); padding: 1.8vh 3vh; border-radius: 1.2vh; }
        #title { font-size: 4.2vh; font-weight: 700; letter-spacing: -.01em; }
        #sub { font-size: 2.6vh; color: rgba(255,255,255,.72); margin-top: .4vh; animation: fade .6s ease-out .25s both; }
        @keyframes slide-in { from { transform: translateX(-8vw); opacity: 0; } to { transform: none; opacity: 1; } }
        @keyframes slide-out { to { transform: translateX(-8vw); opacity: 0; } }
        """, body: """
        <div id="card"><div id="bar"></div><div id="text">\(line("title", c.title))\(line("sub", c.subtitle))</div></div>
        """)
    }

    private static func titleCard(_ c: Content, accent: String, duration: Double) -> String {
        page("""
        .center { animation: \(inOut("pop", duration: duration)); }
        #title { font-size: 9vh; font-weight: 800; letter-spacing: -.02em; text-shadow: 0 .4vh 3vh rgba(0,0,0,.45); }
        #rule { width: 14vh; height: .9vh; border-radius: 1vh; background: \(accent); margin-top: 2.2vh; }
        #sub { font-size: 3.6vh; margin-top: 2vh; color: rgba(255,255,255,.85); text-shadow: 0 .3vh 2vh rgba(0,0,0,.45); }
        """, body: """
        <div class="center">\(line("title", c.title))<div id="rule"></div>\(line("sub", c.subtitle))</div>
        """)
    }

    private static func barChart(_ c: Content, accent: String, duration: Double) -> String {
        let peak = max(c.values.max() ?? 1, 0.000_001)
        let bars = c.values.indices.map { i -> String in
            let percent = (c.values[i] / peak * 100).rounded()
            return """
            <div class="col" style="--d:\(0.15 * Double(i))s"><div class="num">\(escape(format(c.values[i])))</div>\
            <div class="bar" style="height:\(percent)%"></div><div class="lab">\(escape(c.labels[i]))</div></div>
            """
        }.joined()
        return page("""
        #panel { position: absolute; left: 8vw; right: 8vw; top: 12vh; bottom: 12vh; padding: 3vh 4vh; border-radius: 2vh;
          background: rgba(12,12,16,.84); display: flex; flex-direction: column; animation: \(inOut("panel", duration: duration)); }
        #title { font-size: 4.4vh; font-weight: 700; margin-bottom: 2.5vh; }
        #chart { flex: 1; display: flex; align-items: flex-end; gap: 2vw; min-height: 0; }
        .col { flex: 1; height: 100%; display: flex; flex-direction: column; justify-content: flex-end; align-items: center; min-width: 0; }
        .bar { width: 100%; background: \(accent); border-radius: 1vh 1vh 0 0; transform-origin: bottom;
          animation: grow .9s cubic-bezier(.2,.8,.2,1) var(--d) both; }
        .num { font-size: 3vh; font-weight: 700; margin-bottom: .8vh; animation: fade .5s ease-out calc(var(--d) + .5s) both; }
        .lab { font-size: 2.6vh; color: rgba(255,255,255,.75); margin-top: 1vh; max-width: 100%; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        @keyframes grow { from { transform: scaleY(0); } to { transform: scaleY(1); } }
        @keyframes panel-in { from { transform: translateY(4vh); opacity: 0; } to { transform: none; opacity: 1; } }
        @keyframes panel-out { to { transform: translateY(4vh); opacity: 0; } }
        """, body: """
        <div id="panel">\(line("title", c.title))<div id="chart">\(bars)</div></div>
        """)
    }

    private static func stat(_ c: Content, stat: Stat, accent: String, duration: Double) -> String {
        // Counts up through the seek contract: a CSS animation cannot animate text.
        page("""
        .center { animation: \(inOut("pop", duration: duration)); }
        #num { font-size: 22vh; font-weight: 800; letter-spacing: -.03em; color: \(accent); text-shadow: 0 .5vh 3vh rgba(0,0,0,.5);
          font-variant-numeric: tabular-nums; }
        #label { font-size: 4.4vh; font-weight: 600; margin-top: 1vh; text-shadow: 0 .3vh 2vh rgba(0,0,0,.5); }
        """, body: """
        <div class="center"><div id="num"></div>\(line("label", c.title))</div>
        """, script: """
        const stat = { prefix: \(jsString(stat.prefix)), suffix: \(jsString(stat.suffix)), target: \(stat.target), decimals: \(stat.decimals), grouped: \(stat.grouped) };
        const num = document.getElementById('num');
        const digits = new Intl.NumberFormat('en-US', { minimumFractionDigits: stat.decimals, maximumFractionDigits: stat.decimals, useGrouping: stat.grouped });
        const show = (t) => {
          const k = Math.min(1, t / 1.4), eased = 1 - Math.pow(1 - k, 3);
          num.textContent = stat.prefix + digits.format(stat.target * eased) + stat.suffix;
        };
        show(0);
        window.__hf = { duration: \(duration), seek(t) {
          show(t);
          document.getAnimations().forEach((a) => { a.pause(); a.currentTime = t * 1000; });
        } };
        """)
    }

    // MARK: Helpers

    struct Stat { let prefix: String; let suffix: String; let target: Double; let decimals: Int; let grouped: Bool }

    /// "$1.2M" -> prefix "$", 1.2, suffix "M". Commas count only as thousands: "1,5M" is 1 + ",5M".
    static func parseStat(_ raw: String) -> Stat? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard let match = text.range(of: #"-?(\d{1,3}(,\d{3})+|\d+)(\.\d+)?"#, options: .regularExpression) else { return nil }
        let matched = String(text[match])
        let number = matched.replacingOccurrences(of: ",", with: "")
        guard let value = Double(number), value.isFinite, abs(value) < 1e15 else { return nil }
        let decimals = number.split(separator: ".").dropFirst().first.map(\.count) ?? 0
        return Stat(prefix: String(text[..<match.lowerBound]), suffix: String(text[match.upperBound...]), target: value,
                    decimals: min(decimals, 4), grouped: matched.contains(","))
    }

    /// Goes straight into CSS, so anything that is not a #RRGGBB(AA) value falls back to the default.
    static func safeColor(_ hex: String) -> String {
        hex.hasPrefix("#") && CanvasLayout.parseHexColor(hex) != nil ? hex : "#0A84FF"
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// A JS string literal that cannot end the script block or the string.
    static func jsString(_ text: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [text])) ?? Data("[\"\"]".utf8)
        let array = String(decoding: data, as: UTF8.self)
        let literal = String(array.dropFirst().dropLast())
        return literal.replacingOccurrences(of: "<", with: "\\u003c")
    }

    private static func format(_ value: Double) -> String {
        String(format: value == value.rounded() ? "%.0f" : "%.1f", value)
    }
}
