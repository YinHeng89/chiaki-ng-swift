/// The text fields and buttons of the entry screens that take controller focus.
public enum EntryFocus: Hashable, Sendable {
    /// The account name field.
    case accountName

    /// The Base64 account id field.
    case accountID

    /// The button that saves an account added by account id.
    case createProfile

    /// The console address field.
    case consoleAddress

    /// The button that pairs the console at the typed address.
    case consoleContinue

    /// The pairing PIN field.
    case pin

    /// The button that pairs with the typed PIN.
    case pairConsole

    /// The checkbox on the PlayStation sign-in screen that acknowledges the app is an unofficial client before
    /// signing in.
    case acknowledgeUnofficial

    /// The button that opens the web sign-in.
    case signInWithPlayStation

    /// The button that switches the PlayStation sign-in to its other method: the web sign-in page from a QR code, or
    /// a QR code from the web page.
    case signInOtherMethod

    /// The button that shows a new QR code after a QR sign-in failed.
    case newSignInCode

    /// The Back button of the PlayStation sign-in screen.
    case signInBack

    /// The Back button of the account id screen.
    case accountIDBack
}
