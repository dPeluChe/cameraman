import XCTest
import AVFoundation
@testable import EngineKit

final class AudioInputDevicesTests: XCTestCase {
    func testListHasUniqueIDs() {
        let ids = AudioInputDevices.list().map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testRouteToUnknownDeviceKeepsDefault() {
        XCTAssertFalse(AudioInputDevices.route(AVAudioEngine(), toDeviceUID: "no-such-device-uid"))
        XCTAssertFalse(AudioInputDevices.route(AVAudioEngine(), toDeviceUID: nil))
    }

    func testRecordingConfigurationCarriesMicDevice() {
        let screen = CaptureEngine.CaptureConfiguration(
            sourceType: .display,
            display: SourceSelector.DisplaySource(
                id: "d", name: "D", width: 1920, height: 1080, refreshRate: 60, isMain: true
            )
        )
        let config = Recorder.RecordingConfiguration(screenConfig: screen, captureMicAudio: true, micDeviceID: "abc")
        XCTAssertEqual(config.micDeviceID, "abc")
    }
}
