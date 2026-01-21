# labs-cameraman (Project Studio / Cameraman)

macOS local‑first screen recorder + editor.

## Current functional status (recording)

Recording is functional with **separate tracks**:

- `screen.mov` (ScreenCaptureKit video)
- `system_audio.m4a` (system audio)
- `camera.mov` (camera video)
- `mic_audio.m4a` (microphone)

Outputs are written inside the app container (sandbox):

- `~/Library/Containers/com.dpeluchestudios.CameramanApp/Data/Documents/Recordings/recording_<ISO8601>/`

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

Because the app runs with **App Sandbox**, camera/microphone require entitlements:

- `CameramanApp/CameramanApp.entitlements`
  - `com.apple.security.device.camera = true`
  - `com.apple.security.device.audio-input = true`

And the Xcode target must reference it via `CODE_SIGN_ENTITLEMENTS`.

Also ensure Info.plist usage strings exist:

- `NSCameraUsageDescription`
- `NSMicrophoneUsageDescription`
- `NSScreenCaptureUsageDescription`

## Troubleshooting

- If camera/mic show `denied` even after enabling in System Settings:
  - Verify entitlements are present and referenced by the target.
  - Quit the app completely and run again.
  - Check System Settings:
    - Privacy & Security → Camera
    - Privacy & Security → Microphone
    - Privacy & Security → Screen Recording

- If a track file is created with `0 bytes`:
  - For camera, verify the capture output delegate is strongly retained for the duration of the session.

## Notes

This project intentionally records audio/video tracks separately (later export can mux them if desired).
