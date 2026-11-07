import Foundation

/// The Kakusan media pacing limits a host can tune; every value is clamped to its field's range.
public struct KakusanMediaTuning: Equatable, Sendable, Codable {
    /// One tunable value; the raw value is its stored key.
    public enum Field: String, CaseIterable, Sendable {
        /// The shortest time a packet may wait in the send queue.
        case queueAgeMinimumMs

        /// The longest time a packet may wait in the send queue.
        case queueAgeMaximumMs

        /// The queue wait as a multiple of the round trip.
        case queueAgeRoundTrips

        /// How long start-up is spared from shedding.
        case startupGraceMs

        /// How long heavy shedding may last before the session ends.
        case dropSecondsToEnd

        /// How long to wait for an acknowledgement.
        case acknowledgementTimeoutMs

        /// The send queue size in kilobytes.
        case queueKilobytes

        /// The send queue size in packets.
        case queuePackets

        /// The shortest gap between keyframes.
        case keyframeIntervalMs

        /// The allowed values.
        public var range: ClosedRange<Int> {
            switch self {
            case .queueAgeMinimumMs:
                20 ... 1000
            case .queueAgeMaximumMs:
                20 ... 2000
            case .queueAgeRoundTrips:
                1 ... 8
            case .startupGraceMs:
                0 ... 60000
            case .dropSecondsToEnd:
                1 ... 60
            case .acknowledgementTimeoutMs:
                500 ... 60000
            case .queueKilobytes:
                64 ... 65536
            case .queuePackets:
                64 ... 65536
            case .keyframeIntervalMs:
                100 ... 10000
            }
        }

        /// The label shown for the field.
        public var label: LocalizedStringResource {
            switch self {
            case .queueAgeMinimumMs:
                .settingsKakusanMediaQueueAgeMinimum
            case .queueAgeMaximumMs:
                .settingsKakusanMediaQueueAgeMaximum
            case .queueAgeRoundTrips:
                .settingsKakusanMediaQueueAgeRoundTrips
            case .startupGraceMs:
                .settingsKakusanMediaStartupGrace
            case .dropSecondsToEnd:
                .settingsKakusanMediaDropSecondsToEnd
            case .acknowledgementTimeoutMs:
                .settingsKakusanMediaAcknowledgementTimeout
            case .queueKilobytes:
                .settingsKakusanMediaQueueKilobytes
            case .queuePackets:
                .settingsKakusanMediaQueuePackets
            case .keyframeIntervalMs:
                .settingsKakusanMediaKeyframeInterval
            }
        }
    }

    /// See ``Field/queueAgeMinimumMs``.
    public var queueAgeMinimumMs = 100

    /// See ``Field/queueAgeMaximumMs``.
    public var queueAgeMaximumMs = 250

    /// See ``Field/queueAgeRoundTrips``.
    public var queueAgeRoundTrips = 2

    /// See ``Field/startupGraceMs``.
    public var startupGraceMs = 5000

    /// See ``Field/dropSecondsToEnd``.
    public var dropSecondsToEnd = 10

    /// See ``Field/acknowledgementTimeoutMs``.
    public var acknowledgementTimeoutMs = 3000

    /// See ``Field/queueKilobytes``.
    public var queueKilobytes = 4096

    /// See ``Field/queuePackets``.
    public var queuePackets = 8192

    /// See ``Field/keyframeIntervalMs``.
    public var keyframeIntervalMs = 1000

    /// Creates the default tuning.
    public init() {
    }

    /// Decodes tuning, keeping defaults for missing fields and clamping the rest.
    ///
    /// - Parameter decoder: The decoder holding the stored tuning.
    /// - Throws: `DecodingError` when a stored value is not an integer.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var value = Self()
        for field in Field.allCases {
            guard let key = CodingKeys(stringValue: field.rawValue),
                  let stored = try container.decodeIfPresent(Int.self, forKey: key) else {
                continue
            }
            value[field] = stored
        }
        self = value.clamped()
    }

    /// The value of a field.
    ///
    /// - Parameter field: The field.
    public subscript(field: Field) -> Int {
        get {
            switch field {
            case .queueAgeMinimumMs:
                queueAgeMinimumMs
            case .queueAgeMaximumMs:
                queueAgeMaximumMs
            case .queueAgeRoundTrips:
                queueAgeRoundTrips
            case .startupGraceMs:
                startupGraceMs
            case .dropSecondsToEnd:
                dropSecondsToEnd
            case .acknowledgementTimeoutMs:
                acknowledgementTimeoutMs
            case .queueKilobytes:
                queueKilobytes
            case .queuePackets:
                queuePackets
            case .keyframeIntervalMs:
                keyframeIntervalMs
            }
        }
        set {
            switch field {
            case .queueAgeMinimumMs:
                queueAgeMinimumMs = newValue
            case .queueAgeMaximumMs:
                queueAgeMaximumMs = newValue
            case .queueAgeRoundTrips:
                queueAgeRoundTrips = newValue
            case .startupGraceMs:
                startupGraceMs = newValue
            case .dropSecondsToEnd:
                dropSecondsToEnd = newValue
            case .acknowledgementTimeoutMs:
                acknowledgementTimeoutMs = newValue
            case .queueKilobytes:
                queueKilobytes = newValue
            case .queuePackets:
                queuePackets = newValue
            case .keyframeIntervalMs:
                keyframeIntervalMs = newValue
            }
        }
    }

    /// The tuning with every field in range and the longest wait at least the shortest.
    ///
    /// - Returns: The clamped tuning.
    public func clamped() -> Self {
        var value = self
        for field in Field.allCases {
            value[field] = min(max(value[field], field.range.lowerBound), field.range.upperBound)
        }
        value.queueAgeMaximumMs = max(value.queueAgeMaximumMs, value.queueAgeMinimumMs)
        return value
    }
}
