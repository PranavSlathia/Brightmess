import BrightnessCore
import Darwin
import Foundation

protocol TVDiscoveryCancellation: AnyObject { func cancel() }

/// One bounded, ephemeral UDP client. No scan of addresses, TV action or daemon.
enum TVLANDiscovery {
    private final class Cancellation: TVDiscoveryCancellation, @unchecked Sendable {
        private let lock = NSLock()
        private var stopped = false
        func cancel() { lock.withLock { stopped = true } }
        var cancelled: Bool { lock.withLock { stopped } }
    }
    static func search(name: String, completion: @escaping ([String]) -> Void) -> any TVDiscoveryCancellation {
        let cancellation = Cancellation()
        DispatchQueue.global(qos:.utility).async {
            let hosts = discover(name:name,cancellation:cancellation)
            DispatchQueue.main.async { if !cancellation.cancelled { completion(hosts) } }
        }
        return cancellation
    }
    private static func discover(name: String, cancellation: Cancellation) -> [String] {
        let descriptor = socket(AF_INET,SOCK_DGRAM,IPPROTO_UDP)
        guard descriptor >= 0 else { return [] }
        defer { close(descriptor) }
        var enabled: Int32 = 1
        guard setsockopt(descriptor,SOL_SOCKET,SO_BROADCAST,&enabled,socklen_t(MemoryLayout.size(ofValue:enabled))) == 0 else { return [] }
        var local = sockaddr_in(); local.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        local.sin_family = sa_family_t(AF_INET); local.sin_port = 0; local.sin_addr.s_addr = INADDR_ANY
        let bound = withUnsafePointer(to:&local) { $0.withMemoryRebound(to:sockaddr.self,capacity:1) { bind(descriptor,$0,socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard bound == 0 else { return [] }
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0 else { return [] }
        defer { freeifaddrs(interfaces) }
        let packet = TCLDiscovery.request(clientID:UUID().uuidString,milliseconds:Int64(Date().timeIntervalSince1970*1000))
        var sent = Set<UInt32>(), item = interfaces
        while let current = item {
            defer { item = current.pointee.ifa_next }
            let info = current.pointee
            guard info.ifa_flags & UInt32(IFF_UP|IFF_BROADCAST) == UInt32(IFF_UP|IFF_BROADCAST),
                  info.ifa_flags & UInt32(IFF_LOOPBACK|IFF_POINTOPOINT) == 0,
                  let address = info.ifa_dstaddr, address.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            var destination = address.withMemoryRebound(to:sockaddr_in.self,capacity:1) { $0.pointee }
            guard sent.insert(destination.sin_addr.s_addr).inserted else { continue }
            destination.sin_port = UInt16(6537).bigEndian
            _ = packet.withUnsafeBytes { bytes in
                withUnsafePointer(to:&destination) { $0.withMemoryRebound(to:sockaddr.self,capacity:1) {
                    sendto(descriptor,bytes.baseAddress,bytes.count,0,$0,socklen_t(MemoryLayout<sockaddr_in>.size))
                } }
            }
        }
        guard !sent.isEmpty else { return [] }
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        var found = Set<String>()
        while !cancellation.cancelled && ProcessInfo.processInfo.systemUptime < deadline && found.count < 8 {
            var wait = pollfd(fd:descriptor,events:Int16(POLLIN),revents:0)
            guard poll(&wait,1,100) > 0 else { continue }
            var buffer = [UInt8](repeating:0,count:16385), source = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to:&source) { $0.withMemoryRebound(to:sockaddr.self,capacity:1) {
                recvfrom(descriptor,&buffer,buffer.count,0,$0,&length)
            } }
            guard count > 0, count <= 16384 else { continue }
            var host = [CChar](repeating:0,count:Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET,&source.sin_addr,&host,socklen_t(host.count)) != nil else { continue }
            if let candidate = TCLDiscovery.candidate(Data(buffer.prefix(count)),expectedName:name,host:String(cString:host)) { found.insert(candidate) }
        }
        return found.sorted()
    }
}
