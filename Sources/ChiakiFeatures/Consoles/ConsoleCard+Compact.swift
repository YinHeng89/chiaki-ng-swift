import SwiftUI
import DesignSystem
import MenuFocus

extension ConsoleCard {
    /// The default size of a card on a compact screen, at its tallest.
    static let compactSize = CGSize(width: 360, height: compactTallest)
    /// The narrowest a compact card is laid out.
    static let compactNarrowest: CGFloat = 320
    /// The widest a compact card is laid out.
    static let compactWidest: CGFloat = 440
    /// The tallest a compact card is laid out; below half of it the card uses the short layout.
    static let compactTallest: CGFloat = 320
    /// The corner radius of a compact card.
    static let compactCorner: CGFloat = 26
    /// The inner padding of a tall compact card.
    static let compactPadding: CGFloat = 20
    /// The width of the console art column of a tall compact card.
    static let compactArtWidth: CGFloat = 104

    /// The height of the console art of a tall compact card, kept between 90 and 190 points.
    var compactArtHeight: CGFloat {
        min(190, max(90, compactSize.height - 2 * Self.compactPadding - 20))
    }

    /// The least width the name, tags and buttons of a tall compact card keep beside the console art.
    static let compactTextColumn: CGFloat = 140

    /// Whether a tall compact card is wide enough to show the console art beside its text column.
    var compactTallShowsArt: Bool {
        compactSize.width - 2 * Self.compactPadding - Self.compactArtWidth - 16 >= Self.compactTextColumn
    }

    /// The rim of a compact card, accented while the card holds visible focus.
    var compactRim: Color {
        inputMode.shows(containsFocus)
            ? Palette.accent.opacity(0.7)
            : CompactRim.color
    }

    /// The card's layout on a compact screen: the short row when the card is low, the tall layout otherwise.
    @ViewBuilder var compactBody: some View {
        if compactShort {
            compactShortBody
        } else {
            compactSurface(compactTallContent)
        }
    }

    private var compactTallContent: some View {
        HStack(alignment: .center, spacing: 16) {
            if compactTallShowsArt {
                ConsoleArtwork(height: compactArtHeight, kind: console.kind)
                    .frame(width: Self.compactArtWidth, height: compactArtHeight)
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 8)
            }
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    compactCaption
                    compactName
                    compactStatus
                }
                Spacer(minLength: 0)
                ViewThatFits(in: .horizontal) {
                    compactTags(titled: true)
                    compactTags(titled: false)
                }
                HStack(spacing: 8) {
                    compactPlayButton(height: 48) { direction in
                        move(from: .console(item), direction)
                    }
                    if editable {
                        compactIconButton(.edit) { direction in
                            move(from: .action(item, .edit), direction)
                        }
                        compactIconButton(.delete) { direction in
                            move(from: .action(item, .delete), direction)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(Self.compactPadding)
    }

    /// Frames content as a compact card: glass surface, rim, tap to play, context menu and address
    /// resolution.
    ///
    /// - Parameter content: The card's inside.
    /// - Returns: The card.
    func compactSurface(_ content: some View) -> some View {
        content
            .frame(width: compactSize.width, height: compactSize.height)
            .contentShape(.rect(cornerRadius: Self.compactCorner))
            .onTapGesture {
                play()
            }
            .glassEffect(AppGlass.panel, in: .rect(cornerRadius: Self.compactCorner))
            .overlay {
                RoundedRectangle(cornerRadius: Self.compactCorner)
                    .strokeBorder(compactRim, lineWidth: CompactRim.width)
                    .allowsHitTesting(false)
            }
            .disabled(busy)
            .task(id: console.address) {
                await resolveAddressLocality()
            }
            .contextMenu {
                contextMenuItems
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(name)
            .accessibilityIdentifier("console-card")
    }

    /// The generation caption of a compact card.
    var compactCaption: some View {
        Text(
            console.kind == .ps5
                ? "PLAYSTATION 5"
                : "PLAYSTATION 4"
        )
        .font(.system(size: 13, weight: .semibold))
        .tracking(1.4)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    /// The console's name on a compact card, truncated to one line.
    var compactName: some View {
        Text(name)
            .font(.system(size: 22, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    /// The status line of a compact card: Preview, the not-found note, or the console's presence.
    var compactStatusTitle: String? {
        if preview {
            return "Preview"
        }
        if missingLocally {
            return Self.missingLocallyNote
        }
        return presence.title
    }

    @ViewBuilder private var compactStatus: some View {
        if let title = compactStatusTitle {
            HStack(spacing: 6) {
                Circle()
                    .fill(
                        preview
                            ? Color.secondary
                            : presence.color
                    )
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Status \(title)")
        }
    }

    private func compactTags(titled: Bool) -> some View {
        HStack(spacing: 8) {
            ForEach(connections, id: \.self) { option in
                if connections.count > 1 {
                    FocusButton {
                        chosenConnection = option
                    } label: {
                        compactTag(option, selected: option == connection, titled: titled)
                            .opacity(playableConnections.contains(option)
                                ? 1
                                : Self.unavailableOpacity)
                    }
                    .buttonStyle(.plain)
                    .focusHighlightShape(.roundedRectangle(10))
                    .disabled(preview || !playableConnections.contains(option))
                    .menuFocused($focus, equals: .action(item, .connection(option)))
                    .environment(\.menuMove) { direction in
                        move(from: .action(item, .connection(option)), direction)
                    }
                    .accessibilityLabel("Play over \(option.title)")
                    .accessibilityHint(playableConnections.contains(option)
                        ? ""
                        : Self.missingLocallyNote)
                        .accessibilityAddTraits(
                            option == connection
                                ? .isSelected
                                : []
                        )
                } else {
                    compactTag(shownConnection, selected: false, titled: true)
                }
            }
        }
    }

    private func compactTag(_ option: ConsoleConnection, selected: Bool, titled: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: option.symbol)
                .font(.system(size: 14, weight: .medium))
            if titled {
                Text(option.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .foregroundStyle(
            selected
                ? Color.primary
                : Color.secondary
        )
        .padding(.horizontal, 12)
        .frame(minWidth: 44, minHeight: 44)
        .background(
            Color.primary.opacity(
                selected
                    ? 0.12
                    : 0.04
            ),
            in: .rect(cornerRadius: 10)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    CompactRim.color.opacity(
                        selected
                            ? 1
                            : 0
                    ),
                    lineWidth: CompactRim.width
                )
        }
        .contentShape(.rect(cornerRadius: 10))
    }

    /// The round Edit or Delete button of a compact card.
    ///
    /// - Parameters:
    ///   - action: ``ConsoleCardAction/edit`` or ``ConsoleCardAction/delete``.
    ///   - move: Routes controller moves from the button.
    /// - Returns: The button.
    func compactIconButton(
        _ action: ConsoleCardAction, move: @escaping @MainActor (MenuMoveDirection) -> Void
    ) -> some View {
        let destructive = action == .delete
        let title = destructive
            ? "Delete console"
            : "Edit console"
        return FocusButton(
            role: destructive
                ? .destructive
                : nil,
            action: destructive
                ? delete
                : edit
        ) {
            Image(
                systemName: destructive
                    ? AppIcon.deleteAccount.rawValue
                    : AppIcon.edit.rawValue
            )
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(
                destructive
                    ? Color.red
                    : Color.primary
            )
            .frame(width: 44, height: 44)
            .background(Color.primary.opacity(0.05), in: .circle)
            .overlay {
                Circle()
                    .strokeBorder(CompactRim.color, lineWidth: CompactRim.width)
            }
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .focusHighlightShape(.circle)
        .menuFocused($focus, equals: .action(item, action))
        .environment(\.menuMove, move)
        .accessibilityLabel(title)
    }

    /// The Play button of a compact card, labelled Wake for a console in rest mode.
    ///
    /// - Parameters:
    ///   - height: The button's minimum height.
    ///   - move: Routes controller moves from the button.
    /// - Returns: The button.
    func compactPlayButton(
        height: CGFloat, move: @escaping @MainActor (MenuMoveDirection) -> Void
    ) -> some View {
        FocusButton {
            play()
        } label: {
            Label(
                presence == .restMode && !preview
                    ? "Wake"
                    : "Play",
                systemImage: "play.fill"
            )
            .font(.system(size: 16, weight: .semibold))
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: height)
            .glassEffect(AppGlass.control.interactive(), in: .capsule)
            .overlay {
                Capsule()
                    .strokeBorder(CompactRim.color, lineWidth: CompactRim.width)
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .focusHighlightShape(.capsule)
        .disabled(preview)
        .menuFocused($focus, equals: .console(item))
        .environment(\.menuMove, move)
        .accessibilityLabel("\(playTitle) \(name) over \(shownConnection.title)")
        .accessibilityHint(
            missingLocally
                ? Self.missingLocallyNote
                : ""
        )
    }
}
