import ChiakiClients
import ChiakiDiagnostics
import ChiakiModels
import ComposableArchitecture
import Foundation
import MenuFocus
import PlatformUI
import SwiftUI
#if !os(macOS)
    import UniformTypeIdentifiers
#endif

/// The error report, with Copy, Save and Done.
public struct ErrorReportSheet: View {
    /// The error report feature that holds the report text and drives copying, saving and dismissal.
    public let store: StoreOf<ErrorReportFeature>

    /// Creates an error report sheet.
    ///
    /// - Parameter store: The error report feature that holds the report text and drives copying, saving and
    ///   dismissal.
    public init(store: StoreOf<ErrorReportFeature>) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(.settingsDeveloperReportTitle).font(.headline)
            #if os(macOS)
                ErrorReportTextView(text: store.text)
                    .frame(minWidth: 640, minHeight: 360)
            #else
                ErrorReportTextView(text: store.text)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            #endif
            if store.saving == .failed {
                Label(.settingsDeveloperReportSaveFailed, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                FocusButton(.settingsDeveloperReportCopy) {
                    PlatformPasteboard.copy(store.text)
                }
                Spacer()
                if case .writing = store.saving {
                    ProgressView().controlSize(.small)
                }
                FocusButton(.settingsDeveloperReportSave) {
                    store.send(.save)
                }
                FocusButton(.commonDone) {
                    store.send(.done)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        #if !os(macOS)
            .fileExporter(
                isPresented: Binding(
                    get: {
                        store.saving == .choosingDestination
                    },
                    set: { shown in
                        if !shown {
                            store.send(.destinationChosen(nil))
                        }
                    }
                ),
                document: ErrorReportDocument(text: store.text),
                contentType: .plainText,
                defaultFilename: ErrorReport.suggestedFileName()
            ) { result in
                store.send(.exported(succeeded: (try? result.get()) != nil))
            }
        #endif
    }
}

#if !os(macOS)
    import SwiftUI
    import UniformTypeIdentifiers

    /// The report as a plain-text document for the system file exporter.
    public struct ErrorReportDocument: FileDocument {
        /// The document is read and written as plain text.
        public static let readableContentTypes = [UTType.plainText]
        /// The report's text.
        public let text: String

        /// Wraps a report for export.
        ///
        /// - Parameter text: The report's text.
        public init(text: String) {
            self.text = text
        }

        /// Reads a document as UTF-8 text, leaving it empty when the file cannot be read.
        ///
        /// - Parameter configuration: The file to read.
        public init(configuration: ReadConfiguration) throws {
            text = configuration.file.regularFileContents.flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
        }

        /// Writes the report as UTF-8 text.
        ///
        /// - Parameter configuration: The export destination.
        /// - Returns: A file wrapper holding the report.
        public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
            FileWrapper(regularFileWithContents: Data(text.utf8))
        }
    }
#endif

#if os(macOS)
    /// The report in a read-only, selectable monospaced text view.
    public struct ErrorReportTextView: NSViewRepresentable {
        /// The report's text.
        public let text: String

        /// Creates a scrolling, non-editable plain-text view in the small monospaced system font holding the
        /// report.
        public func makeNSView(context: Context) -> NSScrollView {
            let view = NSTextView.scrollableTextView()
            guard let textView = view.documentView as? NSTextView else {
                return view
            }
            textView.isEditable = false
            textView.isRichText = false
            textView.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
            textView.textContainerInset = CGSize(width: 8, height: 8)
            textView.string = text
            return view
        }

        /// Replaces the shown text when the report changes.
        public func updateNSView(_ view: NSScrollView, context: Context) {
            guard let textView = view.documentView as? NSTextView, textView.string != text else {
                return
            }
            textView.string = text
        }
    }
#else
    /// The report in a read-only, selectable monospaced text view.
    public struct ErrorReportTextView: UIViewRepresentable {
        /// The report's text.
        public let text: String

        /// Creates a non-editable, selectable text view in the small monospaced system font holding the
        /// report.
        public func makeUIView(context: Context) -> UITextView {
            let view = UITextView()
            view.isEditable = false
            view.isSelectable = true
            view.font = .monospacedSystemFont(ofSize: UIFont.smallSystemFontSize, weight: .regular)
            view.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
            view.text = text
            return view
        }

        /// Replaces the shown text when the report changes.
        public func updateUIView(_ view: UITextView, context: Context) {
            guard view.text != text else {
                return
            }
            view.text = text
        }
    }
#endif

/// Shows a built error report and saves it to a file.
///
/// A failed save is shown, never swallowed: the sheet stays open with the reason so the user can try again
/// or copy the text instead.
@Reducer
public struct ErrorReportFeature {
    /// Where saving the report is.
    public enum Saving: Equatable, Sendable {
        /// Nothing has been saved.
        case idle

        /// Waiting for the user to choose where.
        case choosingDestination

        /// Writing the file by the operation with this id.
        case writing(OperationID)

        /// The report was saved.
        case saved

        /// The report could not be saved.
        case failed
    }

    /// The sheet's state.
    @ObservableState
    public struct State: Equatable, Sendable {
        /// The report.
        public let text: String

        /// Where saving the report is.
        public internal(set) var saving = Saving.idle

        /// Shows a report.
        ///
        /// - Parameter text: The report.
        public init(text: String) {
            self.text = text
        }
    }

    /// Everything the sheet reacts to.
    public enum Action: Equatable, Sendable {
        /// Save the report to a file the user chooses.
        case save

        /// The user chose where to save, or cancelled.
        case destinationChosen(URL?)

        /// The system file exporter finished, on platforms where it writes the file itself.
        case exported(succeeded: Bool)

        /// Writing the file finished.
        case written(OperationID, succeeded: Bool)

        /// Close the sheet.
        case done
    }

    @Dependency(\.platform) private var platform
    @Dependency(\.uuid) private var uuid
    @Dependency(\.dismiss) private var dismiss

    /// Creates the reducer.
    public init() {
    }

    /// The reducer.
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .save:
                if case .writing = state.saving {
                    return .none
                }
                state.saving = .choosingDestination
                #if os(macOS)
                    return .run { [platform] send in
                        await send(.destinationChosen(platform
                                .chooseReportDestination(ErrorReport.suggestedFileName())))
                    }
                #else
                    return .none
                #endif
            case let .destinationChosen(url):
                guard state.saving == .choosingDestination else {
                    return .none
                }
                guard let url else {
                    state.saving = .idle
                    return .none
                }
                let id = OperationID(uuid: uuid())
                state.saving = .writing(id)
                return .run { [platform, text = state.text] send in
                    do {
                        try await platform.writeReport(text, url)
                        await send(.written(id, succeeded: true))
                    } catch {
                        await send(.written(id, succeeded: false))
                    }
                }
            case let .exported(succeeded):
                guard state.saving == .choosingDestination else {
                    return .none
                }
                state.saving = succeeded
                    ? .saved
                    : .failed
                return .none
            case let .written(id, succeeded):
                guard state.saving == .writing(id) else {
                    return .none
                }
                state.saving = succeeded
                    ? .saved
                    : .failed
                return .none
            case .done:
                return .run { [dismiss] _ in
                    await dismiss()
                }
            }
        }
    }
}
