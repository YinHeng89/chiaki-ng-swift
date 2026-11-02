import ChiakiBridge
import Foundation

extension Data {
    /// Copies the core's bytes straight from the vector's contiguous storage, without reading the vector as a
    /// Swift `Sequence`.
    ///
    /// - Parameter bytes: The bytes the core returned.
    init(_ bytes: chiaki_bridge.Bytes) {
        let count = bytes.size()
        guard count > 0, let start = bytes.__dataUnsafe() else {
            self.init()
            return
        }
        self.init(bytes: start, count: count)
    }

    /// Copies the core's bytes, or reads an empty vector as no value.
    ///
    /// - Parameter bytes: The bytes the core returned.
    init?(nonEmpty bytes: chiaki_bridge.Bytes) {
        guard !bytes.isEmpty else {
            return nil
        }
        self.init(bytes)
    }
}
