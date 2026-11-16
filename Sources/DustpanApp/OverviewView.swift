import DustpanCore
import SwiftUI

/// The first screen: how much is safe to remove, how much needs review, and one row per area.
struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @Binding var pane: Pane?
    @State private var review: ReviewRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            StorageBar(segments: [
                .init(label: "Safe · rebuilt automatically", value: model.safeSize, color: Theme.accent),
                .init(label: "Review · might hold something you want", value: model.reviewTotal, color: Theme.reviewBar),
            ])

            ScrollView {
                Card {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { Divider() }
                        OverviewRow(row: row)
                    }
                }
                .padding(1)
            }

            Text("Everything goes to the Trash first, so any clean can be undone from History until you empty the Trash.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 28)
        .sheet(item: $review) { request in
            ReviewSheet(request: request)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(DiskSize.format(model.safeSize)) is safe to remove")
                    .font(.system(size: 28, weight: .bold))
                HStack(spacing: 8) {
                    if model.reviewTotal > 0 {
                        Text("Another \(DiskSize.format(model.reviewTotal)) needs a look from you first.")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    ScanStatus()
                }
            }
            Spacer()
            Button("Scan again") {
                Task { await model.scan() }
            }
            .controlSize(.large)
            .disabled(model.isScanning)

            Button("Review & clean \(DiskSize.format(model.selectedCacheSize))") {
                review = model.cacheReview()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.selectedCacheSize == 0 || model.isScanning)
        }
    }

    // MARK: Rows

    private var rows: [OverviewRow.Model] {
        var rows: [OverviewRow.Model] = []

        func cacheRow(_ title: String, _ detail: String, _ category: RuleCategory, _ safety: Safety) {
            let ids = model.ruleIDs(category: category, safety: safety)
            let size = model.size(category: category, safety: safety)
            guard size > 0 else { return }
            rows.append(.init(
                id: "\(category.rawValue)-\(safety.rawValue)", title: title, detail: detail,
                safety: safety, size: size, isOn: binding(for: ids), open: nil
            ))
        }
        func linkRow(_ title: String, _ detail: String, _ size: Int64, _ target: Pane) {
            guard size > 0 else { return }
            rows.append(.init(
                id: target.rawValue, title: title, detail: detail,
                safety: .review, size: size, isOn: nil, open: { pane = target }
            ))
        }

        cacheRow("Xcode build data",
                 "DerivedData, device support, simulator caches. Xcode rebuilds it on the next build.",
                 .xcode, .safe)
        cacheRow("Package manager caches",
                 "npm, pnpm, CocoaPods, Gradle, Homebrew downloads and more. Re-downloaded when needed.",
                 .packages, .safe)
        cacheRow("Temp files & old logs",
                 "Logs not written to for 30 days or more.",
                 .system, .safe)
        linkRow("Stale project builds",
                "node_modules, Unity Library, Pods and build folders in \(model.projects.count) untouched project\(model.projects.count == 1 ? "" : "s").",
                model.projectSize, .projects)
        cacheRow("Xcode archives",
                 "App archives hold the debug symbols for builds you shipped.",
                 .xcode, .review)
        linkRow("Unused apps",
                "\(model.apps.count) app\(model.apps.count == 1 ? "" : "s") you haven't opened in \(model.appStaleDays) days or more, with their data.",
                model.appsSize, .apps)
        linkRow("Older SDK versions",
                "Versions that are neither your default nor the newest, and Homebrew leftovers.",
                model.supersededToolSize, .toolchains)
        linkRow("Files & media",
                "Installers, old recordings, large videos and images, duplicates.",
                model.mediaSize, .media)
        return rows
    }

    /// On when every rule in the group is selected.
    private func binding(for ids: [String]) -> Binding<Bool> {
        Binding(
            get: { !ids.isEmpty && ids.allSatisfy { model.selectedRules.contains($0) } },
            set: { isOn in
                if isOn { model.selectedRules.formUnion(ids) } else { model.selectedRules.subtract(ids) }
            }
        )
    }
}

private struct OverviewRow: View {
    struct Model: Identifiable {
        let id: String
        let title: String
        let detail: String
        let safety: Safety
        let size: Int64
        /// A checkbox, for areas that can be cleaned straight from here.
        let isOn: Binding<Bool>?
        /// Opens the area's own screen, for areas that need choosing item by item.
        let open: (() -> Void)?
    }

    let row: Model

    var body: some View {
        HStack(spacing: 14) {
            if let isOn = row.isOn {
                Toggle(row.title, isOn: isOn)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .frame(width: 20)
            } else {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.system(size: 14, weight: .semibold))
                Text(row.detail).foregroundStyle(.secondary)
            }
            Spacer()
            if let open = row.open {
                Button("Choose…", action: open)
            }
            SafetyBadge(safety: row.safety)
                .frame(width: 64, alignment: .leading)
            Text(DiskSize.format(row.size))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
