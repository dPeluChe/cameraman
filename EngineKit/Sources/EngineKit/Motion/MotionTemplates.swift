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

    /// The page for this template; nil with a reason when `content` lacks what the template needs.
    public func html(_ content: Content, duration: TimeInterval = MotionTemplate.defaultDuration) -> Result<String, MotionTemplateError> {
        let seconds = max(duration, 1.5)
        let accent = Self.safeColor(content.colorHex)
        switch self {
        case .lowerThird:
            guard !content.title.isEmpty else { return .failure(.missing("title")) }
            return .success(Self.lowerThird(content, accent: accent, duration: seconds))
        case .stat:
            guard let stat = Self.parseStat(content.value) else { return .failure(.missing("value (a number such as 42, 42% or $1.2M)")) }
            return .success(Self.stat(content, stat: stat, accent: accent, duration: seconds))
        case .barChart:
            guard !content.values.isEmpty, content.labels.count == content.values.count else {
                return .failure(.missing("labels and values with the same length"))
            }
            guard content.values.count <= 12, content.values.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
                return .failure(.missing("up to 12 non-negative values"))
            }
            return .success(Self.barChart(content, accent: accent, duration: seconds))
        case .title:
            guard !content.title.isEmpty else { return .failure(.missing("title")) }
            return .success(Self.titleCard(content, accent: accent, duration: seconds))
        }
    }

    // MARK: Pages

    private static func page(_ css: String, body: String, script: String = "") -> String {
        """
        <!doctype html><html><head><meta charset="utf-8"><style>
        html, body { margin: 0; width: 100%; height: 100%; overflow: hidden; background: transparent;
          font-family: -apple-system, "SF Pro Display", Helvetica, sans-serif; color: #fff; }
        \(css)
        </style></head><body>\(body)\(script.isEmpty ? "" : "<script>\(script)</script>")</body></html>
        """
    }

    /// In at 0, out at `duration - 0.5`, finishing exactly at `duration`.
    private static func inOut(_ name: String, in inTime: Double = 0.6, delay: Double = 0, duration: Double) -> String {
        "\(name)-in \(inTime)s cubic-bezier(.2,.8,.2,1) \(delay)s both, \(name)-out 0.5s ease-in \(duration - 0.5)s forwards"
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
        @keyframes fade { from { opacity: 0; } to { opacity: 1; } }
        """, body: """
        <div id="card"><div id="bar"></div><div id="text"><div id="title">\(escape(c.title))</div>\
        \(c.subtitle.isEmpty ? "" : "<div id=\"sub\">\(escape(c.subtitle))</div>")</div></div>
        """)
    }

    private static func titleCard(_ c: Content, accent: String, duration: Double) -> String {
        page("""
        #wrap { position: absolute; inset: 0; display: flex; flex-direction: column; align-items: center; justify-content: center;
          text-align: center; animation: \(inOut("pop", duration: duration)); }
        #title { font-size: 9vh; font-weight: 800; letter-spacing: -.02em; text-shadow: 0 .4vh 3vh rgba(0,0,0,.45); }
        #rule { width: 14vh; height: .9vh; border-radius: 1vh; background: \(accent); margin-top: 2.2vh; }
        #sub { font-size: 3.6vh; margin-top: 2vh; color: rgba(255,255,255,.85); text-shadow: 0 .3vh 2vh rgba(0,0,0,.45); }
        @keyframes pop-in { from { transform: scale(.92); opacity: 0; } to { transform: none; opacity: 1; } }
        @keyframes pop-out { to { transform: scale(1.04); opacity: 0; } }
        """, body: """
        <div id="wrap"><div id="title">\(escape(c.title))</div><div id="rule"></div>\
        \(c.subtitle.isEmpty ? "" : "<div id=\"sub\">\(escape(c.subtitle))</div>")</div>
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
        @keyframes fade { from { opacity: 0; } to { opacity: 1; } }
        @keyframes panel-in { from { transform: translateY(4vh); opacity: 0; } to { transform: none; opacity: 1; } }
        @keyframes panel-out { to { transform: translateY(4vh); opacity: 0; } }
        """, body: """
        <div id="panel">\(c.title.isEmpty ? "" : "<div id=\"title\">\(escape(c.title))</div>")<div id="chart">\(bars)</div></div>
        """)
    }

    private static func stat(_ c: Content, stat: Stat, accent: String, duration: Double) -> String {
        // Counts up through the seek contract: a CSS animation cannot animate text.
        page("""
        #wrap { position: absolute; inset: 0; display: flex; flex-direction: column; align-items: center; justify-content: center;
          text-align: center; animation: \(inOut("pop", duration: duration)); }
        #num { font-size: 22vh; font-weight: 800; letter-spacing: -.03em; color: \(accent); text-shadow: 0 .5vh 3vh rgba(0,0,0,.5);
          font-variant-numeric: tabular-nums; }
        #label { font-size: 4.4vh; font-weight: 600; margin-top: 1vh; text-shadow: 0 .3vh 2vh rgba(0,0,0,.5); }
        @keyframes pop-in { from { transform: scale(.9); opacity: 0; } to { transform: none; opacity: 1; } }
        @keyframes pop-out { to { transform: scale(1.03); opacity: 0; } }
        """, body: """
        <div id="wrap"><div id="num"></div>\(c.title.isEmpty ? "" : "<div id=\"label\">\(escape(c.title))</div>")</div>
        """, script: """
        const stat = { prefix: \(jsString(stat.prefix)), suffix: \(jsString(stat.suffix)), target: \(stat.target), decimals: \(stat.decimals) };
        const num = document.getElementById('num');
        const show = (t) => {
          const k = Math.min(1, t / 1.4), eased = 1 - Math.pow(1 - k, 3);
          num.textContent = stat.prefix + (stat.target * eased).toFixed(stat.decimals) + stat.suffix;
        };
        show(0);
        window.__hf = { duration: \(duration), seek(t) {
          show(t);
          document.getAnimations().forEach((a) => { a.pause(); a.currentTime = t * 1000; });
        } };
        """)
    }

    // MARK: Helpers

    struct Stat { let prefix: String; let suffix: String; let target: Double; let decimals: Int }

    /// "$1.2M" -> prefix "$", 1.2, suffix "M".
    static func parseStat(_ raw: String) -> Stat? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard let match = text.range(of: #"-?\d[\d,]*(\.\d+)?"#, options: .regularExpression) else { return nil }
        let number = String(text[match]).replacingOccurrences(of: ",", with: "")
        guard let value = Double(number), value.isFinite, abs(value) < 1e15 else { return nil }
        let decimals = number.split(separator: ".").dropFirst().first.map(\.count) ?? 0
        return Stat(prefix: String(text[..<match.lowerBound]), suffix: String(text[match.upperBound...]), target: value, decimals: min(decimals, 4))
    }

    static func safeColor(_ hex: String) -> String {
        hex.range(of: #"^#[0-9A-Fa-f]{6}$"#, options: .regularExpression) != nil ? hex : "#0A84FF"
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
        return literal.replacingOccurrences(of: "</", with: "<\\/")
    }

    private static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

public enum MotionTemplateError: LocalizedError, Equatable {
    case missing(String)

    public var errorDescription: String? {
        switch self {
        case .missing(let what): return "This template needs \(what)."
        }
    }
}
