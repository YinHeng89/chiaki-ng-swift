import ChiakiModels
import Testing

@Test func theStickGlidesTheBrightnessMarkerByItsDeflection() {
    let centre = BrightnessMarker.centre
    #expect(centre.glided(dx: 0.1, dy: 0.1, seconds: 1) == centre)
    let right = centre.glided(dx: 1, dy: 0, seconds: 0.5)
    #expect(abs(right.x - 0.8) < 0.0001)
    #expect(right.y == 0.5)
    let up = right.glided(dx: 0, dy: -0.6, seconds: 0.5)
    #expect(abs(up.y - 0.425) < 0.0001)
    #expect(up.glided(dx: 1, dy: 0, seconds: 2).x == 1)
}

@Test func nudgesMoveTheMarkerOneStepAndKeepItOnThePicture() {
    let moved = BrightnessMarker.centre.nudged(.right).nudged(.right).nudged(.down)
    #expect(abs(moved.x - 0.52) < 0.0001)
    #expect(abs(moved.y - 0.51) < 0.0001)
    #expect(BrightnessMarker(x: 0, y: 1).nudged(.left).nudged(.down) == BrightnessMarker(x: 0, y: 1))
    #expect(BrightnessMarker.stickDeflected(dx: 0.3, dy: 0))
    #expect(!BrightnessMarker.stickDeflected(dx: 0.1, dy: 0.1))
}
