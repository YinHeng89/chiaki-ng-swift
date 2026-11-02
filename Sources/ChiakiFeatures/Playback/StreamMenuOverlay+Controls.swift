import ChiakiModels
import SwiftUI

extension StreamMenuOverlay {
    /// Performs the press action of a panel control, toggling or resetting settings, acting on players or
    /// selecting a choice, and saves the edited draft.
    /// - Parameter control: The control the user activated.
    /// - Returns: `true` when the press was consumed, which includes presses on unavailable controls.
    func activateControl(_ control: StreamMenuControl) -> Bool {
        if control.isSlider {
            sliderNavigation.confirm(control, current: store.draft)
            return true
        }
        var configuration = store.draft
        switch control {
        case .pictureGenerated:
            guard frameGenerationEligible else {
                return true
            }
            configuration.presentationFrameRate = configuration.presentationFrameRate == .generated120
                ? .source
                : .generated120
        case .soundAudio3D:
            guard store.audio3DDisabledReason == nil else {
                return true
            }
            configuration.spatialAudio.audio3D.toggle()
        case .soundSpatial:
            configuration.spatialAudio.appleSpatial.toggle()
        case .colourReset:
            configuration.adjustments = PictureAdjustments()
        case .colourDeband:
            configuration.reduceBanding.toggle()
        case .streamHDR:
            configuration.launch.hdr.toggle()
        case .streamAutomaticBitrate:
            configuration.launch.automaticBitrate.toggle()
        case .streamRelaunch:
            store.send(.restartStream)
            return true
        case .measureBrightness:
            enterMeasuring()
            return true
        case .trophiesReverse:
            trophies?.send(.reverseToggled)
            return true
        default:
            return activatePlayerControl(control)
                ?? activateRemoteControl(control)
                ?? selectVideoFit(control)
                ?? cycleChoice(control, by: 1)
        }
        store.send(.edit(configuration))
        return true
    }

    private func activatePlayerControl(_ control: StreamMenuControl) -> Bool? {
        switch control {
        case .playerControls(let pad):
            couch?.send(.openControls(pad: pad))
            return true
        case .playerRemove(let pad):
            couch?.send(.cancel(pad: pad))
            return true
        case .playerReassign(let pad), .playerAdd(let pad):
            couch?.send(.pickController(pad: pad))
            return true
        case .playerPick(let id):
            guard let couch, let pad = couch.picking,
                  let option = couch.state.controllerOptions(for: pad).first(where: { $0.id == id }) else {
                return true
            }
            couch.send(.choose(pad: pad, device: option.device))
            return true
        case .playerCancelPick:
            couch?.send(.cancelPicking)
            return true
        default:
            return nil
        }
    }

    private func selectVideoFit(_ control: StreamMenuControl) -> Bool? {
        guard case .pictureFit(let raw) = control else {
            return nil
        }
        if let mode = VideoFitMode(rawValue: raw) {
            var configuration = store.draft
            configuration.videoFit.mode = mode
            store.send(.edit(configuration))
        }
        return true
    }

    /// Moves a slider control, zoom, a volume or a colour adjustment, by whole steps and saves the
    /// edited draft.
    /// - Parameters:
    ///   - control: The slider control to adjust.
    ///   - offset: The number of steps to move, negative to decrease.
    /// - Returns: `false` when the control is not a slider.
    func adjustSlider(_ control: StreamMenuControl, by offset: Int) -> Bool {
        var configuration = store.draft
        switch control {
        case .pictureZoom:
            configuration.videoFit = VideoFit(
                mode: configuration.videoFit.mode,
                zoom: configuration.videoFit.zoom + Double(offset) * 0.05
            )
        case .streamBitrate:
            configuration.launch.bitrateMbps = min(
                StreamProfile.bitrateRange.upperBound,
                max(StreamProfile.bitrateRange.lowerBound, configuration.launch.bitrateMbps + offset)
            )
        case .soundVolume:
            configuration.volume = SoundSettings(volume: configuration.volume + Double(offset) * 0.05)
                .normalized().volume
        case .soundChatVolume:
            guard let chatVolume = configuration.chatVolume else {
                return false
            }
            configuration.chatVolume = SoundSettings(chatVolume: chatVolume + Double(offset) * 0.05)
                .normalized().chatVolume
        default:
            guard let adjustments = StreamMenuColourControls.adjusted(
                configuration.adjustments,
                control,
                by: offset
            )
            else {
                return false
            }
            configuration.adjustments = adjustments
        }
        store.send(.edit(configuration))
        return true
    }

    /// Puts a slider's value back to what it was when adjusting started, and saves the draft.
    ///
    /// - Parameters:
    ///   - control: The slider whose adjustment was cancelled.
    ///   - original: The configuration from when adjusting started.
    func restoreSlider(_ control: StreamMenuControl, from original: StreamTuningConfiguration) {
        var configuration = store.draft
        switch control {
        case .pictureZoom:
            configuration.videoFit = original.videoFit
        case .streamBitrate:
            configuration.launch.bitrateMbps = original.launch.bitrateMbps
        case .soundVolume:
            configuration.volume = original.volume
        case .soundChatVolume:
            configuration.chatVolume = original.chatVolume
        case .colourBrightness, .colourContrast, .colourSaturation, .colourGamma:
            configuration.adjustments = original.adjustments
        default:
            return
        }
        store.send(.edit(configuration))
    }

    /// Steps a cycling choice, the upscaled output size or the upscaler, forward or back with wraparound and
    /// saves the edited draft.
    /// - Parameters:
    ///   - control: The choice control to cycle.
    ///   - offset: The number of options to step, negative to go back.
    /// - Returns: `false` when the control is not a cycling choice.
    func cycleChoice(_ control: StreamMenuControl, by offset: Int) -> Bool {
        var configuration = store.draft
        switch control {
        case .pictureOutput:
            configuration.upscaledOutput = cycled(
                configuration.upscaledOutput,
                in: UpscaledOutput.available(for: configuration.nativeHeight),
                by: offset
            )
        case .pictureUpscaler:
            configuration.upscaler = cycled(configuration.upscaler, in: VideoUpscaler.allCases, by: offset)
        case .trophiesFilter:
            guard let trophies else {
                return false
            }
            trophies.send(.filterChosen(cycled(trophies.filter, in: TrophyFilter.allCases, by: offset)))
            return true
        case .trophiesSort:
            guard let trophies else {
                return false
            }
            trophies.send(.sortChosen(cycled(trophies.sort, in: TrophySort.allCases, by: offset)))
            return true
        default:
            return cycleLaunchChoice(control, by: offset)
        }
        store.send(.edit(configuration))
        return true
    }

    private func cycleLaunchChoice(_ control: StreamMenuControl, by offset: Int) -> Bool {
        var configuration = store.draft
        let options = configuration.launchOptions
        switch control {
        case .streamResolution:
            configuration.launch.height = cycled(configuration.launch.height, in: options.heights, by: offset)
        case .streamFrameRate:
            configuration.launch.frameRate = cycled(
                configuration.launch.frameRate, in: options.frameRates, by: offset
            )
        case .streamCodec:
            configuration.launch.codec = cycled(configuration.launch.codec, in: options.codecs, by: offset)
        case .streamQuality:
            configuration.launch.quality = cycled(
                configuration.launch.quality, in: CloudStreamQuality.allCases, by: offset
            )
        default:
            return false
        }
        store.send(.edit(configuration))
        return true
    }

    /// Selects the panel for a tab, as Confirm on the tab or Up from another tab does, then moves focus into the
    /// panel, to its last control or the Trophies panel's first trophy, while the tab still holds focus.
    ///
    /// A panel shown for the first time may not have its controls yet on the next run loop, so focus is applied
    /// again for a few turns until a control of the panel holds it or focus moved elsewhere.
    func selectPanelFromTab(_ item: StreamMenuPanel) {
        store.send(.selectPanel(item))
        Task { @MainActor in
            for _ in 0 ..< 8 {
                await Task.yield()
                guard panel == item else {
                    return
                }
                switch focusTarget {
                case .control:
                    return
                case .tab(item), nil:
                    focusLastControl()
                default:
                    return
                }
                try? await Task.sleep(for: .milliseconds(30))
            }
        }
    }

    private func cycled<Value: Equatable>(_ value: Value, in values: [Value], by offset: Int) -> Value {
        guard let first = values.first else {
            return value
        }
        guard let index = values.firstIndex(of: value) else {
            return first
        }
        return values[(index + offset + values.count) % values.count]
    }
}
