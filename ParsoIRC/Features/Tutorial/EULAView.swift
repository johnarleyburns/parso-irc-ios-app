import SwiftUI

/// First-launch gate: End User License Agreement + age attestation.
///
/// The user must:
///   1. Scroll to the bottom of the EULA text.
///   2. Check "I confirm I am 18 years of age or older" (or the applicable
///      minimum age in their jurisdiction).
///   3. Check "I have read and agree to the Terms of Service".
///   4. Tap "Agree & Continue".
///
/// Both checkboxes are required; the button is disabled until both are ticked
/// AND the user has scrolled to the bottom of the EULA.
struct EULAView: View {
    @Binding var isPresented: Bool

    @State private var ageConfirmed: Bool = false
    @State private var termsConfirmed: Bool = false
    @State private var hasScrolledToBottom: Bool = false
    @State private var showDeclineAlert: Bool = false

    private var canProceed: Bool {
        ageConfirmed && termsConfirmed && hasScrolledToBottom
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ── Scrollable EULA body ──────────────────────────────────────
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        eulaHeader
                        eulaBody
                        // Invisible sentinel: when it appears in the viewport,
                        // the user has scrolled to the bottom of the document.
                        Color.clear
                            .frame(height: 1)
                            .onAppear { hasScrolledToBottom = true }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }

                Divider()

                // ── Checkboxes + action buttons ───────────────────────────────
                VStack(spacing: 14) {
                    checkboxRow(
                        isChecked: $ageConfirmed,
                        label: "I confirm I am 18 years of age or older (or the minimum age required in my jurisdiction).",
                        accessibilityLabel: "Age confirmation checkbox"
                    )

                    checkboxRow(
                        isChecked: $termsConfirmed,
                        label: "I have read and agree to the Terms of Service and End User License Agreement above.",
                        accessibilityLabel: "Terms agreement checkbox"
                    )

                    if !hasScrolledToBottom {
                        Text("Please scroll to the bottom to review the full agreement.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 4)
                    }

                    Button {
                        UserDefaults.standard.set(true, forKey: "eulaAccepted")
                        isPresented = false
                    } label: {
                        Text("Agree & Continue")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(canProceed ? Color.accentColor : Color(.systemFill))
                            .foregroundStyle(canProceed ? .white : .secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(!canProceed)

                    Button {
                        showDeclineAlert = true
                    } label: {
                        Text("Decline")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color(.systemBackground))
            }
            .navigationTitle("Terms of Service")
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert("Unable to Continue", isPresented: $showDeclineAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You must agree to the Terms of Service and confirm your age to use Parso IRC. To decline, please close the app.")
        }
        .interactiveDismissDisabled(true)
    }

    // MARK: - Header

    private var eulaHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("End User License Agreement")
                .font(.title2)
                .fontWeight(.bold)

            Text("PARSO IRC — Licensed Application")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Licensor: Parso Consulting")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Support: info@parso.guru")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()
        }
    }

    // MARK: - EULA body (Apple Standard EULA template, adapted for Parso IRC)

    private var eulaBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            eulaSection(
                title: "Acknowledgement",
                body: """
Parso Consulting ("Licensor") and you ("End-User") acknowledge that this End User License Agreement ("EULA") is concluded between Licensor and End-User only, and not with Apple Inc. ("Apple"). Licensor, not Apple, is solely responsible for the Licensed Application ("Parso IRC") and its content.

This EULA may not provide for usage rules for Parso IRC that are in conflict with the Apple Media Services Terms and Conditions ("Usage Rules") as of the date you download Parso IRC. Licensor acknowledges that it had the opportunity to review the Usage Rules and this EULA is not in conflict with them.

When Parso IRC is downloaded through the Apple App Store, the Usage Rules will also govern your use of Parso IRC.
"""
            )

            eulaSection(
                title: "Scope of License",
                body: """
Licensor grants you a non-transferable, non-exclusive, non-sublicensable license to install and use Parso IRC on any Apple-branded products that you own or control, as permitted by the Usage Rules. The terms of this EULA will govern any content, materials, or services accessible from or purchased within Parso IRC, as well as upgrades provided by Licensor that replace or supplement the original application, unless such an upgrade is accompanied by a new EULA. Except as provided in the Usage Rules, you may not distribute or make Parso IRC available over a network where it could be used by multiple devices at the same time. You may not transfer, redistribute, or sublicense Parso IRC and, if you sell your Apple Device to a third party, you must remove Parso IRC from the Apple Device before doing so. You may not copy (except as permitted by this license and the Usage Rules), reverse-engineer, disassemble, attempt to derive the source code of, modify, or create derivative works of Parso IRC, any updates, or any part thereof (except as and only to the extent that any foregoing restriction is prohibited by applicable law or to the extent as may be permitted by the licensing terms governing use of any open-sourced components included with Parso IRC).
"""
            )

            eulaSection(
                title: "Technical Requirements",
                body: """
Licensor warrants that Parso IRC functions as described in the documentation and on the App Store. In order to use Parso IRC, you need an Apple device with iOS 17.0 or later and an active internet connection. The technical specifications are subject to change without notice. You acknowledge that it is your responsibility to confirm and verify all technical specifications before downloading Parso IRC.
"""
            )

            eulaSection(
                title: "No Warranty",
                body: """
You expressly acknowledge and agree that use of Parso IRC is at your sole risk. To the maximum extent permitted by applicable law, Parso IRC and any services performed or provided by Parso IRC are provided "AS IS" and "AS AVAILABLE," with all faults and without warranty of any kind, and Licensor hereby disclaims all warranties and conditions with respect to Parso IRC and any services, either express, implied, or statutory, including, but not limited to, the implied warranties and/or conditions of merchantability, of satisfactory quality, of fitness for a particular purpose, of accuracy, of quiet enjoyment, and of noninfringement of third-party rights.

No oral or written information or advice given by Licensor or its authorized representatives shall create a warranty. Should Parso IRC prove defective, you assume the entire cost of all necessary servicing, repair, or correction.
"""
            )

            eulaSection(
                title: "Limitation of Liability",
                body: """
To the extent not prohibited by law, in no event shall Licensor be liable for personal injury or any incidental, special, indirect, or consequential damages whatsoever, including, without limitation, damages for loss of profits, loss of data, business interruption, or any other commercial damages or losses, arising out of or related to your use or inability to use Parso IRC, however caused, regardless of the theory of liability (contract, tort, or otherwise) and even if Licensor has been advised of the possibility of such damages.
"""
            )

            eulaSection(
                title: "User-Generated Content",
                body: """
Parso IRC connects you to third-party IRC networks that contain user-generated content. Licensor does not control, and is not responsible for, any user-generated content on third-party IRC servers. You acknowledge that you may be exposed to content that you find offensive, indecent, or objectionable, and that you use Parso IRC at your own risk.

By using Parso IRC, you agree not to transmit any content that is unlawful, harassing, abusive, tortious, defamatory, obscene, invasive of another's privacy, or otherwise objectionable. You acknowledge that Licensor provides in-app reporting tools to flag violations and that reported content will be reviewed in accordance with Licensor's moderation policies.
"""
            )

            eulaSection(
                title: "Age Requirement",
                body: """
Parso IRC is intended for users who are 18 years of age or older, or the minimum age required in your jurisdiction, whichever is greater. By using Parso IRC, you represent and warrant that you meet this age requirement. If you are under the applicable minimum age, you may not use Parso IRC.
"""
            )

            eulaSection(
                title: "Maintenance and Support",
                body: """
Licensor is solely responsible for providing any maintenance and support services with respect to Parso IRC, as specified in this EULA or as required under applicable law. Licensor and you acknowledge that Apple has no obligation whatsoever to furnish any maintenance and support services with respect to Parso IRC.

You can reach Licensor for support at: info@parso.guru
"""
            )

            eulaSection(
                title: "Product Claims",
                body: """
Licensor and you acknowledge that Licensor, not Apple, is responsible for addressing any claims by you or any third party relating to Parso IRC or your possession and/or use of Parso IRC, including, but not limited to: (i) product liability claims; (ii) any claim that Parso IRC fails to conform to any applicable legal or regulatory requirement; and (iii) claims arising under consumer protection, privacy, or similar legislation.
"""
            )

            eulaSection(
                title: "Intellectual Property Rights",
                body: """
In the event of any third-party claim that Parso IRC or your possession and use of Parso IRC infringes that third party's intellectual property rights, Licensor will be solely responsible for the investigation, defense, settlement, and discharge of any such intellectual property infringement claim. Apple shall have no obligation whatsoever with respect to such claims.
"""
            )

            eulaSection(
                title: "Legal Compliance",
                body: """
You represent and warrant that (i) you are not located in a country that is subject to a U.S. Government embargo, or that has been designated by the U.S. Government as a "terrorist supporting" country; and (ii) you are not listed on any U.S. Government list of prohibited or restricted parties.
"""
            )

            eulaSection(
                title: "Third-Party Terms of Agreement",
                body: """
You must comply with applicable third-party terms of service when using Parso IRC. Parso IRC connects to public and private IRC networks; your use of those networks is governed by each network's own terms of service, which are independent of this EULA.
"""
            )

            eulaSection(
                title: "Third-Party Beneficiary",
                body: """
Licensor and you acknowledge and agree that Apple, and Apple's subsidiaries, are third-party beneficiaries of this EULA, and that, upon your acceptance of the terms and conditions of this EULA, Apple will have the right (and will be deemed to have accepted the right) to enforce this EULA against you as a third-party beneficiary thereof.
"""
            )

            eulaSection(
                title: "Contact Information",
                body: """
If you have any questions, complaints, or claims with respect to Parso IRC, please contact Licensor at:

Parso Consulting
Email: info@parso.guru
"""
            )
        }
    }

    // MARK: - Helpers

    private func eulaSection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            Text(body)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func checkboxRow(
        isChecked: Binding<Bool>,
        label: String,
        accessibilityLabel: String
    ) -> some View {
        Button {
            isChecked.wrappedValue.toggle()
            HapticManager.selectionFeedback()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isChecked.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(isChecked.wrappedValue ? Color.accentColor : Color(.systemGray))
                    .animation(.easeInOut(duration: 0.15), value: isChecked.wrappedValue)
                Text(label)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isChecked.wrappedValue ? "Checked" : "Unchecked")
        .accessibilityHint("Double-tap to toggle")
    }
}

#Preview {
    EULAView(isPresented: .constant(true))
}
