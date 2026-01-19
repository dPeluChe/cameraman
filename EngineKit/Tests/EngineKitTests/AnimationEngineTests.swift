//
//  AnimationEngineTests.swift
//  EngineKitTests
//
//  Created by Ralphy on 2026-01-19.
//

import XCTest
@testable import EngineKit

final class AnimationEngineTests: XCTestCase {

    var animationEngine: AnimationEngine!

    override func setUp() {
        super.setUp()
        animationEngine = AnimationEngine()
    }

    override func tearDown() {
        animationEngine = nil
        super.tearDown()
    }

    // MARK: - Test Helpers

    func createTestOverlay(
        type: Project.Overlay.OverlayType = .arrow,
        start: TimeInterval = 0.0,
        end: TimeInterval = 10.0,
        animation: Project.Overlay.Animation? = nil
    ) -> Project.Overlay {
        let transform = Project.Overlay.Transform(x: 100, y: 100, scale: 1.0, rotation: 0.0)
        let style = Project.Overlay.Style(stroke: "#FFFFFF", strokeWidth: 4.0, shadow: false)

        return Project.Overlay(
            id: UUID(),
            type: type,
            start: start,
            end: end,
            transform: transform,
            style: style,
            animation: animation
        )
    }

    // MARK: - No Animation Tests

    func testOverlayWithoutAnimation_IsFullyVisible() async throws {
        let overlay = createTestOverlay(animation: nil)

        // Test at various times within the overlay range
        let times: [TimeInterval] = [0.0, 2.5, 5.0, 7.5, 10.0]
        for time in times {
            let (progress, opacity) = await animationEngine.calculateAnimationProgress(overlay: overlay, at: time)
            XCTAssertEqual(progress, 1.0, "At time \(time)s, progress should be 1.0")
            XCTAssertEqual(opacity, 1.0, "At time \(time)s, opacity should be 1.0")
        }
    }

    func testOverlayWithoutAnimation_IsVisibleOutsideRange() async throws {
        let overlay = createTestOverlay(start: 2.0, end: 8.0, animation: nil)

        // Before overlay
        let (progressBefore, opacityBefore) = await animationEngine.calculateAnimationProgress(overlay: overlay, at: 1.0)
        XCTAssertEqual(progressBefore, 0.0, "Before overlay, progress should be 0.0")
        XCTAssertEqual(opacityBefore, 0.0, "Before overlay, opacity should be 0.0")

        // After overlay
        let (progressAfter, opacityAfter) = await animationEngine.calculateAnimationProgress(overlay: overlay, at: 9.0)
        XCTAssertEqual(progressAfter, 0.0, "After overlay, progress should be 0.0")
        XCTAssertEqual(opacityAfter, 0.0, "After overlay, opacity should be 0.0")
    }

    // MARK: - Fade In Tests

    func testFadeInAnimation_StartsInvisible() async throws {
        let animation = Project.Overlay.Animation(
            type: .fadeIn,
            fadeInDuration: 1.0,
            fadeOutDuration: 0.0
        )
        let overlay = createTestOverlay(start: 0.0, end: 10.0, animation: animation)

        let (progress, opacity) = await animationEngine.calculateAnimationProgress(overlay: overlay, at: 0.0)
        XCTAssertEqual(progress, 0.0, accuracy: 0.01, "At start, progress should be 0.0")
        XCTAssertEqual(opacity, 0.0, accuracy: 0.01, "At start, opacity should be 0.0")
    }

    func testFadeInAnimation_FadesInLinearly() async throws {
        let animation = Project.Overlay.Animation(
            type: .fadeIn,
            fadeInDuration: 2.0,
            fadeOutDuration: 0.0,
            easing: .linear
        )
        let overlay = createTestOverlay(start: 0.0, end: 10.0, animation: animation)

        // At 50% of fade-in duration
        let (progress1, opacity1) = await animationEngine.calculateAnimationProgress(overlay: overlay, at: 1.0)
        XCTAssertEqual(progress1, 0.5, accuracy: 0.01, "At 50% of fade-in, progress should be 0.5")
        XCTAssertEqual(opacity1, 0.5, accuracy: 0.01, "At 50% of fade-in, opacity should be 0.5")

        // At end of fade-in duration
        let (progress2, opacity2) = await animationEngine.calculateAnimationProgress(overlay: overlay, at: 2.0)
        XCTAssertEqual(progress2, 1.0, accuracy: 0.01, "At end of fade-in, progress should be 1.0")
        XCTAssertEqual(opacity2, 1.0, accuracy: 0.01, "At end of fade-in, opacity should be 1.0")
    }

    func testFadeInAnimation_RemainsVisibleAfterFadeIn() async throws {
        let animation = Project.Overlay.Animation(
            type: .fadeIn,
            fadeInDuration: 1.0,
            fadeOutDuration: 0.0
        )
        let overlay = createTestOverlay(start: 0.0, end: 10.0, animation: animation)

        // Well after fade-in completes
        let (progress, opacity) = await animationEngine.calculateAnimationProgress(overlay: overlay, at: 5.0)
        XCTAssertEqual(progress, 1.0, "After fade-in, progress should be 1.0")
        XCTAssertEqual(opacity, 1.0, "After fade-in, opacity should be 1.0")
    }

    func testFadeInAnimation_WithEaseOutEasing() async throws {
        let animation = Project.Overlay.Animation(
            type: .fadeIn,
            fadeInDuration: 1.0,
            fadeOutDuration: 0.0,
            easing: .easeOut
        )
        let overlay = createTestOverlay(start: 0.0, end: 10.0, animation: animation)

        // At 50% of fade-in duration with ease-out, should be > 0.5 due to easing curve
        let (progress, opacity) = await animationEngine.calculateAnimationProgress(overlay: overlay, at: 0.5)
        XCTAssertGreaterThan(progress, 0.5, "With ease-out, progress at 50% should be > 0.5")
        XCTAssertGreaterThan(opacity, 0.5, "With ease-out, opacity at 50% should be > 0.5")
    }

    // MARK: - Fade Out Tests

    func testFadeOutAnimation_StartsVisible() async throws {
        let animation = Project.Overlay.Animation(
            type: .fadeOut,
            fadeInDuration: 0.0,
            fadeOutDuration: 1.0
        )
        let overlay = createTestOverlay(start: 0.0, end: 10.0, animation: animation)

        // At beginning, should be fully visible
        let (progress, opacity) = await animationEngine.calculateAnimationProgress(overlay: overlay, at: 0.0)
        XCTAssertEqual(progress, 1.0, "At start, progress should be 1.0")
        XCTAssertEqual(opacity, 1.0, "At start, opacity should be 1.0")
    }

    func testFadeOutAnimation_FadesOutAtEnd() async throws {
        let animation = Project.Overlay.Animation(
            type: .fadeOut,
            fadeInDuration: 0.0,
            fadeOutDuration: 2.0,
            easing: .linear
        )
        let overlay = createTestOverlay(start: 0.0, end: 10.0, animation: animation)

        // At start of fade-out (8.0s)
        let (progress1, opacity1) = await animationEngine.calculateAnimationProgress(overlay: overlay, at: 8.0)
        XCTAssertEqual(progress1, 1.0, accuracy: 0.01, "At fade-out start, progress should be 1.0")
        XCTAssertEqual(opacity1, 1.0, accuracy: 0.01, "At fade-out start, opacity should be 1.0")

        // At 50% of fade-out
        let (progress2, opacity2) = await animationEngine.calculateAnimationProgress(overlay: overlay, at: 9.0)
        XCTAssertEqual(progress2, 0.5, accuracy: 0.01, "At 50% of fade-out, progress should be 0.5")
        XCTAssertEqual(opacity2, 0.5, accuracy: 0.01, "At 50% of fade-out, opacity should be 0.5")

        // At end of fade-out
        let (progress3, opacity3) = await animationEngine.calculateAnimationProgress(overlay: overlay, at: 10.0)
        XCTAssertEqual(progress3, 0.0, accuracy: 0.01, "At end of fade-out, progress should be 0.0")
        XCTAssertEqual(opacity3, 0.0, accuracy: 0.01, "At end of fade-out, opacity should be 0.0")
    }

    // MARK: - Fade In/Out Tests

    func testFadeInOutAnimation_FadesInAndOut() async throws {
        let animation = Project.Overlay.Animation(
            type: .fadeInOut,
            fadeInDuration: 1.0,
            fadeOutDuration: 1.0,
            easing: .linear
        )
        let overlay = createTestOverlay(start: 0.0, end: 10.0, animation: animation)

        // At start
        let (progress0, opacity0) = await animationEngine.calculateAnimationProgress(overlay: overlay, at: 0.0)
        XCTAssertEqual(opacity0, 0.0, accuracy: 0.01, "At start, opacity should be 0.0")

        // During fade-in
        let (progress1, opacity1) = await animationEngine.calculateAnimationProgress(overlay: overlay, at: 0.5)
        XCTAssertEqual(opacity1, 0.5, accuracy: 0.01, "During fade-in, opacity should be 0.5")

        // After fade-in, before fade-out
        let (progress2, opacity2) = await animationEngine.calculateAnimationProgress(overlay: overlay, at: 5.0)
        XCTAssertEqual(opacity2, 1.0, accuracy: 0.01, "In middle, opacity should be 1.0")

        // During fade-out
        let (progress3, opacity3) = await animationEngine.calculateAnimationProgress(overlay: overlay, at: 9.5)
        XCTAssertEqual(opacity3, 0.5, accuracy: 0.01, "During fade-out, opacity should be 0.5")

        // At end
        let (progress4, opacity4) = await animationEngine.calculateAnimationProgress(overlay: overlay, at: 10.0)
        XCTAssertEqual(opacity4, 0.0, accuracy: 0.01, "At end, opacity should be 0.0")
    }

    func testFadeInOutAnimation_WithDurations() async throws {
        let animation = Project.Overlay.Animation(
            type: .fadeInOut,
            fadeInDuration: 2.0,
            fadeOutDuration: 3.0,
            easing: .linear
        )
        let overlay = createTestOverlay(start: 0.0, end: 10.0, animation: animation)

        // Fully visible period should be from 2.0s to 7.0s
        let (progress, opacity) = await animationEngine.calculateAnimationProgress(overlay: overlay, at: 5.0)
        XCTAssertEqual(opacity, 1.0, "In fully visible period, opacity should be 1.0")
    }

    // MARK: - Draw On Tests

    func testDrawOnAnimation_StartsNotDrawn() async throws {
        let animation = Project.Overlay.Animation.drawOn(duration: 1.0)
        let overlay = createTestOverlay(start: 0.0, end: 10.0, animation: animation)

        let drawProgress = await animationEngine.calculateDrawOnProgress(overlay: overlay, at: 0.0)
        XCTAssertEqual(drawProgress, 0.0, accuracy: 0.01, "At start, draw progress should be 0.0")
    }

    func testDrawOnAnimation_DrawsOverTime() async throws {
        let animation = Project.Overlay.Animation.drawOn(duration: 2.0)
        var mutableAnimation = animation
        mutableAnimation.easing = .linear
        let overlay = createTestOverlay(start: 0.0, end: 10.0, animation: mutableAnimation)

        // At 50% of draw-on duration
        let drawProgress1 = await animationEngine.calculateDrawOnProgress(overlay: overlay, at: 1.0)
        XCTAssertEqual(drawProgress1, 0.5, accuracy: 0.01, "At 50% of draw-on, progress should be 0.5")

        // At end of draw-on duration
        let drawProgress2 = await animationEngine.calculateDrawOnProgress(overlay: overlay, at: 2.0)
        XCTAssertEqual(drawProgress2, 1.0, accuracy: 0.01, "At end of draw-on, progress should be 1.0")
    }

    func testDrawOnAnimation_RemainsFullyDrawn() async throws {
        let animation = Project.Overlay.Animation.drawOn(duration: 1.0)
        let overlay = createTestOverlay(start: 0.0, end: 10.0, animation: animation)

        // Well after draw-on completes
        let drawProgress = await animationEngine.calculateDrawOnProgress(overlay: overlay, at: 5.0)
        XCTAssertEqual(drawProgress, 1.0, "After draw-on, progress should be 1.0")
    }

    func testDrawOnAnimation_WithEaseInEasing() async throws {
        let animation = Project.Overlay.Animation.drawOn(duration: 1.0)
        var mutableAnimation = animation
        mutableAnimation.easing = .easeIn
        let overlay = createTestOverlay(start: 0.0, end: 10.0, animation: mutableAnimation)

        // At 50% of draw-on duration with ease-in, should be < 0.5 due to easing curve
        let drawProgress = await animationEngine.calculateDrawOnProgress(overlay: overlay, at: 0.5)
        XCTAssertLessThan(drawProgress, 0.5, "With ease-in, progress at 50% should be < 0.5")
    }

    // MARK: - Visibility Tests

    func testIsVisible_WithoutAnimation() async throws {
        let overlay = createTestOverlay(start: 2.0, end: 8.0, animation: nil)

        let visibleBefore = await animationEngine.isVisible(overlay: overlay, at: 1.0)
        XCTAssertFalse(visibleBefore, "Should not be visible before start time")

        let visibleDuring = await animationEngine.isVisible(overlay: overlay, at: 5.0)
        XCTAssertTrue(visibleDuring, "Should be visible during overlay")

        let visibleAfter = await animationEngine.isVisible(overlay: overlay, at: 9.0)
        XCTAssertFalse(visibleAfter, "Should not be visible after end time")
    }

    func testIsVisible_WithFadeIn() async throws {
        let animation = Project.Overlay.Animation(
            type: .fadeIn,
            fadeInDuration: 1.0,
            fadeOutDuration: 0.0
        )
        let overlay = createTestOverlay(start: 0.0, end: 10.0, animation: animation)

        // At very start, opacity is 0, so should not be visible
        let visibleAtStart = await animationEngine.isVisible(overlay: overlay, at: 0.0)
        XCTAssertFalse(visibleAtStart, "Should not be visible at start with fade-in")

        // After fade-in, should be visible
        let visibleAfter = await animationEngine.isVisible(overlay: overlay, at: 2.0)
        XCTAssertTrue(visibleAfter, "Should be visible after fade-in")
    }

    func testIsVisible_WithFadeOut() async throws {
        let animation = Project.Overlay.Animation(
            type: .fadeOut,
            fadeInDuration: 0.0,
            fadeOutDuration: 1.0
        )
        let overlay = createTestOverlay(start: 0.0, end: 10.0, animation: animation)

        // At beginning, should be visible
        let visibleAtStart = await animationEngine.isVisible(overlay: overlay, at: 0.0)
        XCTAssertTrue(visibleAtStart, "Should be visible at start with fade-out")

        // At very end, opacity is 0, so should not be visible
        let visibleAtEnd = await animationEngine.isVisible(overlay: overlay, at: 10.0)
        XCTAssertFalse(visibleAtEnd, "Should not be visible at end with fade-out")
    }

    // MARK: - Render State Tests

    func testGetRenderState_NoAnimation() async throws {
        let overlay = createTestOverlay(animation: nil)
        let renderState = await animationEngine.getRenderState(overlay: overlay, at: 5.0)

        XCTAssertTrue(renderState.isVisible, "Should be visible")
        XCTAssertEqual(renderState.opacity, 1.0, accuracy: 0.01, "Opacity should be 1.0")
        XCTAssertEqual(renderState.drawProgress, 1.0, "Draw progress should be 1.0")
    }

    func testGetRenderState_FadeInOut() async throws {
        let animation = Project.Overlay.Animation.fadeInOut
        let overlay = createTestOverlay(start: 0.0, end: 10.0, animation: animation)

        // During fade-in
        let state1 = await animationEngine.getRenderState(overlay: overlay, at: 0.15)
        XCTAssertTrue(state1.isVisible, "Should be visible during fade-in")
        XCTAssertGreaterThan(state1.opacity, 0.0, "Opacity should be > 0")
        XCTAssertLessThan(state1.opacity, 1.0, "Opacity should be < 1.0")
        XCTAssertEqual(state1.drawProgress, 1.0, "Draw progress should be 1.0 for fade animation")

        // Fully visible
        let state2 = await animationEngine.getRenderState(overlay: overlay, at: 5.0)
        XCTAssertTrue(state2.isVisible, "Should be visible")
        XCTAssertEqual(state2.opacity, 1.0, accuracy: 0.01, "Opacity should be 1.0")

        // During fade-out
        let state3 = await animationEngine.getRenderState(overlay: overlay, at: 9.85)
        XCTAssertTrue(state3.isVisible, "Should be visible during fade-out")
        XCTAssertGreaterThan(state3.opacity, 0.0, "Opacity should be > 0")
        XCTAssertLessThan(state3.opacity, 1.0, "Opacity should be < 1.0")
    }

    func testGetRenderState_DrawOn() async throws {
        let animation = Project.Overlay.Animation.drawOn(duration: 2.0)
        var mutableAnimation = animation
        mutableAnimation.easing = .linear
        let overlay = createTestOverlay(start: 0.0, end: 10.0, animation: mutableAnimation)

        // During draw-on
        let state = await animationEngine.getRenderState(overlay: overlay, at: 1.0)
        XCTAssertTrue(state.isVisible, "Should be visible during draw-on")
        XCTAssertEqual(state.opacity, 1.0, "Opacity should be 1.0 for draw-on")
        XCTAssertEqual(state.drawProgress, 0.5, accuracy: 0.01, "Draw progress should be 0.5")
    }

    // MARK: - Easing Function Tests

    func testLinearEasing() async throws {
        let animation = Project.Overlay.Animation(
            type: .fadeIn,
            fadeInDuration: 1.0,
            fadeOutDuration: 0.0,
            easing: .linear
        )
        let overlay = createTestOverlay(animation: animation)

        let (progress, _) = await animationEngine.calculateAnimationProgress(overlay: overlay, at: 0.5)
        XCTAssertEqual(progress, 0.5, accuracy: 0.01, "Linear easing should be proportional")
    }

    func testEaseInEasing() async throws {
        let animation = Project.Overlay.Animation(
            type: .fadeIn,
            fadeInDuration: 1.0,
            fadeOutDuration: 0.0,
            easing: .easeIn
        )
        let overlay = createTestOverlay(animation: animation)

        let (progress, _) = await animationEngine.calculateAnimationProgress(overlay: overlay, at: 0.5)
        // easeIn is t^2, so at t=0.5, result should be 0.25
        XCTAssertEqual(progress, 0.25, accuracy: 0.01, "Ease-in should start slow")
    }

    func testEaseOutEasing() async throws {
        let animation = Project.Overlay.Animation(
            type: .fadeIn,
            fadeInDuration: 1.0,
            fadeOutDuration: 0.0,
            easing: .easeOut
        )
        let overlay = createTestOverlay(animation: animation)

        let (progress, _) = await animationEngine.calculateAnimationProgress(overlay: overlay, at: 0.5)
        // easeOut is t*(2-t), so at t=0.5, result should be 0.75
        XCTAssertEqual(progress, 0.75, accuracy: 0.01, "Ease-out should start fast")
    }

    func testEaseInOutEasing() async throws {
        let animation = Project.Overlay.Animation(
            type: .fadeIn,
            fadeInDuration: 1.0,
            fadeOutDuration: 0.0,
            easing: .easeInOut
        )
        let overlay = createTestOverlay(animation: animation)

        let (progress1, _) = await animationEngine.calculateAnimationProgress(overlay: overlay, at: 0.25)
        // At t=0.25 with ease-in-out, should be in slow start phase

        let (progress2, _) = await animationEngine.calculateAnimationProgress(overlay: overlay, at: 0.75)
        // At t=0.75 with ease-in-out, should be in slow end phase

        XCTAssertLessThan(progress1, 0.5, "Ease-in-out should start slow")
        XCTAssertGreaterThan(progress2, 0.5, "Ease-in-out should end slow")
    }

    // MARK: - Edge Case Tests

    func testAnimationWithVeryShortDuration() async throws {
        let animation = Project.Overlay.Animation(
            type: .fadeIn,
            fadeInDuration: 0.01,
            fadeOutDuration: 0.0
        )
        let overlay = createTestOverlay(start: 0.0, end: 10.0, animation: animation)

        // Just after start
        let (progress, opacity) = await animationEngine.calculateAnimationProgress(overlay: overlay, at: 0.01)
        XCTAssertEqual(progress, 1.0, "Very short animation should complete quickly")
        XCTAssertEqual(opacity, 1.0, "Very short animation should complete quickly")
    }

    func testAnimationWithOverlayStartingAtNonZero() async throws {
        let animation = Project.Overlay.Animation.fadeIn
        let overlay = createTestOverlay(start: 5.0, end: 15.0, animation: animation)

        // Before overlay
        let (progressBefore, opacityBefore) = await animationEngine.calculateAnimationProgress(overlay: overlay, at: 4.0)
        XCTAssertEqual(progressBefore, 0.0, "Before overlay, progress should be 0.0")
        XCTAssertEqual(opacityBefore, 0.0, "Before overlay, opacity should be 0.0")

        // At start of overlay
        let (progressStart, opacityStart) = await animationEngine.calculateAnimationProgress(overlay: overlay, at: 5.0)
        XCTAssertEqual(progressStart, 0.0, accuracy: 0.01, "At start of overlay, progress should be 0.0")
        XCTAssertEqual(opacityStart, 0.0, accuracy: 0.01, "At start of overlay, opacity should be 0.0")
    }

    func testAnimationExactlyAtBoundary() async throws {
        let animation = Project.Overlay.Animation.fadeIn
        let overlay = createTestOverlay(start: 2.0, end: 8.0, animation: animation)

        // Exactly at start time
        let (progress1, _) = await animationEngine.calculateAnimationProgress(overlay: overlay, at: 2.0)
        XCTAssertEqual(progress1, 0.0, accuracy: 0.01, "At exact start, progress should be 0.0")

        // Exactly at end time
        let (progress2, _) = await animationEngine.calculateAnimationProgress(overlay: overlay, at: 8.0)
        // At end time with fade-in, should still be calculating (will be at end of overlay)
        XCTAssertGreaterThan(progress2, 0.0, "At exact end, should have some progress")
    }

    // MARK: - Performance Tests

    func testPerformance_CalculateAnimationProgress() async throws {
        let overlay = createTestOverlay(animation: .fadeIn)

        measure {
            for i in 0..<1000 {
                let time = Double(i) / 100.0
                _ = await animationEngine.calculateAnimationProgress(overlay: overlay, at: time)
            }
        }
    }

    func testPerformance_CalculateOpacity() async throws {
        let overlay = createTestOverlay(animation: .fadeInOut)

        measure {
            for i in 0..<1000 {
                let time = Double(i) / 100.0
                _ = await animationEngine.calculateOpacity(overlay: overlay, at: time)
            }
        }
    }

    func testPerformance_GetRenderState() async throws {
        let overlay = createTestOverlay(animation: .drawOn(duration: 1.0))

        measure {
            for i in 0..<1000 {
                let time = Double(i) / 100.0
                _ = await animationEngine.getRenderState(overlay: overlay, at: time)
            }
        }
    }
}
