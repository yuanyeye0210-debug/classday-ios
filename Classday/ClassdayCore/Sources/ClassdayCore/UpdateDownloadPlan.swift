import Foundation

/// The download plan for one `ReleaseEntry`: which URLs to try, in order,
/// how to retry each one, where to resume a partial download, and how to
/// verify the finished file. Pure value type — the actual download (Task 6)
/// consumes this plan; it performs no I/O itself.
///
/// SHA-256 is a portable pure-Swift implementation in this file (FIPS 180-4).
/// `Package.swift` has no CryptoKit/swift-crypto dependency and Linux has no
/// CryptoKit, so `import CryptoKit` would not compile here. This is the
/// single SHA-256 implementation for the whole feature — Task 6 reuses
/// `sha256Matches(data:expected:)`; do not add a second one anywhere.
public struct UpdateDownloadPlan: Equatable, Sendable {
    /// Attempts per candidate URL before moving to the next candidate.
    public static let maxAttemptsPerURL = 3

    /// Per-request timeout, in seconds, for each download attempt.
    public static let timeoutSeconds = 60

    public let release: ReleaseEntry

    /// Candidate URLs in try order: the release's `download_url` first,
    /// then its `mirrors` in manifest order.
    public let candidates: [URL]

    public init(release: ReleaseEntry) {
        self.release = release
        var candidates = [release.downloadURL]
        for mirror in release.mirrors ?? [] {
            // A malformed mirror string is skipped: it must not break the
            // `download_url` candidate or drop a later valid mirror. A
            // string is only a usable candidate if it parses as an absolute
            // URL with a non-empty scheme and host — a schemeless string
            // parses as a relative URL, which can never be downloaded.
            // Non-empty matters, not just non-nil: Darwin's URL parser is
            // lenient about "://bad" — it returns a URL with an empty
            // scheme ("") and host "bad" (Linux returns nil for it), so a
            // `!= nil` check alone lets it through (CI run 43245109637).
            guard let url = URL(string: mirror),
                  let scheme = url.scheme, !scheme.isEmpty,
                  let host = url.host, !host.isEmpty else {
                continue
            }
            candidates.append(url)
        }
        self.candidates = candidates
    }

    /// Backoff before retry attempt `attempt` (1-based), in seconds:
    /// 1 s, 2 s, 4 s, doubling thereafter. Attempts beyond
    /// `maxAttemptsPerURL` never occur in practice; the doubling continues
    /// so the function stays total. Attempt 0 or below means "no retry
    /// yet", so the backoff is 0.
    public static func backoffSeconds(forAttempt attempt: Int) -> Int {
        guard attempt >= 1 else { return 0 }
        return 1 << (attempt - 1)
    }

    /// Byte offset to resume from, given a partial file of `partialSize`
    /// bytes and an expected total of `expectedSize` bytes: the partial
    /// size itself, unless the partial is larger than expected (corrupt or
    /// from another file), in which case 0 — the caller discards it and
    /// restarts (see `shouldDiscardPartial`). A partial exactly the
    /// expected size resumes at the end (zero bytes remain); the caller
    /// then verifies it by hash.
    public static func resumeOffset(partialSize: Int, expectedSize: Int) -> Int {
        guard partialSize > 0, partialSize <= expectedSize else { return 0 }
        return partialSize
    }

    /// Whether a partial file of `partialSize` bytes must be discarded
    /// rather than resumed: only when it is larger than `expectedSize`.
    public static func shouldDiscardPartial(partialSize: Int, expectedSize: Int) -> Bool {
        partialSize > expectedSize
    }

    /// Whether `data` hashes to the expected SHA-256 hex digest (from the
    /// manifest's `sha256`). The comparison is case-insensitive on the hex.
    public static func sha256Matches(data: Data, expected: String) -> Bool {
        sha256Hex(data) == expected.lowercased()
    }

    /// Lowercase hex SHA-256 digest of `data`.
    public static func sha256Hex(_ data: Data) -> String {
        // Manual hex conversion (no String(format:) varargs) so the digest
        // is identical on Apple platforms and Linux.
        let digits = Array("0123456789abcdef")
        var hex = ""
        hex.reserveCapacity(64)
        for byte in SHA256Digest.hash(data) {
            hex.append(digits[Int(byte >> 4)])
            hex.append(digits[Int(byte & 0x0f)])
        }
        return hex
    }
}

/// Portable pure-Swift SHA-256 (FIPS 180-4). No CryptoKit dependency, so it
/// compiles on Linux CI as well as on Apple platforms. Verified against the
/// standard vectors in `UpdateDownloadPlanTests` ("abc", empty input, and
/// the 56-byte message that spills padding into a second block).
private enum SHA256Digest {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    private static func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 {
        (x >> n) | (x << (32 - n))
    }

    static func hash(_ data: Data) -> [UInt8] {
        var h: [UInt32] = [
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
            0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
        ]

        // Padding: 0x80, then zeros until length is 56 mod 64, then the
        // 8-byte big-endian bit length.
        var message = [UInt8](data)
        let bitLength = UInt64(data.count) * 8
        message.append(0x80)
        while message.count % 64 != 56 {
            message.append(0)
        }
        for i in (0..<8).reversed() {
            message.append(UInt8((bitLength >> (i * 8)) & 0xff))
        }

        for chunkStart in stride(from: 0, to: message.count, by: 64) {
            var w = [UInt32](repeating: 0, count: 64)
            for i in 0..<16 {
                let o = chunkStart + i * 4
                w[i] = (UInt32(message[o]) << 24)
                    | (UInt32(message[o + 1]) << 16)
                    | (UInt32(message[o + 2]) << 8)
                    | UInt32(message[o + 3])
            }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }

            var a = h[0], b = h[1], c = h[2], d = h[3]
            var e = h[4], f = h[5], g = h[6], hh = h[7]
            for i in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ (~e & g)
                let temp1 = hh &+ s1 &+ ch &+ k[i] &+ w[i]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = s0 &+ maj
                hh = g
                g = f
                f = e
                e = d &+ temp1
                d = c
                c = b
                b = a
                a = temp1 &+ temp2
            }
            h[0] = h[0] &+ a
            h[1] = h[1] &+ b
            h[2] = h[2] &+ c
            h[3] = h[3] &+ d
            h[4] = h[4] &+ e
            h[5] = h[5] &+ f
            h[6] = h[6] &+ g
            h[7] = h[7] &+ hh
        }

        var digest = [UInt8]()
        digest.reserveCapacity(32)
        for word in h {
            digest.append(UInt8((word >> 24) & 0xff))
            digest.append(UInt8((word >> 16) & 0xff))
            digest.append(UInt8((word >> 8) & 0xff))
            digest.append(UInt8(word & 0xff))
        }
        return digest
    }
}
