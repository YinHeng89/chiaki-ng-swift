#if os(iOS)
    import AVFoundation
    import CoreHaptics

    /// Plays the console's rumble on the iPhone's own haptic engine, using one looping continuous pattern
    /// whose intensity and sharpness follow the two motor levels.
    @MainActor final class PhoneRumble {
        /// The length in seconds of the looping haptic pattern.
        static let loop: TimeInterval = 30

        private enum Phase {
            case idle
            case rumbling(CHHapticEngine, CHHapticAdvancedPatternPlayer)
            case unsupported
        }

        /// A haptic intensity and sharpness derived from the console's heavy and light motor levels.
        struct Level: Equatable {
            /// How much the light motor counts towards intensity compared with the heavy motor.
            static let lightMotorWeight = 0.6

            /// The haptic intensity from 0 to 1.
            let intensity: Float
            /// The haptic sharpness from 0 to 1, higher when the light motor dominates.
            let sharpness: Float

            /// Derives a haptic level from motor values scaled by the user's rumble strength.
            /// - Parameters:
            ///   - left: The heavy motor level from 0 to 255.
            ///   - right: The light motor level from 0 to 255.
            ///   - strength: The rumble strength setting, clamped to 0 through 1.
            init(left: UInt8, right: UInt8, strength: Double) {
                let heavy = Double(left) / 255
                let light = Double(right) / 255
                let scale = min(1, max(0, strength))
                intensity = Float(min(1, max(heavy, light * Self.lightMotorWeight)) * scale)
                let total = heavy + light
                sharpness = total > 0
                    ? Float(0.2 + 0.6 * light / total)
                    : 0
            }

            /// Whether the level produces no vibration.
            var isSilent: Bool {
                intensity <= 0
            }
        }

        private var phase = Phase.idle
        private var level = Level(left: 0, right: 0, strength: 0)

        /// Updates the rumble to the given motor levels, starting the haptic engine when needed and stopping
        /// it when the level is silent.
        /// - Parameters:
        ///   - left: The heavy motor level from 0 to 255.
        ///   - right: The light motor level from 0 to 255.
        ///   - strength: The rumble strength setting from 0 to 1.
        func play(left: UInt8, right: UInt8, strength: Double) {
            let next = Level(left: left, right: right, strength: strength)
            guard next != level else {
                return
            }
            level = next
            if next.isSilent {
                stop()
                return
            }
            guard let player = runningPlayer() else {
                return
            }
            try? player.sendParameters(
                [
                    CHHapticDynamicParameter(
                        parameterID: .hapticIntensityControl, value: next.intensity, relativeTime: 0
                    ),
                    CHHapticDynamicParameter(
                        parameterID: .hapticSharpnessControl, value: next.sharpness - 0.5, relativeTime: 0
                    )
                ],
                atTime: CHHapticTimeImmediate
            )
        }

        /// Silences the rumble and stops the haptic engine if it is running.
        func stop() {
            level = Level(left: 0, right: 0, strength: 0)
            guard case .rumbling(let engine, let player) = phase else {
                return
            }
            try? player.stop(atTime: CHHapticTimeImmediate)
            engine.stop()
            phase = .idle
        }

        private func runningPlayer() -> CHHapticAdvancedPatternPlayer? {
            switch phase {
            case .rumbling(_, let player):
                return player
            case .unsupported:
                return nil
            case .idle:
                return start()
            }
        }

        private func start() -> CHHapticAdvancedPatternPlayer? {
            guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
                phase = .unsupported
                return nil
            }
            do {
                try? AVAudioSession.sharedInstance().setAllowHapticsAndSystemSoundsDuringRecording(true)
                let engine = try CHHapticEngine()
                engine.playsHapticsOnly = true
                engine.stoppedHandler = { [weak self] _ in
                    Task { @MainActor in
                        self?.engineStopped()
                    }
                }
                engine.resetHandler = { [weak self] in
                    Task { @MainActor in
                        self?.engineStopped()
                    }
                }
                try engine.start()
                let event = CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                    ],
                    relativeTime: 0,
                    duration: Self.loop
                )
                let player = try engine.makeAdvancedPlayer(with: CHHapticPattern(
                    events: [event],
                    parameters: []
                ))
                player.loopEnabled = true
                try player.start(atTime: CHHapticTimeImmediate)
                phase = .rumbling(engine, player)
                return player
            } catch {
                phase = .idle
                return nil
            }
        }

        private func engineStopped() {
            guard case .rumbling = phase else {
                return
            }
            phase = .idle
            level = Level(left: 0, right: 0, strength: 0)
        }
    }
#endif
