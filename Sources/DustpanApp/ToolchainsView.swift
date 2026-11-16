import DustpanCore
import SwiftUI

/// Every installed SDK and toolchain version, with a way to drop the ones no longer needed.
struct ToolchainsView: View {
    @Environment(AppModel.self) private var model
    @State private var review: ReviewRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SDKs & toolchains").font(.title.weight(.bold))
                    HStack(spacing: 8) {
                        Text("Every version installed on this Mac. Nothing here is selected for you.")
                            .foregroundStyle(.secondary)
                        ScanStatus()
                    }
                }
                Spacer()
                Button("Select older versions") {
                    model.selectSupersededToolVersions()
                }
                .disabled(model.supersededToolVersions.isEmpty || model.isScanning)
                .help("Selects every version that is neither the default nor the newest of its kind.")

                Button("Review & remove \(DiskSize.format(model.selectedToolSize))") {
                    review = model.toolchainReview()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedToolSize == 0 || model.isScanning)
            }

            if model.toolchains.isEmpty {
                if model.isScanning {
                    Spacer()
                } else {
                    ContentUnavailableView(
                        "No versioned SDKs found",
                        systemImage: "shippingbox",
                        description: Text("Looked for Node, Python, Ruby, Rust, Flutter, Go, Java, Android, Unity, Xcode and Homebrew installs.")
                    )
                }
            } else {
                List {
                    ForEach(model.toolchains) { toolchain in
                        Section {
                            ForEach(toolchain.versions) { version in
                                VersionRow(version: version, isOn: binding(for: version.id))
                            }
                        } header: {
                            HStack {
                                Text(toolchain.name).font(.headline)
                                Text("via \(toolchain.manager)").foregroundStyle(.secondary)
                                Spacer()
                                Text("\(toolchain.versions.count) installed · \(DiskSize.format(toolchain.size))")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: false))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
            }

            Text("Default is the version your version manager is set to use. A project can still pin an older version, for example in .nvmrc or .python-version, so check before removing. System-wide installs and current Homebrew packages are listed with the command that removes them; only Homebrew's leftover old versions can be removed here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .sheet(item: $review) { request in
            ReviewSheet(request: request)
        }
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { model.selectedToolVersions.contains(id) },
            set: { isOn in
                if isOn { model.selectedToolVersions.insert(id) } else { model.selectedToolVersions.remove(id) }
            }
        )
    }
}

private struct VersionRow: View {
    let version: ToolVersion
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Toggle(version.version, isOn: $isOn)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(!version.removable)
            Text(version.version)
                .font(.body.weight(.medium))
                .monospacedDigit()
            if version.isDefault { tag("Default", color: Theme.accent) }
            if version.isNewest { tag("Newest", color: .secondary) }
            if let reason = version.lockReason { tag(reason, color: Theme.review) }
            Spacer()
            Text(version.url.deletingLastPathComponent().path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(DiskSize.format(version.size))
                .monospacedDigit()
                .frame(width: 90, alignment: .trailing)
        }
        .padding(.vertical, 3)
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
    }
}
