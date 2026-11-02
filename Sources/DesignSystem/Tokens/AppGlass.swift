import SwiftUI

/// The Liquid Glass materials the app draws with.
public enum AppGlass {
    /// Clear glass for buttons, segmented controls and other small controls.
    public static var control: Glass {
        .clear
    }

    /// Lightly tinted glass for panels, cards and modals.
    public static var panel: Glass {
        .regular.tint(.black.opacity(0.2))
    }

    /// Panel glass tinted with ``Palette/slate`` for notices shown over a stream.
    public static var notice: Glass {
        panel.tint(Palette.slate.opacity(0.35))
    }

    /// Clear glass tinted orange for warnings shown over a stream.
    public static var warning: Glass {
        control.tint(.orange.opacity(0.25))
    }
}
