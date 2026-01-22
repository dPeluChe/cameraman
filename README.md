# labs-cameraman (Project Studio / Cameraman)

macOS local‑first screen recorder + editor.

**Version**: 0.2.0 (January 22, 2026)

## Current functional status

### Recording
Recording is functional with **separate tracks**:

- `screen.mov` (ScreenCaptureKit video)
- `system_audio.m4a` (system audio)
- `camera.mov` (camera video)
- `mic_audio.m4a` (microphone)

Outputs are written inside app container (sandbox):

- `~/Library/Containers/com.dpeluchestudios.CameramanApp/Data/Documents/Recordings/recording_<ISO8601>/`

### Editing & Export
Project editor is now functional with:

- **Timeline visualization** with drag-and-drop clips
- **Trim and cut** operations for screen and audio tracks
- **Zoom controls** for timeline navigation
- **Export system** with save panel for user-selected destination
- **Export presets**: Web 1080p (H.264), High 1080p (HEVC), Portrait 1080p (H.264), Animated GIF
- **Progress tracking** with detailed export stages
- **Temporary file management** within sandbox before user saves
- **Play button** to preview exported video directly

## Build / Run

- Open: `CameramanApp/CameramanApp.xcodeproj`
- Scheme: `CameramanApp`
- Run on: `My Mac`

EngineKit can be built standalone:

```bash
cd EngineKit
swift build
```

## Permissions / Entitlements (IMPORTANT)

Because app runs with **App Sandbox**, camera/microphone/file access require entitlements:

- `CameramanApp/CameramanApp.entitlements`
  - `com.apple.security.device.camera = true`
  - `com.apple.security.device.audio-input = true`
  - `com.apple.security.files.user-selected.read-write = true` (for export)
  - `com.apple.security.files.downloads.read-write = true` (for export)

And the Xcode target must reference it via `CODE_SIGN_ENTITLEMENTS`.

Also ensure Info.plist usage strings exist:

- `NSCameraUsageDescription`
- `NSMicrophoneUsageDescription`
- `NSScreenCaptureUsageDescription`

## Troubleshooting

- If camera/mic show `denied` even after enabling in System Settings:
  - Verify entitlements are present and referenced by target.
  - Quit the app completely and run again.
  - Check System Settings:
    - Privacy & Security → Camera
    - Privacy & Security → Microphone
    - Privacy & Security → Screen Recording

- If a track file is created with `0 bytes`:
  - For camera, verify that the capture output delegate is strongly retained for the duration of the session.

- If export fails with "Cannot Save":
  - Verify that the entitlements are correct in the target settings.
  - Restart Xcode after modifying entitlements.
  - Check the export logs for detailed error information.

## Known Issues

- Exported videos may show black bars/letterboxing (aspect ratio issue)
- Frame counter warnings during recording startup (non-critical)

## Notes

This project intentionally records audio/video tracks separately (later export can mux them if desired).

For detailed changes, see [CHANGELOG.md](CHANGELOG.md).
