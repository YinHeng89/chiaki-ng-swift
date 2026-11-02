import Foundation

/// Locates the images, sounds and licence texts bundled with the app's shared asset target.
public enum ChiakiAssets {
    /// The resource bundle that holds the shared assets.
    public static let bundle = Bundle.module

    /// Finds a bundled resource by name.
    ///
    /// - Parameters:
    ///   - name: The resource's file name without its extension.
    ///   - ext: The file extension, or `nil` for a resource without one, such as a folder.
    /// - Returns: The resource's location, or `nil` when the bundle does not contain it.
    public static func url(forResource name: String, withExtension ext: String?) -> URL? {
        bundle.url(forResource: name, withExtension: ext)
    }

    /// The bundled `Licenses` folder with the third-party licence texts, or `nil` when it is missing.
    public static var licensesURL: URL? {
        url(forResource: "Licenses", withExtension: nil)
    }
}
