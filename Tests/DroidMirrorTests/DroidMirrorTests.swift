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
        XCTAssertTrue(arguments.contains("--video-codec"))
        XCTAssertTrue(arguments.contains("h264"))
        XCTAssertTrue(arguments.contains("/tmp/demo.mp4"))
    }

    func testParsesWiFiAddressFromRoute() {
        let route = "192.168.1.0/24 dev wlan0 proto kernel scope link src 192.168.1.88"
        XCTAssertEqual(DeviceService.parseWiFiAddress(route), "192.168.1.88")
    }

    func testSerializesKeyPressAndRelease() {
        let data = ScrcpyControlMessageEncoder.encode(.key(.home))

        XCTAssertEqual(data.count, 28)
        XCTAssertEqual(data[0], 0)
        XCTAssertEqual(data[1], 0)
        XCTAssertEqual(data.bigEndianUInt32(at: 2), 3)
        XCTAssertEqual(data[14], 0)
        XCTAssertEqual(data[15], 1)
        XCTAssertEqual(data.bigEndianUInt32(at: 16), 3)
    }

    func testSerializesTouchEvent() {
        let data = ScrcpyControlMessageEncoder.encode(
            .touch(action: .down, x: 120, y: 240, width: 1080, height: 2400)
        )

        XCTAssertEqual(data.count, 32)
        XCTAssertEqual(data[0], 2)
        XCTAssertEqual(data[1], TouchAction.down.rawValue)
        XCTAssertEqual(data.bigEndianUInt32(at: 10), 120)
        XCTAssertEqual(data.bigEndianUInt32(at: 14), 240)
        XCTAssertEqual(data.bigEndianUInt16(at: 18), 1080)
        XCTAssertEqual(data.bigEndianUInt16(at: 20), 2400)
    }
}
