/// Recorded HTTP text with every secret in it marked.
///
/// The spans are kept sorted, inside the text and apart from each other, whatever order they were given in, so
/// showing the text never walks backwards.
public struct CoreHTTPMarkedText: Equatable, Sendable {
    /// The text's UTF-8 bytes, secrets included.
    public let bytes: [UInt8]

    /// The secret ranges, sorted by offset and not overlapping.
    public let spans: [CoreHTTPSecretSpan]

    /// Marks text.
    ///
    /// - Parameters:
    ///   - text: The text.
    ///   - spans: The secret ranges, in any order.
    public init(_ text: String, spans: [CoreHTTPSecretSpan] = []) {
        self.init(bytes: Array(text.utf8), spans: spans)
    }

    /// Marks bytes.
    ///
    /// Empty ranges are dropped, ranges are clipped to the text, and overlapping or touching ranges are merged,
    /// keeping the kind of the first.
    ///
    /// - Parameters:
    ///   - bytes: The text's bytes.
    ///   - spans: The secret ranges, in any order.
    public init(bytes: [UInt8], spans: [CoreHTTPSecretSpan]) {
        self.bytes = bytes
        self.spans = Self.normalized(spans, within: bytes.count)
    }

    /// Whether the text is empty.
    public var isEmpty: Bool {
        bytes.isEmpty
    }

    /// The text without its first bytes, with the spans moved to match.
    ///
    /// - Parameter count: How many bytes to drop.
    /// - Returns: The shorter text.
    public func dropping(prefix count: Int) -> CoreHTTPMarkedText {
        let cut = min(max(count, 0), bytes.count)
        let spans = spans.compactMap { span -> CoreHTTPSecretSpan? in
            let end = span.offset + span.length
            guard end > cut else {
                return nil
            }
            let start = max(span.offset, cut)
            return CoreHTTPSecretSpan(offset: start - cut, length: end - start, kind: span.kind)
        }
        return CoreHTTPMarkedText(bytes: Array(bytes[cut...]), spans: spans)
    }

    /// One secret's text.
    ///
    /// - Parameter index: The secret's index in ``spans``.
    /// - Returns: The secret.
    public func secret(_ index: Int) -> String {
        let span = spans[index]
        return Self.text(bytes[span.offset ..< span.offset + span.length])
    }

    /// The text with each secret revealed or masked.
    ///
    /// - Parameters:
    ///   - revealed: Whether the secret at an index is shown.
    ///   - mask: What stands in for a hidden secret.
    /// - Returns: The text.
    public func shown(revealing revealed: (Int) -> Bool, mask: (CoreHTTPSecretSpan) -> String) -> String {
        var text = ""
        var position = 0
        for (index, span) in spans.enumerated() {
            text += Self.text(bytes[position ..< span.offset])
            text += revealed(index)
                ? secret(index)
                : mask(span)
            position = span.offset + span.length
        }
        text += Self.text(bytes[position...])
        return text
    }

    /// The whole text, secrets included.
    public var plain: String {
        Self.text(bytes[...])
    }

    private static func text(_ slice: ArraySlice<UInt8>) -> String {
        String(bytes: slice, encoding: .utf8) ?? ""
    }

    private static func normalized(_ spans: [CoreHTTPSecretSpan], within size: Int) -> [CoreHTTPSecretSpan] {
        let clipped = spans.compactMap { span -> CoreHTTPSecretSpan? in
            guard span.offset >= 0, span.length > 0, span.offset < size else {
                return nil
            }
            return CoreHTTPSecretSpan(
                offset: span.offset,
                length: min(span.length, size - span.offset),
                kind: span.kind
            )
        }
        var merged: [CoreHTTPSecretSpan] = []
        for span in clipped.enumerated().sorted(by: { ($0.element.offset, $0.offset) < (
            $1.element.offset,
            $1.offset
        ) })
        .map(\.element) {
            guard let last = merged.last, span.offset <= last.offset + last.length else {
                merged.append(span)
                continue
            }
            let end = max(last.offset + last.length, span.offset + span.length)
            merged[merged.count - 1] = CoreHTTPSecretSpan(
                offset: last.offset,
                length: end - last.offset,
                kind: last.kind
            )
        }
        return merged
    }
}

/// A range of recorded HTTP text that holds a secret.
public struct CoreHTTPSecretSpan: Equatable, Hashable, Sendable {
    /// The offset of the secret's first byte.
    public let offset: Int

    /// How many bytes the secret covers.
    public let length: Int

    /// What the secret is.
    public let kind: CoreHTTPSecretKind

    /// Describes a span.
    ///
    /// - Parameters:
    ///   - offset: The offset of the first byte.
    ///   - length: How many bytes it covers.
    ///   - kind: What the secret is.
    public init(offset: Int, length: Int, kind: CoreHTTPSecretKind) {
        self.offset = offset
        self.length = length
        self.kind = kind
    }
}

/// What a marked secret in recorded HTTP text is.
public enum CoreHTTPSecretKind: Equatable, Hashable, Sendable {
    /// A credential.
    case credential

    /// A cookie.
    case cookie

    /// A session id.
    case session

    /// A query parameter.
    case parameter

    /// A form or JSON field.
    case field

    /// A whole body.
    case body
}
