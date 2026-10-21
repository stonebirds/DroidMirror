import XCTest
@testable import DroidMirror

final class DroidMirrorTests: XCTestCase {
    func testParsesConnectedAndUnauthorizedDevices() {
        let output = """
        List of devices attached
        R58M123456 device product:beyond1 model:SM_G9730 device:beyond1 transport_id:1
        192.168.1.20:37123 unauthorized transport_id:2

        """

        let devices = DeviceService.parse(output)

        XCTAssertEqual(devices.count, 2)
        XCTAssertEqual(devices[0].serial, "R58M123456")
        XCTAssertEqual(devices[0].name, "SM G9730")
        XCTAssertEqual(devices[0].state, .device)
        XCTAssertEqual(devices[1].state, .unauthorized)
        XCTAssertTrue(devices[1].isWireless)
    }

    func testSettingsBuildScrcpyArguments() {
        let settings = MirrorSettings(
            maxSize: 1280,
            bitRateMbps: 4,
            maxFPS: 30,
            audioEnabled: false,
            turnScreenOff: true,
            stayAwake: true
        )

        let arguments = settings.arguments(
            serial: "device-1",
            recordingURL: URL(fileURLWithPath: "/tmp/demo.mp4")
        )

        XCTAssertTrue(arguments.contains("device-1"))
        XCTAssertTrue(arguments.contains("--no-audio"))
        XCTAssertTrue(arguments.contains("--turn-screen-off"))
        XCTAssertTrue(arguments.contains("--stay-awake"))
        XCTAssertTrue(arguments.contains("/tmp/demo.mp4"))
    }
}
