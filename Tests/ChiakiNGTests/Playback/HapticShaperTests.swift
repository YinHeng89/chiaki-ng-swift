import Foundation
import Testing
import Video

private struct HapticSignal {
    var left: (Int) -> Double
    var right: (Int) -> Double
}

private func shaperState() -> CNHapticShaperState {
    var state = CNHapticShaperState()
    CNHapticShaperReset(&state)
    return state
}

private func samples(_ signal: HapticSignal, from start: Int, frames: Int) -> [Int16] {
    var output = [Int16]()
    output.reserveCapacity(frames * 2)
    for frame in start ..< start + frames {
        output.append(Int16(max(-32767, min(32767, signal.left(frame) * 32767))))
        output.append(Int16(max(-32767, min(32767, signal.right(frame) * 32767))))
    }
    return output
}

private func analyze(
    _ state: inout CNHapticShaperState,
    _ signal: HapticSignal,
    block index: Int,
    channel: Int = 0,
    frames: Int = 30,
    gain: Float = 1
) -> CNHapticShaperBlock {
    let pcm = samples(signal, from: index * frames, frames: frames)
    var block = CNHapticShaperBlock()
    pcm.withUnsafeBufferPointer { buffer in
        CNHapticShaperAnalyze(&state, buffer.baseAddress, frames, channel, gain, &block)
    }
    return block
}

private func points(_ block: CNHapticShaperBlock) -> [CNHapticShaperPoint] {
    withUnsafeBytes(of: block.points) { raw in
        Array(raw.bindMemory(to: CNHapticShaperPoint.self).prefix(block.pointCount))
    }
}

private func sine(frequency: Double, amplitude: Double, startingAt start: Int = 0) -> (Int) -> Double {
    { frame in
        frame < start
            ? 0
            : amplitude * sin(2 * Double.pi * frequency * Double(frame) / 3000)
    }
}

private func silence(_: Int) -> Double {
    0
}

@Test func hapticShaperKeepsSilenceSilent() {
    var state = shaperState()
    let block = analyze(&state, HapticSignal(left: silence, right: silence), block: 0)
    #expect(block.pointCount == 11)
    #expect(abs(block.duration - 0.01) < 0.0001)
    #expect(block.transientCount == 0)
    #expect(points(block).allSatisfy { $0.intensity == 0 })
}

@Test func hapticShaperSpreadsControlPointsAcrossTheBlock() {
    var state = shaperState()
    let block = analyze(&state, HapticSignal(left: silence, right: silence), block: 0, frames: 64)
    let values = points(block)
    #expect(values.count == Int(CNHapticShaperMaxPoints))
    #expect(values.first?.time == 0)
    #expect(abs((values.last?.time ?? 0) - Float(64) / 3000) < 0.0001)
    #expect(zip(values, values.dropFirst()).allSatisfy { $0.time < $1.time })
}

@Test func hapticShaperTracksSteadyToneAmplitudeAndFrequency() {
    var state = shaperState()
    let signal = HapticSignal(left: sine(frequency: 150, amplitude: 0.5), right: silence)
    var block = CNHapticShaperBlock()
    for index in 0 ..< 10 {
        block = analyze(&state, signal, block: index)
    }
    let expected = CNHapticShaperContinuousIntensity(0.5)
    #expect(points(block).allSatisfy { abs($0.intensity - expected) < 0.06 })
    #expect(abs(state.frequency - 150) < 20)
    #expect(abs(points(block).last!.sharpness - CNHapticShaperSharpness(150)) < 0.06)
}

@Test func hapticShaperMapsHigherFrequenciesToSharperOutput() {
    var low = shaperState()
    var high = shaperState()
    var lowBlock = CNHapticShaperBlock()
    var highBlock = CNHapticShaperBlock()
    for index in 0 ..< 10 {
        lowBlock = analyze(
            &low,
            HapticSignal(left: sine(frequency: 60, amplitude: 0.4), right: silence),
            block: index
        )
        highBlock = analyze(
            &high,
            HapticSignal(left: sine(frequency: 400, amplitude: 0.4), right: silence),
            block: index
        )
    }
    #expect(points(highBlock).last!.sharpness > points(lowBlock).last!.sharpness + 0.4)
}

@Test func hapticShaperKeepsHandsIndependent() {
    var left = shaperState()
    var right = shaperState()
    let signal = HapticSignal(left: sine(frequency: 200, amplitude: 0.6), right: silence)
    let leftBlock = analyze(&left, signal, block: 0, channel: 0)
    let rightBlock = analyze(&right, signal, block: 0, channel: 1)
    #expect(points(leftBlock).contains { $0.intensity > CNHapticShaperContinuousIntensity(0.6) * 0.5 })
    #expect(points(rightBlock).allSatisfy { $0.intensity == 0 })
}

@Test func hapticShaperMarksOneTransientAtTheOnset() {
    var state = shaperState()
    let signal = HapticSignal(left: sine(frequency: 180, amplitude: 0.8, startingAt: 45), right: silence)
    let quiet = analyze(&state, signal, block: 0)
    let onset = analyze(&state, signal, block: 1)
    let sustained = analyze(&state, signal, block: 2)
    #expect(quiet.transientCount == 0)
    #expect(onset.transientCount == 1)
    #expect(abs(onset.transient.time - Float(15) / 3000) < 0.002)
    #expect(onset.transient.intensity > 0.5)
    #expect(sustained.transientCount == 0)
}

@Test func hapticShaperReleasesQuicklyAfterTheWaveformStops() {
    var state = shaperState()
    let signal = HapticSignal(
        left: { frame in
            frame < 90
                ? 0.7 * sin(2 * Double.pi * 150 * Double(frame) / 3000)
                : 0
        },
        right: silence
    )
    for index in 0 ..< 3 {
        _ = analyze(&state, signal, block: index)
    }
    let first = analyze(&state, signal, block: 3)
    let second = analyze(&state, signal, block: 4)
    #expect(points(first).first!.intensity > CNHapticShaperContinuousIntensity(0.7) * 0.5)
    #expect(points(second).last!.intensity == 0)
}

@Test func hapticShaperAppliesGain() {
    var quiet = shaperState()
    var loud = shaperState()
    let signal = HapticSignal(left: sine(frequency: 150, amplitude: 0.2), right: silence)
    var quietBlock = CNHapticShaperBlock()
    var loudBlock = CNHapticShaperBlock()
    for index in 0 ..< 5 {
        quietBlock = analyze(&quiet, signal, block: index, gain: 0.5)
        loudBlock = analyze(&loud, signal, block: index, gain: 2)
    }
    #expect(points(loudBlock).last!.intensity > points(quietBlock).last!.intensity * 2)
}

@Test func hapticScheduleRestartsCloseToNow() {
    let first = CNHapticScheduleBlock(0, 10, 0.01)
    #expect(first.action == CNHapticScheduleRestart)
    #expect(abs(first.start - 10.004) < 0.0001)
    #expect(abs(first.duration - 0.01) < 0.0001)
    let late = CNHapticScheduleBlock(9.99, 10, 0.01)
    #expect(late.action == CNHapticScheduleRestart)
    #expect(abs(late.start - 10.004) < 0.0001)
}

@Test func hapticScheduleContinuesAndCompressesExcessLead() {
    let onTime = CNHapticScheduleBlock(10.005, 10, 0.01)
    #expect(onTime.action == CNHapticScheduleContinue)
    #expect(onTime.start == 10.005)
    #expect(abs(onTime.duration - 0.01) < 0.0001)
    let ahead = CNHapticScheduleBlock(10.02, 10, 0.01)
    #expect(ahead.action == CNHapticScheduleContinue)
    #expect(ahead.duration < 0.01)
    #expect(ahead.duration >= 0.0075)
}

@Test func hapticScheduleDropsBlocksBeyondTheLatencyBound() {
    let decision = CNHapticScheduleBlock(10.05, 10, 0.01)
    #expect(decision.action == CNHapticScheduleDrop)
}

@Test func hapticShaperFollowsItsTuning() {
    var tuning = CNHapticShaperDefaultTuning()
    tuning.continuousScale = 0
    var silenced = CNHapticShaperState()
    CNHapticShaperResetWithTuning(&silenced, &tuning)
    var normal = shaperState()
    let signal = HapticSignal(left: sine(frequency: 150, amplitude: 0.5), right: silence)
    var quiet = CNHapticShaperBlock()
    var loud = CNHapticShaperBlock()
    for index in 0 ..< 5 {
        quiet = analyze(&silenced, signal, block: index)
        loud = analyze(&normal, signal, block: index)
    }
    #expect(points(quiet).allSatisfy { $0.intensity == 0 })
    #expect(points(loud).contains { $0.intensity > 0 })
}
