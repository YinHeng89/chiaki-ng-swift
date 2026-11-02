import QuartzCore

/// Builds the endlessly repeating key-frame animations used by the logo and the ambient symbols.
enum AmbientKeyframes {
    /// A linear key-frame animation that loops forever and keeps its values before and after its active time.
    ///
    /// - Parameters:
    ///   - keyPath: The layer property to animate.
    ///   - values: The value at each key frame.
    ///   - keyTimes: The fraction of `duration` at which each value is reached, or `nil` to space them evenly.
    ///   - duration: The length of one loop in seconds.
    ///   - offset: How far into the loop the animation starts, in seconds.
    ///   - begin: The layer-local time the animation starts at, usually ``AmbientLayerClock/now``.
    /// - Returns: The configured animation.
    static func repeating(
        _ keyPath: String,
        values: [Any],
        keyTimes: [Double]? = nil,
        duration: CFTimeInterval,
        offset: CFTimeInterval = 0,
        begin: CFTimeInterval
    ) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        if let keyTimes {
            animation.keyTimes = keyTimes.map {
                NSNumber(value: $0)
            }
        }
        animation.calculationMode = .linear
        animation.duration = duration
        animation.repeatCount = .infinity
        animation.timeOffset = offset
        animation.beginTime = begin
        animation.isRemovedOnCompletion = false
        animation.fillMode = .both
        return animation
    }

    /// Evenly spaced key times covering one loop.
    ///
    /// - Parameter count: The number of intervals.
    /// - Returns: `count + 1` fractions from zero to one inclusive.
    static func samples(count: Int) -> [Double] {
        (0...count).map {
            Double($0) / Double(count)
        }
    }
}
