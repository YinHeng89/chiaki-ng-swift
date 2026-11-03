import ChiakiModels
import CoreGraphics
import Testing
@testable import ChiakiFeatures

@Suite struct ControlsBoardPlacementTests {
    let points = PlayStationControl.allCases.compactMap { control in
        ControllerArtwork.dualSense.consolePosition(of: control).map { (control, $0) }
    }

    @Test(arguments: [
        CGSize(width: 540, height: 290),
        CGSize(width: 600, height: 300),
        CGSize(width: 660, height: 310),
        CGSize(width: 720, height: 330),
        CGSize(width: 960, height: 640),
        CGSize(width: 1180, height: 760)
    ])
    func aCompactBoardKeepsEveryChipApartAndOnTheScreen(size: CGSize) {
        let placement = ControlsBoardPlacement(
            width: size.width,
            filling: size.height,
            aspectRatio: ControllerArtwork.dualSense.aspectRatio,
            points: points,
            metrics: .compact
        )
        guard size.width >= ControlsBoardPlacement.Metrics.compact.sideBySideWidth else {
            #expect(placement.isStacked)
            return
        }
        let bounds = CGRect(origin: .zero, size: size)
        #expect(!placement.isStacked)
        #expect(placement.chips.count == points.count)
        #expect(bounds.contains(placement.artFrame))
        for chip in placement.chips {
            #expect(bounds.contains(chip.frame), "\(chip.control) leaves the board")
            #expect(!chip.frame.intersects(placement.artFrame), "\(chip.control) covers the drawing")
            for other in placement.chips where other.control != chip.control {
                #expect(!chip.frame.intersects(other.frame), "\(chip.control) overlaps \(other.control)")
            }
        }
    }

    @Test func middleControlsEvenOutTheCompactColumns() {
        let placement = ControlsBoardPlacement(
            width: 660,
            filling: 310,
            aspectRatio: ControllerArtwork.dualSense.aspectRatio,
            points: points,
            metrics: .compact
        )
        let leading = placement.chips.filter(\.leading).count
        #expect(abs(leading - (placement.chips.count - leading)) <= 1)
    }
}
