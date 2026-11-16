import DustpanCore
import SwiftUI

struct AppsView: View {
    @Environment(AppModel.self) private var model
    @State private var review: ReviewRequest?

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Unused apps").font(.title.weight(.bold))
                    Text("Apps you haven't opened in a while, with the data each one keeps. Nothing here is selected for you.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clear caches only") {
                    review = model.appsReview(cachesOnly: true)
                }
                .disabled(model.selectedAppsCacheSize == 0 || model.isScanning)

                Button(uninstallTitle) {
                    review = model.appsReview(cachesOnly: false)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedApps.isEmpty || model.isScanning)
            }

            HStack(spacing: 12) {
                Picker("Not opened for", selection: $model.appStaleDays) {
                    Text("30+ days").tag(30)
                    Text("90+ days").tag(90)
                    Text("6+ months").tag(180)
                    Text("1+ year").tag(365)
                }
                .fixedSize()
                ScanStatus()
            }

            if model.apps.isEmpty {
                if model.isScanning {
                    Spacer()
                } else {
                    ContentUnavailableView(
                        "No unused apps",
                        systemImage: "app.dashed",
                        description: Text("Every app here has been opened more recently than that.")
                    )
                }
            } else {
                ColumnHeader(columns: [
                    ("App", nil, .leading),
                    ("Last opened", 150, .leading),
                    ("App", 80, .trailing),
                    ("Its data", 80, .trailing),
                    ("Total", 80, .trailing),
                ])
                .padding(.bottom, -10)
                List(model.apps) { app in
                    AppRow(app: app, isOn: binding(for: app.id))
                }
                .listStyle(.inset(alternatesRowBackgrounds: false))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
            }

            Text("Last opened comes from macOS usage records. Apps that came with macOS and apps that are running are never listed. Apps installed from the App Store or by an installer may need to be removed in Finder if macOS refuses.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .onChange(of: model.appStaleDays) { _, _ in
            model.persistSettings()
            Task { await model.scan() }
        }
        .sheet(item: $review) { request in
            ReviewSheet(request: request)
        }
    }

    private var uninstallTitle: String {
        let count = model.selectedApps.count
        guard count > 0 else { return "Review & uninstall" }
        return "Review & uninstall \(count) app\(count == 1 ? "" : "s") · \(DiskSize.format(model.selectedAppsSize))"
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { model.selectedApps.contains(id) },
            set: { isOn in
                if isOn { model.selectedApps.insert(id) } else { model.selectedApps.remove(id) }
            }
        )
    }
}

private struct AppRow: View {
    let app: UnusedApp
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Toggle(app.name, isOn: $isOn)
                .toggleStyle(.checkbox)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.body.weight(.semibold))
                if app.hasDocuments {
                    Text("Holds documents you created")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.review)
                } else {
                    Text(app.bundleID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(lastOpened)
                .frame(width: 150, alignment: .leading)
            sizeColumn("App", app.appSize)
            sizeColumn("Its data", app.dataSize)
            Text(DiskSize.format(app.totalSize))
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }

    private var lastOpened: String {
        let days = app.daysUnused()
        if app.lastUsed == nil { return "Never opened · added \(days) days ago" }
        return "\(days) days ago"
    }

    private func sizeColumn(_ label: String, _ size: Int64) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(DiskSize.format(size)).monospacedDigit()
            Text(label).font(.caption2)
        }
        .foregroundStyle(.secondary)
        .frame(width: 80, alignment: .trailing)
    }
}
