import ChiakiBridge
import ChiakiModels
import CxxStdlib

/// Reads the console facts the core reports into model values.
///
/// Every core enum is switched over exhaustively, so a case the core adds fails to compile here instead of
/// being mapped silently.
enum ConsoleFactsReader {
    /// The model firmware family of a core family.
    ///
    /// - Parameter family: The core's family.
    /// - Returns: The model family; the core's `ps5_1` is `ChiakiModels/ConsoleFirmware/ps5`.
    static func firmware(of family: libchiaking.consoles.Firmware.Family) -> ConsoleFirmware {
        switch family {
        case .ps4_8:
            .ps4_8
        case .ps4_9:
            .ps4_9
        case .ps4_10:
            .ps4_10
        case .ps5_1:
            .ps5
        }
    }

    /// The model name source of a core name source.
    ///
    /// - Parameter source: The core's source.
    /// - Returns: The model source.
    static func nameSource(of source: libchiaking.consoles.ConsoleName.Source) -> ConsoleNameSource {
        switch source {
        case .generation:
            .generation
        case .account:
            .account
        case .pairing:
            .pairing
        case .discovered:
            .discovered
        case .renamed:
            .renamed
        }
    }

    /// The core generation of a model console kind.
    ///
    /// - Parameter kind: The model kind.
    /// - Returns: The core generation.
    static func generation(of kind: ConsoleKind) -> libchiaking.consoles.Generation {
        switch kind {
        case .ps4:
            .ps4
        case .ps5:
            .ps5
        }
    }

    /// The facts as stored console facts.
    ///
    /// - Parameter facts: What the core reported.
    /// - Returns: The facts, or `nil` when the hardware id is not six bytes.
    static func console(_ facts: chiaki_bridge.ConsoleFacts) -> StoredConsole? {
        guard let hardware = HardwareID(bytes: Array(facts.hardware_id)) else {
            return nil
        }
        return StoredConsole(
            hardwareID: hardware,
            firmware: firmware(of: facts.firmware),
            name: String(facts.name),
            nameSource: nameSource(of: facts.name_source),
            address: facts.address.value.map(String.init)
        )
    }

    /// The facts as a paired console.
    ///
    /// - Parameter facts: What the core reported for the console it just paired.
    /// - Returns: The console, or `nil` when the hardware id is not six bytes.
    static func paired(_ facts: chiaki_bridge.ConsoleFacts) -> PairedConsole? {
        console(facts).map {
            PairedConsole(
                hardwareID: $0.hardwareID,
                name: $0.name,
                nameSource: $0.nameSource,
                firmware: $0.firmware,
                address: $0.address
            )
        }
    }
}
