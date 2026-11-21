import Foundation

/// Shared networking helpers for the TweakKit server modules.
/// This target is internal to the package and is not shipped as a product.
public enum NetworkAddress {
    /// Best-effort lookup of this device's LAN IPv4 address.
    /// Prefers `en0` (Wi-Fi on iOS, primary interface on most Macs), then any other
    /// active, non-loopback interface.
    public static func lanIPv4Address() -> String? {
        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPointer) == 0, let first = ifaddrPointer else {
            return nil
        }
        defer { freeifaddrs(ifaddrPointer) }

        var candidates: [(name: String, address: String)] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            let flags = Int32(entry.ifa_flags)
            guard let addr = entry.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0,
                  flags & IFF_LOOPBACK == 0 else {
                continue
            }
            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                addr,
                socklen_t(addr.pointee.sa_len),
                &hostBuffer,
                socklen_t(hostBuffer.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else {
                continue
            }
            candidates.append((String(cString: entry.ifa_name), String(cString: hostBuffer)))
        }

        return candidates.first(where: { $0.name == "en0" })?.address ?? candidates.first?.address
    }
}
