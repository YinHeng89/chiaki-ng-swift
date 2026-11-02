import Foundation

/// A move-only buffer of secret bytes that wipes itself when it is destroyed.
///
/// Credentials, tokens, pairing keys and PINs live in a ``SecretBytes`` from the moment they are read until
/// the moment they are no longer needed. The value cannot be copied, so exactly one buffer holds the secret,
/// and its `deinit` overwrites that buffer with zeros through ``SecretBytes/wipe(_:)`` before freeing it.
/// The bytes are reachable only inside ``withUnsafeBytes(_:)`` and ``withUnsafeCString(_:)``, and the type
/// cannot be interpolated into a string; ``description`` is always redacted.
///
/// The buffer always keeps one extra zero byte after the secret, so ``withUnsafeCString(_:)`` needs no copy.
public struct SecretBytes: ~Copyable, @unchecked Sendable {
    private let storage: UnsafeMutableRawBufferPointer

    /// The number of secret bytes, not counting the terminating zero byte.
    public let count: Int

    /// Creates a secret by letting a closure write its bytes straight into the wiping buffer.
    ///
    /// The buffer starts zeroed. If `body` throws, the buffer is wiped and freed before the error propagates.
    ///
    /// - Parameters:
    ///   - count: The number of secret bytes.
    ///   - body: Writes the secret into the buffer it is given, which holds exactly `count` bytes.
    /// - Throws: The error `body` throws.
    public init<Failure: Error>(
        count: Int,
        initializingWith body: (UnsafeMutableRawBufferPointer) throws(Failure) -> Void
    ) throws(Failure) {
        precondition(count >= 0, "A secret cannot have a negative length")
        let storage = UnsafeMutableRawBufferPointer.allocate(
            byteCount: count + 1,
            alignment: MemoryLayout<UInt8>.alignment
        )
        storage.initializeMemory(as: UInt8.self, repeating: 0)
        do {
            try body(UnsafeMutableRawBufferPointer(rebasing: storage[0 ..< count]))
        } catch {
            Self.wipe(storage)
            storage.deallocate()
            throw error
        }
        self.storage = storage
        self.count = count
    }

    /// Takes a secret out of a byte array and wipes the array.
    ///
    /// The array's own buffer is overwritten with zeros after the bytes are copied. Copies of the array made
    /// earlier share or own other buffers that this initialiser cannot reach, so pass the only copy.
    ///
    /// - Parameter source: The secret bytes. On return every element is zero.
    public init(wiping source: inout [UInt8]) {
        let count = source.count
        self.init(count: count) { (buffer: UnsafeMutableRawBufferPointer) in
            source.withUnsafeMutableBytes { bytes in
                buffer.copyMemory(from: UnsafeRawBufferPointer(bytes))
                Self.wipe(bytes)
            }
        }
    }

    /// Takes a secret out of `Data` and wipes the data.
    ///
    /// The data's own buffer is overwritten with zeros after the bytes are copied. Copies of the data made
    /// earlier share or own other buffers that this initialiser cannot reach, so pass the only copy.
    ///
    /// - Parameter source: The secret bytes. On return every byte is zero.
    public init(wiping source: inout Data) {
        let count = source.count
        self.init(count: count) { (buffer: UnsafeMutableRawBufferPointer) in
            source.withUnsafeMutableBytes { bytes in
                buffer.copyMemory(from: UnsafeRawBufferPointer(bytes))
                Self.wipe(bytes)
            }
        }
    }

    deinit {
        Self.wipe(storage)
        storage.deallocate()
    }

    /// Makes a second, independent copy of the secret in its own wiping buffer.
    ///
    /// This is the only way to duplicate a secret, so every copy is visible where it is made.
    ///
    /// - Returns: A secret holding the same bytes, wiped when it is destroyed independently of this one.
    public func clone() -> SecretBytes {
        withUnsafeBytes { source in
            SecretBytes(count: source.count) { buffer in
                buffer.copyMemory(from: source)
            }
        }
    }

    /// Whether the secret has no bytes.
    public var isEmpty: Bool {
        count == 0
    }

    /// A fixed redacted text that never reveals the secret or its length.
    public var description: String {
        "SecretBytes(<redacted>)"
    }

    /// Lends the secret bytes to a closure.
    ///
    /// The pointer is valid only for the duration of `body` and must not escape it.
    ///
    /// - Parameter body: Reads the secret, which holds exactly ``count`` bytes.
    /// - Returns: What `body` returns.
    /// - Throws: The error `body` throws.
    public func withUnsafeBytes<Result: ~Copyable, Failure: Error>(
        _ body: (UnsafeRawBufferPointer) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        try body(UnsafeRawBufferPointer(rebasing: storage[0 ..< count]))
    }

    /// Lends the secret to a closure as a NUL-terminated C string.
    ///
    /// The terminator is the zero byte the buffer always keeps after the secret, so nothing is copied. A
    /// secret that contains a zero byte appears truncated to C code.
    ///
    /// - Parameter body: Reads the C string. The pointer is valid only for the duration of `body`.
    /// - Returns: What `body` returns.
    /// - Throws: The error `body` throws.
    public func withUnsafeCString<Result: ~Copyable, Failure: Error>(
        _ body: (UnsafePointer<CChar>) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        guard let base = storage.baseAddress else {
            preconditionFailure("A secret buffer always holds its terminating zero byte")
        }
        return try body(UnsafePointer(base.assumingMemoryBound(to: CChar.self)))
    }

    /// Compares two secrets in time that depends only on their lengths, not on where they first differ.
    ///
    /// - Parameter other: The secret to compare with.
    /// - Returns: `true` when both secrets hold the same bytes.
    public func isEqual(to other: borrowing SecretBytes) -> Bool {
        guard count == other.count else {
            return false
        }
        return withUnsafeBytes { mine in
            other.withUnsafeBytes { theirs in
                zip(mine, theirs).reduce(UInt8(0)) { difference, pair in
                    difference | (pair.0 ^ pair.1)
                } == 0
            }
        }
    }

    /// Overwrites memory with zeros in a way the optimiser cannot remove.
    ///
    /// This is the one secure-zero primitive; every wipe of secret material goes through it.
    ///
    /// - Parameter buffer: The memory to overwrite. An empty buffer is left alone.
    public static func wipe(_ buffer: UnsafeMutableRawBufferPointer) {
        guard let base = buffer.baseAddress, buffer.count > 0 else {
            return
        }
        let status = memset_s(base, buffer.count, 0, buffer.count)
        precondition(status == 0, "memset_s refused to wipe secret memory")
    }
}
