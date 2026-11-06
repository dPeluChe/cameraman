//
//  HeadlessPage.swift
//  EngineKit
//
//  An off-screen web page driven step by step, each step with a deadline. Shared by the renderers
//  that build media from code (MotionRenderer, MusicRenderer).
//

import WebKit

@MainActor
final class HeadlessPage {
    let webView: WKWebView
    private let stepTimeout: TimeInterval
    private let loader = PageLoader()
    private let failure: @Sendable (String) -> Error

    init(size: CGSize, stepTimeout: TimeInterval, failure: @escaping @Sendable (String) -> Error) {
        self.stepTimeout = stepTimeout
        self.failure = failure
        let configuration = WKWebViewConfiguration()
        // Pages must not see what an earlier render left in cookies or storage.
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: configuration)
        webView.navigationDelegate = loader
    }

    func close() { webView.stopLoading() }

    // Callback APIs on purpose: WebKit's async wrappers ignore cancellation and keep the view alive
    // while they wait, so a stuck page could not time out and its web process would outlive the render.

    func within<Value: Sendable>(
        step: String, timeout: TimeInterval? = nil, _ start: (@escaping @MainActor (Result<Value, Error>) -> Void) -> Void
    ) async throws -> Value {
        try await Deadline<Value>().run(seconds: timeout ?? stepTimeout, step: step, failure: failure, start: start)
    }

    func load(_ html: String) async throws {
        let failure = self.failure
        try await within(step: "loading the page") { done in
            loader.onFinish = { error in
                done(error.map { .failure(failure($0.localizedDescription)) } ?? .success(()))
            }
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    /// The trailing return is required: WebKit's Swift overlay traps on an empty result.
    func run(_ script: String, arguments: [String: Any] = [:], step: String,
             timeout: TimeInterval? = nil) async throws -> Double {
        try await within(step: step, timeout: timeout) { done in
            webView.callAsyncJavaScript(script + "\nreturn 0;", arguments: arguments, in: nil, in: .page) { result in
                done(result.map { ($0 as? NSNumber)?.doubleValue ?? 0 }.mapError(self.scriptError))
            }
        }
    }

    /// A script that ends in `return <string>`.
    func text(_ script: String, arguments: [String: Any] = [:], step: String) async throws -> String {
        try await within(step: step) { done in
            webView.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page) { result in
                done(result.map { $0 as? String ?? "" }.mapError(self.scriptError))
            }
        }
    }

    /// WebKit keeps the script's own message apart from its generic "A JavaScript exception occurred".
    private func scriptError(_ error: Error) -> Error {
        failure((error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription)
    }
}

/// Bridges one WebKit callback to async, giving up after `seconds` or when the task is cancelled.
@MainActor
private final class Deadline<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Error>?
    private var timer: Task<Void, Error>?

    func run(seconds: TimeInterval, step: String, failure: @escaping @Sendable (String) -> Error,
             start: (@escaping @MainActor (Result<Value, Error>) -> Void) -> Void) async throws -> Value {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                timer = Task { [weak self] in
                    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    self?.settle(.failure(failure("timed out after \(seconds)s \(step)")))
                }
                start { [self] in settle($0) }
            }
        } onCancel: {
            Task { @MainActor in self.settle(.failure(CancellationError())) }
        }
    }

    private func settle(_ result: Result<Value, Error>) {
        timer?.cancel()
        continuation?.resume(with: result)
        continuation = nil
    }
}

@MainActor
private final class PageLoader: NSObject, WKNavigationDelegate {
    var onFinish: ((Error?) -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { onFinish?(nil) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { onFinish?(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { onFinish?(error) }
}
