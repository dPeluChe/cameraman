//
//  ProjectStore+MobileBundle.swift
//  EngineKit
//
//  Open a `.cameramanproject` bundle written by Cameraman Mobile. Mobile ships two
//  project records: `project.json` in its own schema (v1) and `project.enginekit.json`
//  in ours (v2). Decoding the first is what fails today, so this path reads the second
//  and carries the manifest's notes back to the UI.
//

import AVFoundation
import Foundation

// MARK: - The mobile bundle's manifest

/// `manifest.json` as Cameraman Mobile writes it. Mobile owns this shape — see that
/// repo's `docs/DESKTOP_READER.md` §3 for the table this mirrors.
public struct MobileBundleManifest: Codable, Equatable, Sendable {

    public struct Generator: Codable, Equatable, Sendable {
        public let app: String
        public let version: String
        public let platform: String
    }

    public struct Counts: Codable, Equatable, Sendable {
        public let takes: Int
        public let photos: Int
        public let sequenceClips: Int
        public let mediaFiles: Int
    }

    /// One media file carried by the bundle. `role` stays a plain String: a role added
    /// by a future mobile build must not fail the decode of the whole manifest.
    public struct Entry: Codable, Equatable, Sendable {
        public let relativePath: String
        public let role: String
        public let refId: UUID
        public let byteCount: Int64
    }

    public let bundleFormatVersion: Int
    public let generator: Generator
    public let exportedAt: Date
    public let projectId: UUID
    public let projectName: String
    /// Schema version of the *mobile* record, not ours.
    public let schemaVersion: Int
    public let projectFile: String
    /// The EngineKit-schema translation. Absent in bundleFormatVersion 1.
    public let engineKitProjectFile: String?
    public let engineKitSchemaVersion: Int?
    public let mappingNotes: [String]
    public let sequenceDuration: TimeInterval
    public let counts: Counts
    public let media: [Entry]
    public let missingMedia: [String]
    public let totalMediaBytes: Int64

    /// Hand-written for the same reason mobile's own decoder is: the three mapping keys
    /// did not exist in bundleFormatVersion 1, and a missing key there is not corruption.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bundleFormatVersion = try c.decode(Int.self, forKey: .bundleFormatVersion)
        generator = try c.decode(Generator.self, forKey: .generator)
        exportedAt = try c.decode(Date.self, forKey: .exportedAt)
        projectId = try c.decode(UUID.self, forKey: .projectId)
        projectName = try c.decode(String.self, forKey: .projectName)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        projectFile = try c.decode(String.self, forKey: .projectFile)
        engineKitProjectFile = try c.decodeIfPresent(String.self, forKey: .engineKitProjectFile)
        engineKitSchemaVersion = try c.decodeIfPresent(Int.self, forKey: .engineKitSchemaVersion)
        mappingNotes = try c.decodeIfPresent([String].self, forKey: .mappingNotes) ?? []
        sequenceDuration = try c.decode(TimeInterval.self, forKey: .sequenceDuration)
        counts = try c.decode(Counts.self, forKey: .counts)
        media = try c.decode([Entry].self, forKey: .media)
        missingMedia = try c.decode([String].self, forKey: .missingMedia)
        totalMediaBytes = try c.decode(Int64.self, forKey: .totalMediaBytes)
    }
}

// MARK: - Import result

/// What an import produced, including everything the user should be told about it.
/// A desktop-written bundle simply reports no notes and no missing media.
public struct BundleImportResult: Equatable, Sendable {
    public let projectId: ProjectId
    /// Whether the bundle came from Cameraman Mobile (it carried a manifest).
    public let isMobile: Bool
    /// What the mobile → EngineKit translation could not carry. Show it.
    public let mappingNotes: [String]
    /// Files the record references that were not in the bundle. Show it.
    public let missingMedia: [String]
    /// Which build wrote the bundle, when it is a mobile one.
    public let generator: MobileBundleManifest.Generator?
}

// MARK: - Reading

extension ProjectStore {

    /// Highest `bundleFormatVersion` this build understands. A bundle above it is refused
    /// rather than guessed at: a newer mobile could move a file this reader depends on.
    public static let supportedMobileBundleFormatVersion = 2

    static let mobileBundleManifestName = "manifest.json"

    /// Import any Cameraman bundle — mobile or desktop — as a new project.
    ///
    /// Both apps name their export `.cameramanproject` and both put a `project.json` at
    /// its root, so the extension decides nothing. `manifest.json` is what tells them
    /// apart: only mobile writes one.
    public func importBundle(from bundleURL: URL) async throws -> BundleImportResult {
        let manifestFile = bundleURL.appendingPathComponent(Self.mobileBundleManifestName)
        guard fileManager.fileExists(atPath: manifestFile.path) else {
            // Desktop's own bundle (or a copied project folder): unchanged path.
            let id = try await importProjectBundle(from: bundleURL)
            return BundleImportResult(
                projectId: id, isMobile: false, mappingNotes: [], missingMedia: [], generator: nil
            )
        }
        return try await importMobileBundle(from: bundleURL, manifestFile: manifestFile)
    }

    private func importMobileBundle(from bundleURL: URL, manifestFile: URL) async throws -> BundleImportResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let manifest: MobileBundleManifest
        do {
            manifest = try decoder.decode(MobileBundleManifest.self, from: try Data(contentsOf: manifestFile))
        } catch {
            throw EngineKitError.invalidConfiguration(
                "Unreadable manifest.json in this Cameraman Mobile bundle (\(error.localizedDescription))"
            )
        }

        guard manifest.bundleFormatVersion <= Self.supportedMobileBundleFormatVersion else {
            throw EngineKitError.invalidConfiguration(
                "This bundle was written by a newer Cameraman Mobile (bundle format "
                    + "\(manifest.bundleFormatVersion); this build reads up to "
                    + "\(Self.supportedMobileBundleFormatVersion)). Update Cameraman to open it."
            )
        }

        // `project.json` in a mobile bundle is the mobile schema and will not decode here.
        // The translation is the file the manifest names.
        guard let engineKitFile = manifest.engineKitProjectFile else {
            throw EngineKitError.invalidConfiguration(
                "This bundle predates the EngineKit translation (bundle format "
                    + "\(manifest.bundleFormatVersion)) and carries only Cameraman Mobile's own "
                    + "project record. Re-export it from a current version of the app."
            )
        }
        let projectFile = bundleURL.appendingPathComponent(engineKitFile)
        guard fileManager.fileExists(atPath: projectFile.path) else {
            throw EngineKitError.invalidConfiguration(
                "The bundle's manifest names \(engineKitFile), but the file is not in the bundle."
            )
        }

        let original: Project
        do {
            original = try decoder.decode(Project.self, from: try Data(contentsOf: projectFile))
        } catch {
            throw EngineKitError.invalidConfiguration(
                "Not a readable Cameraman Mobile project: \(engineKitFile) (\(error.localizedDescription))"
            )
        }

        let newId = ProjectId()
        let destDir = baseDirectory.appendingPathComponent(newId.uuidString, isDirectory: true)
        do {
            // Media paths are bundle-root relative in both records, so the tree lands where
            // the record already points. `takes/` and `media/` are mobile's own folder names
            // and are simply carried over; the regenerable dirs are restored afterwards.
            try copyTree(from: bundleURL, to: destDir)
            try createProjectDirectoryStructure(at: destDir)
            // `saveProject` is about to write our record to `project.json`, replacing the
            // mobile one. The translation would then be a stale second copy — drop it, and
            // keep `manifest.json` as the provenance of what was imported.
            try? fileManager.removeItem(at: destDir.appendingPathComponent(engineKitFile))
        } catch {
            try? fileManager.removeItem(at: destDir)
            throw error
        }

        var imported = original.withNewIdentity(projectId: newId)
        imported.takes = await reprobedTakes(imported.takes, in: destDir)
        try await saveProject(imported)

        let provenance = "format \(manifest.bundleFormatVersion), "
            + "\(manifest.generator.app) \(manifest.generator.version) on \(manifest.generator.platform)"
        logger.info("Imported Cameraman Mobile bundle (\(provenance)) as \(newId.uuidString)")
        return BundleImportResult(
            projectId: newId,
            isMobile: true,
            mappingNotes: manifest.mappingNotes,
            missingMedia: manifest.missingMedia,
            generator: manifest.generator
        )
    }

    /// Mobile writes `fps` and `size` nominally — it stores neither, and our decoder requires
    /// both. The Mac has the files and the CPU the phone did not, and `hasMixedScreenResolutions`
    /// picks a render path off `size`, so a wrong one costs a wrong path.
    ///
    /// A file we cannot read keeps the nominal values rather than being zeroed: a bad guess still
    /// plays, a zero size does not.
    private func reprobedTakes(_ takes: [Project.Take], in projectDirectory: URL) async -> [Project.Take] {
        var result: [Project.Take] = []
        for take in takes {
            var take = take
            let screen = take.sources.screen
            let url = projectDirectory.appendingPathComponent(screen.path)
            guard fileManager.fileExists(atPath: url.path),
                  let track = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video).first
            else {
                result.append(take)
                continue
            }
            // Phone video carries its rotation in the track transform, so the natural size is
            // often landscape for a portrait movie. Orient it before recording the dimensions.
            let natural = (try? await track.load(.naturalSize)) ?? .zero
            let transform = (try? await track.load(.preferredTransform)) ?? .identity
            let oriented = natural.applying(transform)
            let w = Int(abs(oriented.width).rounded())
            let h = Int(abs(oriented.height).rounded())
            let fps = Double((try? await track.load(.nominalFrameRate)) ?? 0)
            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            let bytes = (attributes?[.size] as? NSNumber)?.uint64Value

            take.sources.screen = Project.Sources.MediaTrack(
                path: screen.path,
                fps: fps > 0 ? fps : screen.fps,
                size: (w > 0 && h > 0) ? Project.Sources.Size(w: w, h: h) : screen.size,
                syncOffsetMs: screen.syncOffsetMs,
                sha256: screen.sha256,
                sizeBytes: bytes ?? screen.sizeBytes,
                capture: screen.capture
            )
            result.append(take)
        }
        return result
    }
}
