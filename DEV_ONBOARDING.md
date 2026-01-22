# Cameraman - Developer Onboarding Guide

**Project Name**: Cameraman (Project Studio)
**Current Version**: 0.2.0 (January 22, 2026)
**Tech Stack**: Swift, SwiftUI, AVFoundation, ScreenCaptureKit

---

## 🎬 Project Overview

**Cameraman** is a macOS native screen recorder and editor application built with SwiftUI. It's designed as a "local-first" application that stores all recordings and projects within the app's sandbox container.

### Key Features
- **Screen Recording**: Capture screen video with system audio
- **Camera Recording**: Simultaneous camera overlay recording
- **Microphone Audio**: Mic input recording
- **Timeline Editor**: Visual timeline for editing recordings
- **Export System**: Multi-format export (MP4, GIF) with customizable presets
- **Zoom/Keyframe Support**: Auto-zoom features during recording

---

## 🏗️ Architecture

### Project Structure
```
labs-cameraman/
├── App/                    # Main application layer (SwiftUI)
│   └── Sources/Cameraman/
│       ├── ExportView.swift
│       ├── ProjectEditorView.swift
│       ├── TimelineView.swift
│       └── [UI Components]
├── EngineKit/              # Core engine and business logic
│   ├── Sources/EngineKit/
│   │   ├── Export/         # Export engine
│   │   ├── Capture/        # Recording engine
│   │   ├── Preview/        # Preview system
│   │   ├── Zoom/           # Zoom plan generator
│   │   └── Intelligence/   # AI services
└── CameramanApp/          # Xcode project and configs
    ├── CameramanApp.entitlements
    └── Info.plist
```

### Tech Stack Details
- **Language**: Swift 5.x
- **UI Framework**: SwiftUI
- **Video**: AVFoundation, ScreenCaptureKit
- **Audio**: AVAudioEngine, CoreAudio
- **Concurrency**: async/await, Combine
- **Storage**: FileManager (sandboxed container)
- **Architecture**: MVVM (Model-View-ViewModel)

### Key Libraries/Frameworks
- `AVFoundation` - Video/audio recording and export
- `ScreenCaptureKit` - macOS screen capture
- `CoreVideo` - Video frame handling
- `CoreText` - Caption rendering
- `AppKit` - Native macOS controls (NSSavePanel)

---

## 📊 Current Status (v0.2.0)

### ✅ Implemented Features

#### Recording System
- Screen recording using ScreenCaptureKit
- System audio capture
- Camera overlay recording
- Microphone input recording
- Separate track storage (screen.mov, system_audio.m4a, camera.mov, mic_audio.m4a)
- Recording state management with Combine
- Hotkey support for recording controls
- Recording indicator window

#### Editor System
- Timeline visualization with drag-and-drop clips
- Trim operations for screen and audio tracks
- Cut operations for segmenting clips
- Zoom controls for timeline navigation
- Project-based editor (save/load projects)
- Source management for multi-take recordings

#### Export System
- Complete export engine with AVAssetExportSession
- Multi-format support:
  - MP4 (H.264) - Web 1080p
  - MP4 (HEVC) - High 1080p
  - MP4 (H.264) - Portrait 9:16 1080p
  - GIF - Animated GIF
- Progress tracking with detailed stages:
  - Validation
  - Asset loading
  - Composition building
  - Video composition setup
  - Export session
  - Verification
- User-controlled save location via NSSavePanel
- Temporary file management within sandbox
- Play button to preview exported video
- Export error handling with detailed logging

#### Preview System
- Real-time preview of compositions
- Frame extraction for thumbnails
- Preview rendering with zoom support

#### AI Integration (Foundation)
- AI service architecture with job queue
- Local processing capabilities
- File helpers for AI operations
- Model definitions for AI features

### ⚠️ Known Issues
- **Aspect Ratio Issue**: Exported videos may show black bars/letterboxing (needs fitMode implementation)
- **Frame Counter Warnings**: Non-critical warnings during recording startup
- **Export Performance**: Some exports may pause at 90% progress (investigate composition timing)

---

## 🚀 Development Setup

### Prerequisites
- macOS 14.0+ (for ScreenCaptureKit)
- Xcode 15.0+
- Swift 5.9+

### Build Instructions
1. Open `CameramanApp/CameramanApp.xcodeproj`
2. Select scheme: `CameramanApp`
3. Select destination: `My Mac`
4. Build and Run (Cmd+R)

### Standalone EngineKit Build
```bash
cd EngineKit
swift build
```

---

## 🔑 Critical Information for Development

### Sandbox Configuration
The app runs with **App Sandbox** enabled. This affects:
- File access - Only sandbox container and user-selected locations
- Camera/mic - Require entitlements
- Export - Must use NSSavePanel for user consent

**Entitlements** (CameramanApp.entitlements):
```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.device.camera</key>
<true/>
<key>com.apple.security.device.audio-input</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
<key>com.apple.security.files.downloads.read-write</key>
<true/>
```

### File Paths
- **Recordings**: `~/Library/Containers/com.dpeluchestudios.CameramanApp/Data/Documents/Recordings/recording_<ISO8601>/`
- **Projects**: `~/Library/Containers/com.dpeluchestudios.CameramanApp/Data/Library/Application Support/ProjectStudio/Projects/`
- **Exports**: Temporary files in `.../Projects/<id>/renders/`, then user-selected location

### Code Style
- Swift: Use SwiftLint formatting
- SwiftUI: Prefer declarative syntax
- Concurrency: Use async/await for I/O operations
- Logging: Use `Logger` with descriptive messages (export uses 🎬 emoji prefix)

---

## 📋 Priority Tasks (Next Development Phase)

### 🔴 High Priority

#### 1. Fix Aspect Ratio/Black Bars Issue
**Problem**: Exported videos show black bars/letterboxing
**Root Cause**: Fit mode not properly applied during export composition
**Files to Check**:
- `EngineKit/Sources/EngineKit/Export/ExportTransformUtils.swift`
- `EngineKit/Sources/EngineKit/Export/VideoExportSession.swift` (line ~216)
**Approach**:
- Verify `calculateDownscaleTransform` uses correct fitMode
- Implement proper aspect ratio calculation
- Test with different source resolutions

#### 2. Improve Export Reliability
**Problem**: Some exports pause at 90% progress
**Files to Check**:
- `EngineKit/Sources/EngineKit/Export/VideoExportSession.swift` (line ~282-292)
**Approach**:
- Add timeout handling for export progress
- Improve error recovery
- Add export session cancellation cleanup

#### 3. Fix Timeline Performance
**Problem**: Timeline may lag with many segments
**Files to Check**:
- `App/Sources/Cameraman/TimelineView.swift`
- `EngineKit/Sources/EngineKit/Editor/EditorModel.swift`
**Approach**:
- Implement virtual scrolling for timeline
- Optimize clip rendering
- Add lazy loading for timeline segments

### 🟡 Medium Priority

#### 4. Add Caption Support
**Feature**: Burn captions into exported video
**Files to Check**:
- `EngineKit/Sources/EngineKit/Export/VideoExportSession.swift` (line ~359-514)
**Status**: Caption layer creation is implemented but needs:
- Caption file parsing (SRT format)
- Caption style configuration
- Caption timing verification
- Toggle for caption burn-in

#### 5. Implement Zoom Keyframe System
**Feature**: Auto-zoom during recording based on cursor movement
**Files to Check**:
- `EngineKit/Sources/EngineKit/Zoom/ZoomPlanGenerator.swift`
- `EngineKit/Sources/EngineKit/Zoom/ZoomTypes.swift`
**Approach**:
- Complete zoom plan generation algorithm
- Implement zoom easing functions
- Add zoom keyframe UI in timeline
- Apply zoom transforms during export

#### 6. Add GIF Export Optimization
**Feature**: Improve GIF export quality and file size
**Files to Check**:
- `EngineKit/Sources/EngineKit/Export/GIFExportSession.swift`
**Approach**:
- Implement frame optimization
- Add color palette reduction
- Support for GIF-specific options (dithering, loop count)

### 🟢 Low Priority

#### 7. Add Export Progress Persistence
**Feature**: Resume interrupted exports
**Approach**:
- Save export progress to disk
- Implement resume functionality
- Add export queue management

#### 8. Improve UI/UX
**Features**:
- Export preset management (custom presets)
- Export history
- Keyboard shortcuts for editor
- Dark mode support
- Accessibility improvements

---

## 🐛 Common Issues & Solutions

### Export Fails with "Cannot Save"
**Cause**: Entitlements not configured or Xcode not restarted
**Solution**:
1. Check entitlements in target settings
2. Restart Xcode after modifying entitlements
3. Verify export logs for detailed errors

### Camera/Mic Denied
**Cause**: Permissions not granted or entitlements missing
**Solution**:
1. Check System Settings → Privacy & Security
2. Verify entitlements in CameramanApp.entitlements
3. Check Info.plist usage descriptions
4. Quit and restart app

### Sandbox Extension Failed
**Cause**: Trying to access files outside sandbox without user consent
**Solution**:
1. Use NSSavePanel for user file access
2. Store temporary files within sandbox
3. Copy files to user-selected location after export

### AVAsset Deprecation Warning
**Cause**: Using deprecated `AVAsset(url:)` API
**Solution**:
1. Replace with `AVURLAsset(url:)`
2. Already fixed in v0.2.0
3. Check for remaining instances

---

## 📚 Documentation

- **README.md** - Project overview and build instructions
- **CHANGELOG.md** - Version history and changes
- **DEV_ONBOARDING.md** - This document

---

## 🤝 Getting Started

1. **Read the codebase**: Start with `ExportEngine.swift` and `ProjectEditorView.swift`
2. **Understand the data model**: Check `Project.swift` and related extensions
3. **Run the app**: Try recording and exporting to understand the flow
4. **Review logs**: Export logs use 🎬 emoji prefix for easy debugging
5. **Ask questions**: The codebase uses Combine and async/await extensively

---

## 📞 Contact & Support

For questions about:
- **Architecture**: Review this guide first
- **Specific features**: Check related source files
- **Bug reports**: Include console logs and reproduction steps
- **Feature requests**: Open an issue with detailed description

---

**Last Updated**: January 22, 2026
**Version**: 0.2.0
