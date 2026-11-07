import Foundation

/// How the stream diagnostics overlay looks: how much it shows, its material and its arrangement.
///
/// Decoding tolerates missing or unknown values and falls back to the defaults.
public struct StreamDiagnosticsAppearance: Codable, Equatable, Sendable {
    /// How much of the overlay is shown.
    public enum Level: String, Codable, CaseIterable, Equatable, Sendable {
        /// The overlay is hidden.
        case off

        /// One line of key figures.
        case compact

        /// The usual set of figures.
        case standard

        /// Every figure and chart.
        case full

        /// The label shown for the level.
        public var title: LocalizedStringResource {
            switch self {
            case .off:
                .settingsDiagnosticsLevelOff
            case .compact:
                .settingsDiagnosticsLevelCompact
            case .standard:
                .settingsDiagnosticsLevelStandard
            case .full:
                .settingsDiagnosticsLevelFull
            }
        }

        /// Whether the overlay is shown at all.
        public var visible: Bool {
            self != .off
        }

        /// The level a toggle moves to, cycling back to ``off`` after ``full``.
        public var nextShown: Level {
            switch self {
            case .off:
                .compact
            case .compact:
                .standard
            case .standard:
                .full
            case .full:
                .off
            }
        }
    }

    /// The material behind the overlay.
    public enum Glass: String, Codable, CaseIterable, Equatable, Sendable {
        /// Regular Liquid Glass.
        case regular

        /// Clear glass.
        case clear

        /// Clear glass over a dimming layer.
        case clearDimmed

        /// Glass tinted by the stream's health.
        case healthTint

        /// An opaque background.
        case solid

        /// The label shown for the material.
        public var title: LocalizedStringResource {
            switch self {
            case .regular:
                .settingsDiagnosticsGlassRegular
            case .clear:
                .settingsDiagnosticsGlassClear
            case .clearDimmed:
                .settingsDiagnosticsGlassDimmed
            case .healthTint:
                .settingsDiagnosticsGlassHealthTint
            case .solid:
                .settingsDiagnosticsGlassSolid
            }
        }

        /// The next material in declaration order, wrapping around.
        public var next: Glass {
            let all = Self.allCases
            let index = all.firstIndex(of: self) ?? all.startIndex
            return all[(index + 1) % all.count]
        }
    }

    /// How the overlay's sections are arranged.
    public enum Layout: String, Codable, CaseIterable, Equatable, Sendable {
        /// All sections on one sheet.
        case sheet

        /// Separate floating cards.
        case floating

        /// The label shown for the arrangement.
        public var title: LocalizedStringResource {
            switch self {
            case .sheet:
                .settingsDiagnosticsLayoutSheet
            case .floating:
                .settingsDiagnosticsLayoutFloating
            }
        }
    }

    /// How much is shown.
    public var level: Level

    /// The material behind the overlay.
    public var glass: Glass

    /// How the sections are arranged.
    public var layout: Layout

    /// Creates an appearance.
    ///
    /// - Parameters:
    ///   - level: How much is shown.
    ///   - glass: The material.
    ///   - layout: The arrangement.
    public init(level: Level = .off, glass: Glass = .regular, layout: Layout = .sheet) {
        self.level = level
        self.glass = glass
        self.layout = layout
    }

    /// Decodes an appearance, defaulting anything missing or unreadable.
    ///
    /// - Parameter decoder: The decoder holding the stored appearance.
    /// - Throws: `DecodingError` when the stored value is not a keyed container.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        level = (try? values.decodeIfPresent(Level.self, forKey: .level)) ?? .off
        glass = (try? values.decodeIfPresent(Glass.self, forKey: .glass)) ?? .regular
        layout = (try? values.decodeIfPresent(Layout.self, forKey: .layout)) ?? .sheet
    }
}
