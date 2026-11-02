import ChiakiModels
import DesignSystem
import MenuFocus
import SwiftUI

/// The line above the sign-in page that names the current page's host and who its certificate was issued to,
/// with a chevron that shows or hides the certificate's details in place rather than in a popover.
///
/// It follows the page as the sign-in moves between hosts, so the person can check whose page they are typing
/// into. It is there for reassurance and says so.
struct SignInCertificateBar: View {
    /// The certificate the page's connection was secured with.
    let certificate: SignInCertificate
    @State private var expanded = true

    /// The bar.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summary
            if expanded {
                Divider()
                details
            }
        }
        .glassEffect(AppGlass.panel, in: .rect(cornerRadius: 12))
        .animation(.easeOut(duration: 0.15), value: expanded)
        .accessibilityElement(children: .contain)
    }

    private var summary: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Palette.accent)
                .frame(width: 22, height: 22)
                .background(
                    Palette.accent.opacity(0.16),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .accessibilityHidden(true)
            Text(certificate.host)
                .font(.callout.monospaced().weight(.semibold))
                .lineLimit(1)
            if let party = certificate.verifiedParty {
                Text("Verified: \(party)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            FocusButton {
                expanded.toggle()
            } label: {
                Image(systemName: "chevron.down")
                    .rotationEffect(expanded
                        ? .zero
                        : .degrees(-180))
                        .frame(width: 24, height: 24)
            }
            .glassControlStyle()
            .focusBorderShape(.circle)
            .accessibilityLabel(expanded
                ? "Hide certificate details"
                : "Show certificate details")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var details: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 18, verticalSpacing: 10) {
            GridRow {
                Text(Self.reassurance)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Palette.accent)
                    .fixedSize(horizontal: false, vertical: true)
                    .gridCellColumns(2)
            }
            GridRow {
                field("Issued to", certificate.subject)
                field("Issued by", certificate.issuer ?? "Unknown")
            }
            GridRow {
                field("Valid", validity)
                    .gridCellColumns(2)
            }
            GridRow {
                field("SHA-256", certificate.fingerprint, monospaced: true)
                    .gridCellColumns(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// Why the bar is shown, under the details.
    static var reassurance: String {
        "Shown for your reassurance: this is the certificate of the page you are signing in on, as it was "
            + "verified for this connection. It changes as the sign-in moves between pages."
    }

    private var validity: String {
        switch (certificate.validFrom, certificate.validUntil) {
        case (let from?, let until?):
            "\(Self.shown(from)) to \(Self.shown(until))"
        case (nil, let until?):
            "Until \(Self.shown(until))"
        case (let from?, nil):
            "From \(Self.shown(from))"
        case (nil, nil):
            "Unknown"
        }
    }

    private static func shown(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    private func field(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(monospaced
                    ? .caption.monospaced()
                    : .callout)
                    .foregroundStyle(monospaced
                        ? .secondary
                        : .primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
