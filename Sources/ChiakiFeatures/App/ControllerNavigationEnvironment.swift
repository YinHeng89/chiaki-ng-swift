import ChiakiClients
import SwiftUI

extension EnvironmentValues {
    /// The controller driving menu navigation, which the app supplies at its root; `nil` in previews and
    /// tests that do not need one.
    @Entry public var controllerNavigation: (any ControllerNavigation)?
}
