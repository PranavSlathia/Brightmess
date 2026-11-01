import BrightnessCore
import BrightnessHardware
import Foundation
import Network

enum HTTPRelayError: Error, CustomStringConvertible {
    case invalidPort
    case invalidResponse
    case rejected(Int, String)
    case malformedRequest
    case payloadTooLarge

    var description: String {
        switch self {
        case .invalidPort:
            return "The relay port is invalid."
        case .invalidResponse:
            return "The receiver returned an invalid response."
        case let .rejected(status, message):
            return "The receiver rejected the update (HTTP \(status)): \(message)"
        case .malformedRequest:
            return "The HTTP request is malformed."
        case .payloadTooLarge:
            return "The HTTP request is too large."
        }
    }
}

struct RelayClient {
    let brightnessEndpoint: URL
    let pullEndpoint: URL
    let controlEndpoint: URL
    let authenticator: RelayAuthenticator

    init(host: String, port: UInt16, authenticator: RelayAuthenticator) throws {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = Int(port)
        components.path = "/v1/brightness"
        guard let brightnessEndpoint = components.url else {
            throw HTTPRelayError.invalidPort
        }
        components.path = "/v1/pull/await"
        guard let pullEndpoint = components.url else {
            throw HTTPRelayError.invalidPort
        }
        components.path = "/v1/control"
        guard let controlEndpoint = components.url else {
            throw HTTPRelayError.invalidPort
        }
        self.brightnessEndpoint = brightnessEndpoint
        self.pullEndpoint = pullEndpoint
        self.controlEndpoint = controlEndpoint
        self.authenticator = authenticator
    }

    func send(brightness: Double, source: String, ambient: AmbientSample? = nil) async throws {
        let envelope = try BrightnessEnvelope(brightness: brightness, source: source, ambient: ambient)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let body = try encoder.encode(envelope)

        var request = URLRequest(url: brightnessEndpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authenticator.signature(for: body), forHTTPHeaderField: "X-Brightness-Signature")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPRelayError.invalidResponse
        }
        guard httpResponse.statusCode == 204 else {
            let message = String(data: data, encoding: .utf8) ?? "unknown error"
            throw HTTPRelayError.rejected(httpResponse.statusCode, message)
        }
    }

    func awaitPull(source: String) async throws -> Bool {
        let envelope = try PullWaitEnvelope(source: source)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let body = try encoder.encode(envelope)

        var request = URLRequest(url: pullEndpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 35
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authenticator.signature(for: body), forHTTPHeaderField: "X-Brightness-Signature")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPRelayError.invalidResponse
        }
        switch httpResponse.statusCode {
        case 200:
            return true
        case 204:
            return false
        default:
            let message = String(data: data, encoding: .utf8) ?? "unknown error"
            throw HTTPRelayError.rejected(httpResponse.statusCode, message)
        }
    }

    func sendControl(_ action: RelayControlAction, displayID: String? = nil,
                     value: Double? = nil) async throws {
        let envelope = try PullWaitEnvelope(source: action.rawValue, displayID: displayID, value: value)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let body = try encoder.encode(envelope)
        let endpoint = controlEndpoint.appendingPathComponent(action.rawValue)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 4
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authenticator.signature(for: body), forHTTPHeaderField: "X-Brightness-Signature")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPRelayError.invalidResponse
        }
        guard httpResponse.statusCode == 204 else {
            let message = String(data: data, encoding: .utf8) ?? "unknown error"
            throw HTTPRelayError.rejected(httpResponse.statusCode, message)
        }
    }

    func sendAmbient(_ ambient: AmbientSample, source: String) async throws {
        let body = try JSONEncoder().encode(AmbientEnvelope(source: source, ambient: ambient))
        var request = URLRequest(url: brightnessEndpoint.deletingLastPathComponent()
            .appendingPathComponent("ambient"))
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 8
        request.setValue(authenticator.signature(for: body), forHTTPHeaderField: "X-Brightness-Signature")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HTTPRelayError.invalidResponse }
        guard http.statusCode == 204 else {
            throw HTTPRelayError.rejected(http.statusCode, String(decoding: data, as: UTF8.self))
        }
    }

    func status() async throws -> String {
        let body = try JSONEncoder().encode(PullWaitEnvelope(source: "status"))
        var request = URLRequest(url: controlEndpoint.appendingPathComponent("status"))
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 8
        request.setValue(authenticator.signature(for: body), forHTTPHeaderField: "X-Brightness-Signature")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw HTTPRelayError.invalidResponse }
        return String(decoding: data, as: UTF8.self)
    }
}

enum RelayControlAction: String, Sendable {
    case showMenu = "show-menu"
    case wakeAll = "wake-all"
    case syncNow = "sync-now"
    case setColor = "set-color"
    case setConnection = "set-connection"
    case enableKeys = "enable-keys"
}

struct AppliedBrightnessStatus: Sendable {
    let source: String
    let sourceBrightness: Double
    let displayBrightness: UInt16
    let appliedAt: Date
    let wroteHardware: Bool
    let changedDisplays: Int
}

final class RelayHTTPServer {
    private static let maximumRequestBytes = 16 * 1024

    private let listener: NWListener
    private let queue = DispatchQueue(label: "dev.pranav.brightness-relay.receiver")
    private let authenticator: RelayAuthenticator
    let displayCoordinator: DisplayCoordinator
    private let curve: BrightnessCurve
    private let deadband: UInt16
    private let solarFallback: SolarFallbackConfiguration?
    private var onApplied: ((AppliedBrightnessStatus) -> Void)?
    private var onControl: ((RelayControlAction, PullWaitEnvelope) -> Void)?
    private var onAmbient: ((AmbientSample?, String, Date) -> Void)?
    private var uiStatusProvider: (() -> [String: Any])?
    private var onListenerFailure: ((Error) -> Void)?
    private var startupCompletion: ((Error?) -> Void)?
    private var replayGuard = ReplayGuard()
    private var lastBrightness: UInt16?
    private var lastRemoteUpdateAt: Date?
    private var lastRemoteSource: String?
    private var lastAmbient: AmbientSample?
    private var pullWaiters: [UUID: NWConnection] = [:]
    private var pendingPullUntil: Date?
    private var fallbackTimer: DispatchSourceTimer?

    init(
        port: UInt16,
        authenticator: RelayAuthenticator,
        displayCoordinator: DisplayCoordinator,
        curve: BrightnessCurve,
        deadband: UInt16 = 2,
        solarFallback: SolarFallbackConfiguration? = nil,
        onApplied: ((AppliedBrightnessStatus) -> Void)? = nil
    ) throws {
        guard let networkPort = NWEndpoint.Port(rawValue: port) else {
            throw HTTPRelayError.invalidPort
        }
        self.listener = try NWListener(using: .tcp, on: networkPort)
        self.authenticator = authenticator
        self.displayCoordinator = displayCoordinator
        self.curve = curve
        self.deadband = deadband
        self.solarFallback = solarFallback
        self.onApplied = onApplied
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            start { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func start(completion: @escaping (Error?) -> Void) {
        startupCompletion = completion
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                guard let completion = self.startupCompletion else { return }
                self.startupCompletion = nil
                self.displayCoordinator.refresh()
                self.startFallbackTimer()
                self.requestRefresh()
                completion(nil)
            case let .failed(error):
                if let completion = self.startupCompletion {
                    self.startupCompletion = nil
                    completion(error)
                } else {
                    RelayLog.write("Menu receiver failed after startup: \(error)")
                    self.onListenerFailure?(error)
                }
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
    }

    func setOnApplied(_ handler: @escaping (AppliedBrightnessStatus) -> Void) {
        onApplied = handler
    }

    func setOnControl(_ handler: @escaping (RelayControlAction, PullWaitEnvelope) -> Void) {
        onControl = handler
    }

    func setOnAmbient(_ handler: @escaping (AmbientSample?, String, Date) -> Void) {
        onAmbient = handler
    }

    func setUIStatusProvider(_ provider: @escaping () -> [String: Any]) {
        uiStatusProvider = provider
    }

    func setOnListenerFailure(_ handler: @escaping (Error) -> Void) {
        onListenerFailure = handler
    }

    func requestRefresh() {
        queue.async { [weak self] in
            guard let self else { return }
            let waiters = Array(self.pullWaiters.values)
            self.pullWaiters.removeAll()
            if waiters.isEmpty {
                self.pendingPullUntil = Date().addingTimeInterval(60)
            } else {
                self.pendingPullUntil = nil
                for connection in waiters {
                    self.respond(to: connection, status: 200, message: "sampleNow")
                }
            }
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer initialBuffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var buffer = initialBuffer
            if let data {
                buffer.append(data)
            }
            if buffer.count > Self.maximumRequestBytes {
                self.respond(to: connection, status: 413, message: "payload too large")
                return
            }
            do {
                if let request = try self.parseRequest(buffer) {
                    self.handle(request, on: connection)
                    return
                }
            } catch {
                self.respond(to: connection, status: 400, message: "malformed request")
                return
            }
            if isComplete || error != nil {
                self.respond(to: connection, status: 400, message: "malformed request")
                return
            }
            self.receive(on: connection, buffer: buffer)
        }
    }

    private struct Request {
        let path: String
        let body: Data
        let signature: String
    }

    private func parseRequest(_ data: Data) throws -> Request? {
        let separator = Data("\r\n\r\n".utf8)
        guard let boundary = data.range(of: separator) else { return nil }
        let headerData = data[..<boundary.lowerBound]
        guard let headers = String(data: headerData, encoding: .utf8) else {
            throw HTTPRelayError.malformedRequest
        }

        let lines = headers.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            throw HTTPRelayError.malformedRequest
        }
        let requestParts = requestLine.split(separator: " ").map(String.init)
        guard requestParts.count == 3,
              requestParts[0] == "POST",
              requestParts[2] == "HTTP/1.1",
              [
                  "/v1/brightness",
                  "/v1/ambient",
                  "/v1/pull/await",
                  "/v1/control/show-menu",
                  "/v1/control/wake-all",
                  "/v1/control/sync-now",
                  "/v1/control/status",
                  "/v1/control/set-color",
                  "/v1/control/set-connection",
                  "/v1/control/enable-keys",
              ].contains(requestParts[1])
        else {
            throw HTTPRelayError.malformedRequest
        }

        var contentLength: Int?
        var signature: String?
        for line in lines.dropFirst() {
            let pair = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { continue }
            let name = pair[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = pair[1].trimmingCharacters(in: .whitespaces)
            if name == "content-length" {
                contentLength = Int(value)
            } else if name == "x-brightness-signature" {
                signature = value
            }
        }

        guard let contentLength,
              contentLength >= 0,
              contentLength <= Self.maximumRequestBytes,
              let signature
        else {
            throw HTTPRelayError.malformedRequest
        }
        let bodyStart = boundary.upperBound
        guard contentLength <= data.count - bodyStart else { return nil }
        let body = data.subdata(in: bodyStart ..< bodyStart + contentLength)
        return Request(path: requestParts[1], body: body, signature: signature)
    }

    private func handle(_ request: Request, on connection: NWConnection) {
        guard authenticator.verify(signature: request.signature, body: request.body) else {
            respond(to: connection, status: 401, message: "invalid signature")
            return
        }

        switch request.path {
        case "/v1/ambient":
            do {
                let envelope = try JSONDecoder().decode(AmbientEnvelope.self, from: request.body)
                guard !envelope.source.isEmpty else { throw RelayProtocolError.invalidEnvelope }
                try replayGuard.validate(envelope)
                lastAmbient = envelope.ambient
                onAmbient?(envelope.ambient, envelope.source, Date())
                respond(to: connection, status: 204, message: "")
            } catch {
                respond(to: connection, status: 400, message: String(describing: error))
            }
        case "/v1/brightness":
            handleBrightness(request, on: connection)
        case "/v1/pull/await":
            handlePullWait(request, on: connection)
        case "/v1/control/show-menu":
            handleControl(.showMenu, request: request, on: connection)
        case "/v1/control/wake-all":
            handleControl(.wakeAll, request: request, on: connection)
        case "/v1/control/sync-now":
            handleControl(.syncNow, request: request, on: connection)
        case "/v1/control/set-color":
            handleControl(.setColor, request: request, on: connection)
        case "/v1/control/set-connection":
            handleControl(.setConnection, request: request, on: connection)
        case "/v1/control/enable-keys":
            handleControl(.enableKeys, request: request, on: connection)
        case "/v1/control/status":
            do {
                let envelope = try JSONDecoder().decode(PullWaitEnvelope.self, from: request.body)
                guard envelope.source == "status" else { throw RelayProtocolError.invalidEnvelope }
                try replayGuard.validate(envelope)
                let displays: [[String: Any]] = displayCoordinator.snapshot().map {
                    ["id": $0.id, "name": $0.display.name,
                     "connected": $0.connectionState.isConnected,
                     "brightness": $0.brightness.map { Int($0) } as Any? ?? NSNull(),
                     "automatic": $0.followsAutomatic,
                     "error": $0.lastError as Any? ?? NSNull(),
                     "method": $0.controlMethod.rawValue]
                }
                var status: [String: Any] = [
                    "version": "0.7.0", "displays": displays,
                    "airSource": lastRemoteSource as Any? ?? NSNull(),
                    "airReadingAgeSeconds": lastRemoteUpdateAt.map { Date().timeIntervalSince($0) } as Any? ?? NSNull(),
                    "pullConnections": pullWaiters.count,
                ]
                if let lastAmbient,
                   let object = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(lastAmbient)) {
                    status["ambient"] = object
                }
                if let provider = uiStatusProvider {
                    status["controls"] = DispatchQueue.main.sync { provider() }
                }
                let data = try JSONSerialization.data(withJSONObject: status, options: [.prettyPrinted, .sortedKeys])
                respond(to: connection, status: 200, message: String(decoding: data, as: UTF8.self))
            } catch {
                respond(to: connection, status: 400, message: String(describing: error))
            }
        default:
            respond(to: connection, status: 404, message: "not found")
        }
    }

    private func handleControl(
        _ action: RelayControlAction,
        request: Request,
        on connection: NWConnection
    ) {
        do {
            let envelope = try JSONDecoder().decode(PullWaitEnvelope.self, from: request.body)
            guard envelope.source == action.rawValue else {
                throw RelayProtocolError.invalidEnvelope
            }
            try replayGuard.validate(envelope)
            if action == .setColor {
                guard envelope.displayID != nil, let value = envelope.value,
                      value.isFinite, value == -1 || value == 0 || (3500...7500).contains(value) else {
                    throw RelayProtocolError.invalidEnvelope
                }
            }
            if action == .setConnection {
                guard envelope.displayID != nil, envelope.value == 0 || envelope.value == 1 else {
                    throw RelayProtocolError.invalidEnvelope
                }
            }
            RelayLog.write("Accepted authenticated control request: \(action.rawValue)")
            if action == .syncNow { requestRefresh() }
            onControl?(action, envelope)
            respond(to: connection, status: 204, message: "")
        } catch RelayProtocolError.replayedEnvelope {
            respond(to: connection, status: 409, message: "replayed control")
        } catch RelayProtocolError.staleEnvelope {
            respond(to: connection, status: 408, message: "stale control")
        } catch {
            respond(to: connection, status: 400, message: String(describing: error))
        }
    }

    private func handleBrightness(_ request: Request, on connection: NWConnection) {
        do {
            let envelope = try JSONDecoder().decode(BrightnessEnvelope.self, from: request.body)
            guard envelope.brightness.isFinite, (0 ... 1).contains(envelope.brightness) else {
                throw RelayProtocolError.invalidEnvelope
            }
            try replayGuard.validate(envelope)
            lastRemoteUpdateAt = Date()
            lastRemoteSource = envelope.source
            lastAmbient = envelope.ambient
            onAmbient?(envelope.ambient, envelope.source, Date())
            try applyBrightness(envelope.brightness, source: envelope.source, calibrationSource: envelope.brightness)
            respond(to: connection, status: 204, message: "")
        } catch RelayProtocolError.replayedEnvelope {
            respond(to: connection, status: 409, message: "replayed update")
        } catch RelayProtocolError.staleEnvelope {
            respond(to: connection, status: 408, message: "stale update")
        } catch {
            respond(to: connection, status: 400, message: String(describing: error))
        }
    }

    private func startFallbackTimer() {
        guard fallbackTimer == nil, let solarFallback else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let startupGrace = min(solarFallback.staleAfter, 45)
        timer.schedule(deadline: .now() + startupGrace, repeating: solarFallback.updateInterval)
        timer.setEventHandler { [weak self] in
            self?.applySolarFallbackIfNeeded(at: Date())
        }
        fallbackTimer = timer
        timer.resume()
    }

    private func applySolarFallbackIfNeeded(at date: Date) {
        guard let solarFallback else { return }
        if let lastRemoteUpdateAt,
           date.timeIntervalSince(lastRemoteUpdateAt) < solarFallback.staleAfter
        {
            return
        }

        do {
            let normalized = solarFallback.normalizedBrightness(at: date)
            try applyBrightness(normalized, source: "solar-fallback")
        } catch {
            RelayLog.write("Solar fallback failed: \(error)")
        }
    }

    private func applyBrightness(_ normalized: Double, source: String, calibrationSource: Double? = nil) throws {
        let target = curve.map(normalized: normalized)
        let summary = try displayCoordinator.applyAutomatic(target: target, deadband: deadband,
                                                           sourceBrightness: calibrationSource)
        lastBrightness = target
        let wroteHardware = summary.hardwareWrites > 0
        if summary.changedDisplays == 0 {
            RelayLog.write("No automatic display change needed at \(target)% from \(source)")
        } else {
            RelayLog.write(
                "Applied \(target)% from \(source) to \(summary.changedDisplays) display(s) " +
                    "(DDC \(summary.hardwareWrites), software \(summary.softwareWrites))"
            )
        }

        onApplied?(
            AppliedBrightnessStatus(
                source: source,
                sourceBrightness: normalized,
                displayBrightness: lastBrightness ?? target,
                appliedAt: Date(),
                wroteHardware: wroteHardware,
                changedDisplays: summary.changedDisplays
            )
        )
    }

    private func handlePullWait(_ request: Request, on connection: NWConnection) {
        do {
            let envelope = try JSONDecoder().decode(PullWaitEnvelope.self, from: request.body)
            try replayGuard.validate(envelope)

            if let pendingPullUntil, pendingPullUntil >= Date() {
                self.pendingPullUntil = nil
                respond(to: connection, status: 200, message: "sampleNow")
                return
            }
            pendingPullUntil = nil

            let waiterID = UUID()
            pullWaiters[waiterID] = connection
            queue.asyncAfter(deadline: .now() + 25) { [weak self] in
                guard let self, let timedOutConnection = self.pullWaiters.removeValue(forKey: waiterID) else {
                    return
                }
                self.respond(to: timedOutConnection, status: 204, message: "")
            }
        } catch RelayProtocolError.replayedEnvelope {
            respond(to: connection, status: 409, message: "replayed update")
        } catch RelayProtocolError.staleEnvelope {
            respond(to: connection, status: 408, message: "stale update")
        } catch {
            respond(to: connection, status: 400, message: String(describing: error))
        }
    }

    private func respond(to connection: NWConnection, status: Int, message: String) {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 204: reason = "No Content"
        case 400: reason = "Bad Request"
        case 401: reason = "Unauthorized"
        case 408: reason = "Request Timeout"
        case 409: reason = "Conflict"
        case 413: reason = "Content Too Large"
        case 404: reason = "Not Found"
        default: reason = "Error"
        }
        let body = status == 204 ? "" : message
        let response = "HTTP/1.1 \(status) \(reason)\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
