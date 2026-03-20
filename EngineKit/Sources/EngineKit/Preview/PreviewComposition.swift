//
//  PreviewComposition.swift
//  EngineKit
//
//  Created by Ralphy on 2026-01-19.
//

import Foundation
import AVFoundation

extension PreviewEngine {
    /// Resolve sources for a specific take ID, falling back to primary sources
    func resolveSources(for takeId: UUID?) -> Project.Sources? {
        if let takeId = takeId, let take = project?.takes.first(where: { $0.id == takeId }) {
            return take.sources
        }
        return project?.primarySources
    }

    /// Create AVPlayer with composition that applies edits
    func createPlayerWithEdits() async throws {
        do {
            guard let project = project else {
                throw PreviewError.noProjectLoaded
            }

            // Use primary sources for initial validation, but we'll load per-segment sources later
            guard project.primarySources != nil else {
                throw PreviewError.playbackFailed("No sources found")
            }

            logger.debug("🎬 Creating player with edits - project: \(project.name), segments: \(project.timeline.segments.count)")

            // Create AVMutableComposition with segments
            let composition = AVMutableComposition()

            // Add composition track for screen
            let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )

            guard let videoTrack = compositionVideoTrack else {
                logger.error("❌ Failed to create composition video track")
                throw PreviewError.playbackFailed("Failed to create composition video track")
            }

            logger.debug("✅ Screen video track created successfully")

        var insertTime = CMTime.zero

        // Cache for loaded assets to avoid reloading the same file multiple times
        var assetCache: [String: AVAsset] = [:]

        // Apply segments (trims, cuts, speed changes)
        for (index, segment) in project.timeline.segments.enumerated() {
            // Resolve sources for this segment
            guard let sources = resolveSources(for: segment.takeId) else {
                logger.warning("⚠️ Could not resolve sources for segment \(index), skipping")
                // If we can't resolve sources, we skip this segment or insert black gap?
                // For now, skipping, but keeping time alignment might require inserting empty time.
                continue
            }

            let sourcePath = sources.screen.path

            // Use proxy if available and enabled
            let effectivePath: String
            if configuration.useProxy, let proxyPath = getProxyPath(for: "screen") {
                effectivePath = proxyPath
                logger.debug("📺 Segment \(index): using proxy for screen")
            } else {
                effectivePath = sourcePath
                logger.debug("📺 Segment \(index): screen path = \(sourcePath)")
            }

            // Load asset (cached)
            let asset: AVAsset
            if let cached = assetCache[effectivePath] {
                asset = cached
            } else {
                let assetURL: URL
                if effectivePath == sourcePath, let projectDir = projectDirectory {
                    assetURL = URL(fileURLWithPath: projectDir).appendingPathComponent(sourcePath)
                } else {
                    assetURL = URL(fileURLWithPath: effectivePath)
                }

                guard fileManager.fileExists(atPath: assetURL.path) else {
                    logger.error("Screen file not found: \(assetURL.path)")
                    continue
                }

                asset = AVAsset(url: assetURL)
                assetCache[effectivePath] = asset
            }

            // Load screen asset tracks
            let screenAssetTracks = try await asset.loadTracks(withMediaType: .video)
            guard let screenTrack = screenAssetTracks.first else {
                logger.warning("⚠️ No video track found in segment \(index), skipping")
                // Skip if no video track
                continue
            }

            let startTime = CMTime(seconds: segment.sourceIn, preferredTimescale: 600)
            let endTime = CMTime(seconds: segment.sourceOut, preferredTimescale: 600)
            let duration = CMTimeSubtract(endTime, startTime)

            logger.debug("📺 Inserting segment \(index): \(segment.sourceIn)s - \(segment.sourceOut)s, duration: \(duration.seconds)s")

            // Time range in source
            let timeRange = CMTimeRange(start: startTime, duration: duration)

            try videoTrack.insertTimeRange(
                timeRange,
                of: screenTrack,
                at: insertTime
            )

            // Apply speed change by scaling the inserted time range
            let segmentDuration: CMTime
            if segment.speed != 1.0 {
                let scaledDuration = CMTime(
                    seconds: (segment.sourceOut - segment.sourceIn) / segment.speed,
                    preferredTimescale: 600
                )
                let insertedRange = CMTimeRange(start: insertTime, duration: duration)
                videoTrack.scaleTimeRange(insertedRange, toDuration: scaledDuration)
                segmentDuration = scaledDuration
            } else {
                segmentDuration = duration
            }
            insertTime = CMTimeAdd(insertTime, segmentDuration)

            logger.debug("✅ Segment \(index) inserted, current time: \(insertTime.seconds)s")
        }

        logger.debug("✅ All screen segments inserted, total duration: \(insertTime.seconds)s")

        // Handle camera track if present (wrapped in do-catch for error handling)
        var cameraTrack: AVMutableCompositionTrack?
        do {
            if project.primarySources?.camera != nil {
                logger.debug("📷 Camera source found, attempting to create camera track")

                guard let camTrack = composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else {
                    logger.warning("⚠️ Failed to create camera track in composition")
                    throw PreviewError.playbackFailed("Failed to create camera track")
                }

                cameraTrack = camTrack
                insertTime = CMTime.zero
                logger.debug("✅ Camera track created successfully")

                for (index, segment) in project.timeline.segments.enumerated() {
                    do {
                        guard let sources = resolveSources(for: segment.takeId),
                              let cameraPath = sources.camera?.path else {
                            logger.debug("📷 No camera source for segment \(index), skipping")
                            // No camera for this segment, insert gap
                            let segmentDuration = CMTime(
                                seconds: (segment.sourceOut - segment.sourceIn) / segment.speed,
                                preferredTimescale: 600
                            )
                            insertTime = CMTimeAdd(insertTime, segmentDuration)
                            continue
                        }

                        // Use proxy if available and enabled
                        let effectiveCameraPath: String
                        if configuration.useProxy, let proxyPath = getProxyPath(for: "camera") {
                            effectiveCameraPath = proxyPath
                        } else {
                            effectiveCameraPath = cameraPath
                        }

                        let asset: AVAsset
                        if let cached = assetCache[effectiveCameraPath] {
                            asset = cached
                        } else {
                            let assetURL: URL
                            if effectiveCameraPath == cameraPath, let projectDir = projectDirectory {
                                assetURL = URL(fileURLWithPath: projectDir).appendingPathComponent(cameraPath)
                            } else {
                                assetURL = URL(fileURLWithPath: effectiveCameraPath)
                            }

                            guard fileManager.fileExists(atPath: assetURL.path) else {
                                logger.warning("Camera file not found: \(assetURL.path)")
                                // Insert gap and continue
                                let segmentDuration = CMTime(
                                    seconds: (segment.sourceOut - segment.sourceIn) / segment.speed,
                                    preferredTimescale: 600
                                )
                                insertTime = CMTimeAdd(insertTime, segmentDuration)
                                continue
                            }

                            logger.debug("📷 Loading camera asset for segment \(index)")
                            asset = AVAsset(url: assetURL)
                            assetCache[effectiveCameraPath] = asset
                        }

                        let cameraAssetTracks = try await asset.loadTracks(withMediaType: .video)
                        guard let sourceCameraTrack = cameraAssetTracks.first else {
                            logger.warning("📷 No camera video track found for segment \(segment.id)")
                            continue
                        }

                        let startTime = CMTime(seconds: segment.sourceIn, preferredTimescale: 600)
                        let endTime = CMTime(seconds: segment.sourceOut, preferredTimescale: 600)
                        let duration = CMTimeSubtract(endTime, startTime)

                        try camTrack.insertTimeRange(
                            CMTimeRange(start: startTime, duration: duration),
                            of: sourceCameraTrack,
                            at: insertTime
                        )

                        // Apply speed change to camera track
                        let segmentDuration: CMTime
                        if segment.speed != 1.0 {
                            let scaledDuration = CMTime(
                                seconds: (segment.sourceOut - segment.sourceIn) / segment.speed,
                                preferredTimescale: 600
                            )
                            let insertedRange = CMTimeRange(start: insertTime, duration: duration)
                            camTrack.scaleTimeRange(insertedRange, toDuration: scaledDuration)
                            segmentDuration = scaledDuration
                        } else {
                            segmentDuration = duration
                        }
                        insertTime = CMTimeAdd(insertTime, segmentDuration)

                        logger.debug("✅ Camera preview segment \(index + 1) added successfully")
                    } catch {
                        logger.error("❌ Error processing camera segment \(index): \(error.localizedDescription)")
                        // Insert gap and continue with next segment
                        let segmentDuration = CMTime(
                            seconds: (segment.sourceOut - segment.sourceIn) / segment.speed,
                            preferredTimescale: 600
                        )
                        insertTime = CMTimeAdd(insertTime, segmentDuration)
                        continue
                    }
                }

                logger.debug("✅ All camera segments processed successfully")
            }
        } catch {
            logger.error("❌ Error setting up camera track: \(error.localizedDescription)")
            cameraTrack = nil
            // Continue with screen-only preview
        }

        // Always create video composition to ensure screen is scaled correctly
        let videoComposition = AVMutableVideoComposition()

        // Use render size from canvas format
        let renderSize = CoreFoundation.CGSize(
            width: CGFloat(project.canvas.format.w),
            height: CGFloat(project.canvas.format.h)
        )
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 60)

        logger.debug("🖼️ Video composition: render size = \(Int(renderSize.width))x\(Int(renderSize.height)), duration = \(composition.duration.seconds)s")

        // Create instruction
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRangeMake(start: .zero, duration: composition.duration)

        // Screen layer instruction - scale screen to fill canvas
        let screenLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)

        // Calculate screen transform to fill canvas (same as export)
        let screenSourceSize = CoreFoundation.CGSize(
            width: CGFloat(project.primarySources?.screen.size.w ?? 0),
            height: CGFloat(project.primarySources?.screen.size.h ?? 0)
        )

        // Simple fill transform (maintain aspect ratio)
        let scaleX = renderSize.width / screenSourceSize.width
        let scaleY = renderSize.height / screenSourceSize.height
        let scale = min(scaleX, scaleY)

        let scaledWidth = screenSourceSize.width * scale
        let scaledHeight = screenSourceSize.height * scale

        let offsetX = (renderSize.width - scaledWidth) / 2
        let offsetY = (renderSize.height - scaledHeight) / 2

        var screenTransform = CGAffineTransform.identity
        screenTransform = screenTransform.translatedBy(x: offsetX, y: offsetY)
        screenTransform = screenTransform.scaledBy(x: scale, y: scale)

        screenLayerInstruction.setTransform(screenTransform, at: .zero)

        // Add camera layer instruction if camera track exists
        if let cameraTrack = cameraTrack, let cameraPosition = project.canvas.layout.camera {
            let cameraLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: cameraTrack)

            let cameraSourceSize = CoreFoundation.CGSize(
                width: CGFloat(project.primarySources?.camera?.size.w ?? 0),
                height: CGFloat(project.primarySources?.camera?.size.h ?? 0)
            )

            // Calculate camera overlay transform
            let cameraX = cameraPosition.x * renderSize.width
            let cameraY = cameraPosition.y * renderSize.height
            let cameraW = cameraPosition.w * renderSize.width
            let cameraH = cameraPosition.h * renderSize.height

            // Scale to fit
            let camScaleX = cameraW / cameraSourceSize.width
            let camScaleY = cameraH / cameraSourceSize.height
            let camScale = min(camScaleX, camScaleY)

            // Actual scaled size
            let camScaledWidth = cameraSourceSize.width * camScale
            let camScaledHeight = cameraSourceSize.height * camScale

            // Center in target rect
            let camOffsetX = cameraX + (cameraW - camScaledWidth) / 2
            let camOffsetY = cameraY + (cameraH - camScaledHeight) / 2

            // Build transform
            var cameraTransform = CGAffineTransform.identity
            cameraTransform = cameraTransform.translatedBy(x: camOffsetX, y: camOffsetY)
            cameraTransform = cameraTransform.scaledBy(x: camScale, y: camScale)

            cameraLayerInstruction.setTransform(cameraTransform, at: .zero)

            // Add both layer instructions (screen first, then camera on top)
            instruction.layerInstructions = [screenLayerInstruction, cameraLayerInstruction]
        } else {
            // Only screen layer
            instruction.layerInstructions = [screenLayerInstruction]
        }

        videoComposition.instructions = [instruction]

        logger.debug("🎬 Video composition created with \(instruction.layerInstructions.count) layer instructions")

        // Create player item with video composition
        do {
            let playerItem = await MainActor.run {
                let item = AVPlayerItem(asset: composition)
                item.videoComposition = videoComposition
                logger.debug("✅ Player item created on main actor")
                return item
            }
            player = AVPlayer(playerItem: playerItem)
            self.composition = composition

            logger.debug("✅ Player created successfully with composition")
        } catch {
            logger.error("❌ Error creating player: \(error.localizedDescription)")
            throw PreviewError.playbackFailed("Failed to create player: \(error.localizedDescription)")
        }
        } catch {
            logger.error("❌ UNHANDLED ERROR in createPlayerWithEdits: \(error.localizedDescription)")
            dump(error, name: "Preview Error", indent: 2)
            throw PreviewError.playbackFailed("Preview failed: \(error.localizedDescription)")
        }

        // Add time observer for current time tracking
        // Note: In a real implementation, we would add a periodic time observer here
        // For now, we'll track time manually during playback
    }
}
