import PlatformUI
import SwiftUI
import Testing
@testable import DesignSystem

@Test func ambientMotionRunsOnlyWhenVisibleMainAndIdle() {
    let shown = AmbientWindowState(visible: true, main: true)
    #expect(AmbientMotionState.resolve(reduceMotion: false, streaming: false, window: shown) == .running)
    #expect(
        AmbientMotionState.resolve(reduceMotion: true, streaming: false, window: shown)
            == .paused(.reduceMotion)
    )
    #expect(
        AmbientMotionState.resolve(reduceMotion: false, streaming: true, window: shown)
            == .paused(.streaming)
    )
    #expect(
        AmbientMotionState.resolve(
            reduceMotion: false, streaming: false,
            window: AmbientWindowState(visible: false, main: true)
        ) == .paused(.windowHidden)
    )
    #expect(
        AmbientMotionState.resolve(
            reduceMotion: false, streaming: false,
            window: AmbientWindowState(visible: true, main: false)
        ) == .paused(.windowInactive)
    )
}

@MainActor @Test func logoLayersFreezeAndResumeWithTheirClock() {
    let geometry = ChiakiLogoGeometry(size: 48)
    let view = ChiakiLogoLayerView(frame: CGRect(x: 0, y: 0, width: 120, height: 70))
    view.configure(geometry: geometry, isConnecting: false, replay: 0, running: true, ink: .navy)
    view.layout()
    #expect(view.isAnimating)
    #expect(view.stage.speed == 1)
    let animated = view.stage.sublayers?.first?.animationKeys() ?? []
    #expect(animated.contains("bob"))
    view.configure(geometry: geometry, isConnecting: false, replay: 0, running: false, ink: .navy)
    #expect(!view.isAnimating)
    #expect(view.stage.speed == 0)
    let frozenAt = view.stage.timeOffset
    view.configure(geometry: geometry, isConnecting: false, replay: 0, running: true, ink: .navy)
    #expect(view.stage.speed == 1)
    #expect(view.stage.timeOffset == 0)
    #expect(abs(view.stage.convertTime(CACurrentMediaTime(), from: nil) - frozenAt) < 0.05)
}

@MainActor @Test func ambientLayersFreezeWhenPaused() {
    let view = AmbientMotifLayerView(frame: CGRect(x: 0, y: 0, width: 800, height: 500))
    view.configure(quiet: true, dark: false, running: false)
    view.layout()
    #expect(!view.isAnimating)
    #expect(view.stage.speed == 0)
    #expect(view.stage.sublayers?.count == AmbientMotif.count)
    view.configure(quiet: true, dark: false, running: true)
    #expect(view.isAnimating)
}

@Test func waveTravelIsLinearSoTwoKeyframesReproduceEveryFrame() {
    let geometry = ChiakiLogoGeometry(size: 96)
    let start = ChiakiLogoMotion.wavePath(progress: 0, in: geometry).cgPath.points
    let end = ChiakiLogoMotion.wavePath(progress: 1, in: geometry).cgPath.points
    for progress in stride(from: 0.05, to: 1, by: 0.1) {
        let actual = ChiakiLogoMotion.wavePath(progress: progress, in: geometry).cgPath.points
        #expect(actual.count == start.count)
        for (index, point) in actual.enumerated() {
            let expectedX = start[index].x + (end[index].x - start[index].x) * progress
            let expectedY = start[index].y + (end[index].y - start[index].y) * progress
            #expect(abs(point.x - expectedX) < 1e-3)
            #expect(abs(point.y - expectedY) < 1e-3)
        }
    }
}

@Test func motifTravelIsLinearSoTwoKeyframesReproduceEveryFrame() {
    let size = CGSize(width: 1440, height: 900)
    for motif in AmbientMotif.all {
        let start = motif.frame(progress: 0, rotation: 0, size: size, quiet: true, dark: true)
        let end = motif.frame(progress: 1, rotation: 0, size: size, quiet: true, dark: true)
        for progress in stride(from: 0.05, to: 1, by: 0.1) {
            let actual = motif.frame(progress: progress, rotation: 0, size: size, quiet: true, dark: true)
            #expect(abs(actual.center.x - (start.center.x + (end.center.x - start.center.x) * progress)) <
                1e-6)
            #expect(abs(actual.center.y - (start.center.y + (end.center.y - start.center.y) * progress)) <
                1e-6)
            #expect(abs(actual.side - (start.side + (end.side - start.side) * progress)) < 1e-6)
        }
    }
}

@Test func motifTimelineMatchesProgressAndPhase() {
    let motif = AmbientMotif.all[3]
    #expect(abs(motif.progress(at: 0) - motif.phase) < 1e-12)
    #expect(abs(motif.progress(at: AmbientMotif.period * (1 - motif.phase))) < 1e-9)
    #expect(abs(motif.rotation(at: AmbientMotif.rotationPeriod) - motif.rotation(at: 0)) < 1e-9)
}

@Test func logoKeyTimesCoverTheCycleInOrder() {
    for times in [ChiakiLogoMotion.blinkKeyTimes(), ChiakiLogoMotion.spinKeyTimes()] {
        #expect(times.first == 0)
        #expect(times.last == 1)
        #expect(times == times.sorted())
        #expect(Set(times).count == times.count)
    }
}

@Test func spinCompletesAFullTurnBeforeTheCycleWraps() {
    let period = ChiakiLogoMotion.spinPeriod
    #expect(abs(ChiakiLogoMotion.spinAngle(period - 1e-6) - 360) < 1e-6)
    #expect(ChiakiLogoMotion.spinAngle(0) == 0)
    #expect(abs(ChiakiLogoMotion.spinAngle(3.4)) < 1e-9)
}

@Test func blinkSamplesHitBothClosures() {
    let closures = ChiakiLogoMotion.blinkKeyTimes().map { time in
        let blinkTime = time * ChiakiLogoMotion.blinkPeriod
        return max(ChiakiLogoMotion.blink(blinkTime - 3.4), ChiakiLogoMotion.blink(blinkTime - 3.86))
    }
    #expect(closures.first == 0)
    #expect(closures.last == 0)
    #expect((closures.max() ?? 0) > 0.93)
    #expect(closures.filter {
        $0 > 0
    }.count > 80)
}

@Test func animatedLogoPathsKeepOneShapeSoTheyInterpolate() {
    let geometry = ChiakiLogoGeometry(size: 48)
    let lids = ChiakiLogoMotion.blinkKeyTimes().map {
        ChiakiLogoMotion.eyelidPath($0 * ChiakiLogoMotion.blinkPeriod, in: geometry).points.count
    }
    let fills = AmbientKeyframes.samples(count: 64).map {
        ChiakiLogoMotion.fillPath($0 * ChiakiLogoMotion.fillPeriod, in: geometry).points.count
    }
    #expect(Set(lids) == [16])
    #expect(Set(fills) == [4])
}

private extension CGPath {
    var points: [CGPoint] {
        var result = [CGPoint]()
        applyWithBlock { element in
            switch element.pointee.type {
            case .moveToPoint, .addLineToPoint:
                result.append(element.pointee.points[0])
            case .addQuadCurveToPoint:
                result.append(element.pointee.points[0])
                result.append(element.pointee.points[1])
            case .addCurveToPoint:
                result.append(element.pointee.points[0])
                result.append(element.pointee.points[1])
                result.append(element.pointee.points[2])
            case .closeSubpath:
                break
            @unknown default:
                break
            }
        }
        return result
    }
}
