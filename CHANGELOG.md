# Changelog

All notable changes to Cameraman will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-01-22

### Added
- **Complete export system** with user-selected save location
- **Export presets**: Web 1080p (H.264), High 1080p (HEVC), Portrait 1080p (H.264), Animated GIF
- **Timeline editor** with drag-and-drop clip management
- **Trim and cut operations** for screen and audio tracks
- **Zoom controls** for timeline navigation
- **Progress tracking** with detailed export stages (validation, loading, composition, export, verification)
- **NSSavePanel integration** for user-controlled file destination
- **Play button** to preview exported video within app
- **Hotkey manager** for recording controls (ExportEngine/HotkeyManager)
- **Recording state manager** with Combine support (RecordingStateManager)

### Fixed
- **Sandbox entitlements** - Added `com.apple.security.files.user-selected.read-write` and `com.apple.security.files.downloads.read-write` for file access
- **Export engine errors** - Improved error logging with domain, code, and userInfo details
- **AVAsset deprecation** - Changed `AVAsset(url:)` to `AVURLAsset(url:)` for macOS 15 compatibility
- **Telemetry controls** - Fixed optional unwrapping issues (TelemetryControlsView)
- **Overlay editor** - Changed file-private access to internal for extensions
- **App delegate imports** - Added missing `EngineKit` import for hotkey registration
- **Recording notifications** - Removed duplicate `openRecordingWindow` declaration
- **Recording control view model** - Added missing imports (Combine, AppKit, CoreVideo)
- **Export view model** - Fixed `temporaryExportURL` path construction to use correct project directory
- **Export view** - Fixed cancel button to properly close modal
- **Video export session** - Added detailed directory and file permission verification
- **Save panel** - Ensured .mp4 extension is added to user-selected files
- **Progress monitoring** - Fixed state updates to prevent UI freezing

### Changed
- **Export workflow** - Files are now exported to temporary location within sandbox, then user saves to desired location via save panel
- **Export logging** - Added comprehensive logging with emojis (🎬) for easier debugging
- **UI behavior** - Export completion now shows "Done" button instead of "Cancel Export"
- **File management** - Improved handling of existing files before export

### Technical Improvements
- **VideoExportSession**:
  - Added `shouldOptimizeForNetworkUse = true` for better export performance
  - Added detailed error reporting with AVAssetExportSession status descriptions
  - Added verification of output directory existence and write permissions
  - Added immediate file existence check after export completion
  - Improved error messages with domain, code, and userInfo details

- **ExportViewModel**:
  - Added `temporaryExportURL` and `showSavePanel` state management
  - Implemented `saveExportToFile()` with NSSavePanel integration
  - Fixed `projectDirectory` parameter passing from ExportView
  - Added delay before showing save panel for proper UI updates

- **ExportView**:
  - Added "Play Video (Temporary)" button for immediate preview
  - Fixed cancel button behavior to change to "Done" after completion
  - Improved user feedback with detailed progress messages
  - Added comprehensive logging for debugging

### Known Issues
- Exported videos may show black bars/letterboxing (aspect ratio issue)
- Frame counter warnings during recording startup (non-critical)

## [0.1.0] - Previous Release

### Added
- Basic screen recording with ScreenCaptureKit
- System audio capture
- Camera video capture
- Microphone audio capture
- Separate track recording (screen, system audio, camera, mic audio)
- Sandbox-compatible file storage
