import BrightnessCore
import BrightnessHardware
import Foundation
import AppKit

enum CLIError: Error, CustomStringConvertible {
    case missingCommand
    case missingValue(String)
    case invalidValue(String)
    case unknownCommand(String)

    var description: String {
        switch self {
        case .missingCommand:
            return "A command is required."
        case let .missingValue(name):
            return "A value is required for \(name)."
        case let .invalidValue(name):
            return "The value for \(name) is invalid."
        case let .unknownCommand(command):
            return "Unknown command: \(command)"
        }
    }
}

struct CLIArguments {
    let values: [String]

    var command: String? { values.dropFirst().first }

    func option(_ name: String) -> String? {
        guard let index = values.firstIndex(of: name), values.indices.contains(index + 1) else {
            return nil
        }
        return values[index + 1]
    }

    func positional(at index: Int) -> String? {
        guard values.count > index + 2 else { return nil }
        return values[index + 2]
    }

    func doubleOption(_ name: String, default defaultValue: Double) throws -> Double {
        guard let raw = option(name) else { return defaultValue }
        guard let value = Double(raw), value.isFinite else {
            throw CLIError.invalidValue(name)
        }
        return value
    }

    func uint16Option(_ name: String, default defaultValue: UInt16) throws -> UInt16 {
        guard let raw = option(name) else { return defaultValue }
        guard let value = UInt16(raw) else {
            throw CLIError.invalidValue(name)
        }
        return value
    }
}

@main
struct BrightnessRelayCLI {
    @MainActor
    static func main() {
        let arguments = CLIArguments(values: CommandLine.arguments)
        #if DEBUG
        if arguments.command == "picker-preview" {
            _ = NSApplication.shared
            Task {do {try await BringHereChecks.render(arguments);Foundation.exit(0)}catch{fail(error)}}
            NSApplication.shared.run();return
        }
        if arguments.command == "panel-preview" {
            do { try DeskPreview.render(arguments) } catch { fail(error) }
            return
        }
        #endif
        if arguments.command == "menu" {
            do {
                try menu(arguments)
            } catch {
                fail(error)
            }
            return
        }

        Task.detached {
            do {
                try await run(arguments)
                Foundation.exit(0)
            } catch {
                fail(error)
            }
        }
        if arguments.command == "source" || arguments.command == "simulation-check" {
            RunLoop.main.add(Port(), forMode: .default)
            CFRunLoopRun()
        } else { dispatchMain() }
    }

    private static func fail(_ error: Error) -> Never {
        fputs("error: \(error)\n", stderr)
        fputs("Run 'brightness-relay help' for usage.\n", stderr)
        Foundation.exit(1)
    }

    private static func run(_ arguments: CLIArguments) async throws {
        guard let command = arguments.command else {
            throw CLIError.missingCommand
        }
        switch command {
        case "help", "--help", "-h":
            print(help)
        #if DEBUG
        case "window-fixture-move":
            guard let screen=arguments.option("--screen") else{throw CLIError.missingValue("--screen")}
            try await WindowGeometryChecks.moveFixture(to:screen)
        case "window-geometry-check":
            try await WindowGeometryChecks.run()
        case "window-geometry-audit":
            guard let app=arguments.option("--app"),let screen=arguments.option("--screen") else{throw CLIError.missingValue("--app and --screen")}
            try await WindowGeometryChecks.live(appName:app,expectedScreen:screen)
        case "tv-identity-check":
            try TVIdentityChecks.run()
        case "tv-identity-audit":
            guard try TVIdentity.storedCertificate() != nil else{throw TVError("No current certificate matches the tagged TV key")}
            print("Current saved TV certificate found by tagged public-key hash; no key creation, signing or pairing change.")
        case "bring-here-check":
            try await BringHereChecks.run()
        case "tv-reconnect-check":
            try await TVReconnectChecks.run()
        case "tv-lan-probe":
            let candidates: [String] = await withCheckedContinuation { continuation in
                _ = TVLANDiscovery.search(name:"Smart TV") { continuation.resume(returning:$0) }
            }
            print(candidates)
        case "tv-mapping-check":
            try await TVMappingChecks.run()
        case "ddc-readback-check":
            try DDCReadbackChecks.run()
            try await HardwareReadbackChecks.run()
        case "samsung-source-check":
            try await SamsungSourceChecks.run()
        case "display-identity-live-check":
            try DisplayIdentityChecks.verifyNativeSnapshot()
        case "display-identity-check":
            try DisplayIdentityChecks.run()
            try DisplayConnectionChecks.run()
        case "display-recovery-check":
            try DisplayRecoveryChecks.run()
        case "simulation-check":
            try await RuntimeChecks.run()
        #endif
        case "probe":
            probe()
        case "displays":
            listDisplays()
        case "sample":
            let value = try BuiltInBrightnessSource().sample()
            print(String(format: "%.4f", value))
        case "sensor-sample":
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(decoding: try encoder.encode(AmbientLightSource().sample()), as: UTF8.self))
        case "send-sample":
            try await sendCurrentBrightness(using: makeClient(arguments), source: BuiltInBrightnessSource())
        case "status":
            print(try await makeClient(arguments).status())
        case "sync-now":
            try await makeClient(arguments).sendControl(.syncNow)
            print("Requested a fresh Air brightness and colour reading.")
        case "enable-keys":
            try await makeClient(arguments).sendControl(.enableKeys)
            print("Requested macOS Accessibility access for brightness keys.")
        case "set-color":
            guard let id = arguments.positional(at: 0), let raw = arguments.positional(at: 1),
                  let kelvin = raw == "adaptive" ? -1.0 : (raw == "off" ? 0.0 : Double(raw)),
                  kelvin == -1 || kelvin == 0 || (3500...7500).contains(kelvin) else {
                throw CLIError.invalidValue("display ID and colour temperature (0=off, 3500–7500 K)")
            }
            try await makeClient(arguments).sendControl(.setColor, displayID: id, value: kelvin)
            print("Colour request accepted; inspect the app for the resulting state.")
        case "disconnect-display", "connect-display":
            guard let id = arguments.positional(at: 0) else { throw CLIError.missingValue("display ID") }
            try await makeClient(arguments).sendControl(.setConnection, displayID: id,
                value: command == "connect-display" ? 1 : 0)
            print("Connection request accepted; use status to verify.")
        case "recover-displays":
            let outcomes = try DisplayConnectionController().recoverAll()
            for outcome in outcomes {
                print("\(outcome.display.name): \(outcome.error ?? "reconnected")")
            }
            if outcomes.contains(where: { !$0.succeeded }) {
                throw CLIError.invalidValue("some displays could not be recovered; see results above")
            }
        case "set":
            guard let raw = arguments.positional(at: 0), let percentage = UInt16(raw), percentage <= 100 else {
                throw CLIError.invalidValue("brightness")
            }
            let count = try ExternalDDCController().set(percentage: percentage)
            print("Applied \(percentage)% to \(count) display(s).")
        case "set-display":
            try setDisplay(arguments)
        case "wake-all":
            try await makeClient(arguments).sendControl(.wakeAll)
            print("Requested reconnection of all known screens.")
        case "show-menu":
            try await makeClient(arguments).sendControl(.showMenu)
            print("Opened the BRIGHTMESS controller.")
        case "token":
            try token(arguments)
        case "send":
            try await send(arguments)
        case "source":
            try await source(arguments)
        case "receive":
            try await receive(arguments)
        case "menu":
            try await menu(arguments)
        case "solar-sample":
            guard let fallback = try makeSolarFallback(arguments) else {
                throw CLIError.missingValue("--latitude and --longitude")
            }
            let altitude = fallback.solarAltitude(at: Date())
            let brightness = fallback.normalizedBrightness(at: Date())
            print(String(format: "Solar altitude: %.1f°; fallback signal: %.1f%%", altitude, brightness * 100))
        default:
            throw CLIError.unknownCommand(command)
        }
    }

    private static func probe() {
        let controller = ExternalDDCController()
        let displays = controller.displays()
        print("External displays: \(displays.count)")
        for (index, display) in displays.enumerated() {
            let standby = display.supportsStandby ? "standby advertised" : "no standby"
            if let reading = try? controller.readBrightness(of: display) {
                print("[\(index + 1)] \(display.name): \(reading.percentage)% live DDC; \(standby)")
            } else {
                print("[\(index + 1)] \(display.name): live DDC read unavailable; \(standby)")
            }
        }
        do {
            let value = try BuiltInBrightnessSource().sample()
            print(String(format: "Built-in display brightness: %.1f%%", value * 100))
        } catch {
            print("Built-in display brightness: unavailable")
        }
    }

    private static func listDisplays() {
        let displays = ExternalDDCController().displays()
        guard !displays.isEmpty else {
            print("No external displays found.")
            return
        }
        for (index, display) in displays.enumerated() {
            print("[\(index + 1)] \(display.name)")
            print("    id: \(display.id)")
            print(String(format: "    vendor/product/serial: %04X/%04X/%08X", display.vendorID, display.productID, display.serialNumber))
            print("    standby advertised: \(display.supportsStandby ? "yes" : "no")")
        }
    }

    private static func setDisplay(_ arguments: CLIArguments) throws {
        guard let selector = arguments.positional(at: 0) else {
            throw CLIError.missingValue("display")
        }
        guard let raw = arguments.positional(at: 1),
              let percentage = UInt16(raw), percentage <= 100
        else {
            throw CLIError.invalidValue("brightness")
        }
        let controller = ExternalDDCController()
        let displays = controller.displays()
        let display: ExternalDisplay?
        if let index = Int(selector), displays.indices.contains(index - 1) {
            display = displays[index - 1]
        } else {
            display = displays.first { $0.id == selector || $0.name == selector }
        }
        guard let display else {
            throw BrightnessHardwareError.displayNotFound(selector)
        }
        try controller.set(percentage: percentage, on: display)
        print("Applied \(percentage)% to \(display.name).")
    }

    private static func token(_ arguments: CLIArguments) throws {
        let action = arguments.positional(at: 0) ?? "create"
        guard action == "create" else {
            throw CLIError.invalidValue("token action")
        }
        let url = tokenURL(arguments)
        _ = try TokenStore.create(at: url)
        print("Created a private relay token at \(url.path)")
    }

    private static func send(_ arguments: CLIArguments) async throws {
        guard let raw = arguments.positional(at: 0), let percentage = Double(raw), (0 ... 100).contains(percentage) else {
            throw CLIError.invalidValue("brightness")
        }
        let client = try makeClient(arguments)
        try await client.send(brightness: percentage / 100, source: sourceName)
        print("Sent \(Int(percentage.rounded()))%.")
    }

    private static func source(_ arguments: CLIArguments) async throws {
        setvbuf(stdout, nil, _IOLBF, 0)
        let rawMode = arguments.option("--sync-mode") ?? (arguments.option("--interval") == nil ? "live" : "scheduled")
        guard let mode = SourceMode(rawValue: rawMode) else { throw CLIError.invalidValue("--sync-mode") }
        if mode == .live {
            let client = try makeClient(arguments)
            await LiveAirSource(client: client, name: sourceName).run()
            return
        }
        let interval = try arguments.doubleOption("--interval", default: 1_800)
        guard (60...86400).contains(interval) else {
            throw CLIError.invalidValue("--interval")
        }
        let client = try makeClient(arguments)
        let source = BuiltInBrightnessSource()

        print("Scheduled brightness sync every \(Int(interval / 60)) minutes; listening for Sync Now requests.")
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                while !Task.isCancelled {
                    do {
                        try await sendCurrentBrightness(using: client, source: source)
                    } catch {
                        fputs("scheduled sync retry: \(error)\n", stderr)
                    }
                    try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                }
            }
            group.addTask {
                while !Task.isCancelled {
                    do {
                        if try await client.awaitPull(source: sourceName) {
                            try await sendCurrentBrightness(using: client, source: source)
                        }
                    } catch {
                        fputs("pull channel retry: \(error)\n", stderr)
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                    }
                }
            }
            await group.waitForAll()
        }
    }

    private static func sendCurrentBrightness(
        using client: RelayClient,
        source: BuiltInBrightnessSource
    ) async throws {
        let ambient = AmbientLightSource().sample()
        if ambient.lidClosed {
            try await client.sendAmbient(ambient, source: sourceName)
            print("Air lid closed; sent unavailable sensor status.")
            return
        }
        do {
            let sample = try source.sample()
            try await client.send(brightness: sample, source: sourceName, ambient: ambient)
            print(String(format: "Sent %.1f%%", sample * 100) +
                (ambient.kelvin.map { String(format: " · %.0f K", $0) } ?? " · colour unavailable"))
        } catch let error as BrightnessHardwareError {
            try await client.sendAmbient(ambient, source: sourceName)
            throw error
        }
    }

    private static func receive(_ arguments: CLIArguments) async throws {
        let port = try arguments.uint16Option("--port", default: 47_777)
        let minimum = try arguments.doubleOption("--min", default: 15)
        let maximum = try arguments.doubleOption("--max", default: 100)
        let gamma = try arguments.doubleOption("--gamma", default: 1)
        let deadband = try arguments.uint16Option("--deadband", default: 2)
        let server = try makeServer(
            port: port,
            minimum: minimum,
            maximum: maximum,
            gamma: gamma,
            deadband: deadband,
            tokenURL: tokenURL(arguments),
            solarFallback: try makeSolarFallback(arguments)
        )
        try await server.start()
        print("Listening on TCP \(port); mapping MacBook 0–100% to Samsung \(Int(minimum))–\(Int(maximum))%.")
        while !Task.isCancelled {
            try await Task.sleep(nanoseconds: 3_600_000_000_000)
        }
    }

    @MainActor
    private static func menu(_ arguments: CLIArguments) throws {
        let port = try arguments.uint16Option("--port", default: 47_777)
        let minimum = try arguments.doubleOption("--min", default: 15)
        let maximum = try arguments.doubleOption("--max", default: 100)
        let gamma = try arguments.doubleOption("--gamma", default: 1)
        let deadband = try arguments.uint16Option("--deadband", default: 2)
        let server = try makeServer(
            port: port,
            minimum: minimum,
            maximum: maximum,
            gamma: gamma,
            deadband: deadband,
            tokenURL: tokenURL(arguments),
            solarFallback: try makeSolarFallback(arguments)
        )
        BrightnessMenuBarApplication.run(server: server)
    }

    private static func makeServer(
        port: UInt16,
        minimum: Double,
        maximum: Double,
        gamma: Double,
        deadband: UInt16,
        tokenURL: URL,
        solarFallback: SolarFallbackConfiguration?
    ) throws -> RelayHTTPServer {
        let token = try TokenStore.load(from: tokenURL)
        let authenticator = try RelayAuthenticator(token: token)
        let curve = try BrightnessCurve(minimum: minimum, maximum: maximum, gamma: gamma)
        let controller = ExternalDDCController()
        let coordinator = DisplayCoordinator(hardware: controller)
        guard coordinator.connectedDisplayCount > 0 else {
            throw BrightnessHardwareError.noExternalDDCDisplay
        }
        return try RelayHTTPServer(
            port: port,
            authenticator: authenticator,
            displayCoordinator: coordinator,
            curve: curve,
            deadband: deadband,
            solarFallback: solarFallback
        )
    }

    private static func makeSolarFallback(_ arguments: CLIArguments) throws -> SolarFallbackConfiguration? {
        let latitudeRaw = arguments.option("--latitude")
        let longitudeRaw = arguments.option("--longitude")
        guard latitudeRaw != nil || longitudeRaw != nil else { return nil }
        guard let latitudeRaw, let latitude = Double(latitudeRaw),
              let longitudeRaw, let longitude = Double(longitudeRaw)
        else {
            throw CLIError.invalidValue("--latitude/--longitude")
        }

        let timeZone: TimeZone
        if let identifier = arguments.option("--timezone") {
            guard let configured = TimeZone(identifier: identifier) else {
                throw CLIError.invalidValue("--timezone")
            }
            timeZone = configured
        } else {
            timeZone = .current
        }

        return try SolarFallbackConfiguration(
            latitude: latitude,
            longitude: longitude,
            timeZone: timeZone,
            staleAfter: try arguments.doubleOption("--fallback-after", default: 2_700),
            updateInterval: try arguments.doubleOption("--fallback-interval", default: 300)
        )
    }

    private static func makeClient(_ arguments: CLIArguments) throws -> RelayClient {
        let host = arguments.option("--host") ?? "macminips.local"
        let port = try arguments.uint16Option("--port", default: 47_777)
        let token = try TokenStore.load(from: tokenURL(arguments))
        return try RelayClient(host: host, port: port, authenticator: RelayAuthenticator(token: token))
    }

    private static func tokenURL(_ arguments: CLIArguments) -> URL {
        guard let path = arguments.option("--token-file") else {
            return TokenStore.defaultURL
        }
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }

    private static var sourceName: String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    private static let help = """
    BRIGHTMESS — MacBook brightness sync, TV inputs, and window moves on the Mini

    USAGE
      brightness-relay probe
      brightness-relay displays
      brightness-relay sample
      brightness-relay sensor-sample
      brightness-relay send-sample --host <mini-address>
      brightness-relay status [--host 127.0.0.1]
      brightness-relay sync-now [--host 127.0.0.1]
      brightness-relay enable-keys [--host 127.0.0.1]
      brightness-relay set-color <stable-id> <adaptive|off|3500-7500> [--host 127.0.0.1]
      brightness-relay disconnect-display <stable-id> [--host 127.0.0.1]
      brightness-relay connect-display <stable-id> [--host 127.0.0.1]
      brightness-relay recover-displays
      brightness-relay set <0-100>
      brightness-relay set-display <number-or-id> <0-100>
      brightness-relay wake-all
      brightness-relay show-menu
      brightness-relay token create [--token-file <path>]
      brightness-relay receive [--port 47777] [--min 15] [--max 100] [--gamma 1]
                               [--deadband 2] [--token-file <path>]
      brightness-relay menu [--port 47777] [--min 15] [--max 100] [--gamma 1]
                            [--deadband 2] [--token-file <path>]
                            [--latitude <degrees>] [--longitude <degrees>]
                            [--timezone <identifier>] [--fallback-after 2700]
                            [--fallback-interval 300]
      brightness-relay source [--host <mini-host>] [--port 47777]
                              [--sync-mode live|scheduled] [--interval 1800] [--token-file <path>]
      brightness-relay send <0-100> [--host <host>] [--port 47777]
                             [--token-file <path>]
      brightness-relay solar-sample --latitude <degrees> --longitude <degrees>
                                    [--timezone <identifier>]

    SOURCE runs on the MacBook Air. RECEIVE runs on the Mac mini. Copy the same
    private token file to both Macs before starting them.
    """
}
