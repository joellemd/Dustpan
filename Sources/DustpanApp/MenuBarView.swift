import AppKit
import DustpanCore
import SwiftUI

/// The popover behind the menu bar icon: free space, what is safe to remove, one button.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var isCleaning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Dustpan").font(.headline)
                Spacer()
                ScanStatus().font(.caption)
            }

            if let disk = model.disk {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(DiskSize.format(disk.free)) free")
                            .font(.title2.weight(.bold))
                        Spacer()
                        Text("of \(DiskSize.format(disk.total))").foregroundStyle(.secondary)
                    }
                    StorageBar(
                        segments: [
                            .init(label: "Used", value: max(disk.used - model.safeSize, 0), color: Theme.usedSpace),
                            .init(label: "Safe to remove", value: model.safeSize, color: Theme.accent),
                            .init(label: "Free", value: disk.free, color: Color.primary.opacity(0.12)),
                        ],
                        height: 10
                    )
                }
            }

            if model.safeResults.isEmpty {
                Text(model.isScanning ? "Looking for things to clean…" : "Nothing safe to remove right now.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.safeResults.prefix(4)) { result in
                        HStack {
                            Text(result.rule.name)
                            Spacer()
                            Text(DiskSize.format(result.size))
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                        .padding(.vertical, 5)
                    }
                    if model.safeResults.count > 4 {
                        HStack {
                            Text("\(model.safeResults.count - 4) more").foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 5)
                    }
                }

                Button {
                    isCleaning = true
                    Task {
                        await model.clean(model.cacheReview(onlySafe: true).targets)
                        isCleaning = false
                    }
                } label: {
                    Text(isCleaning ? "Moving to Trash…" : "Clean \(DiskSize.format(model.safeSize)) of safe items")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isCleaning || model.isScanning)

                Text("Safe items go to the Trash and can be put back from History.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Button("Scan again") { Task { await model.scan() } }
                    .disabled(model.isScanning)
                Spacer()
                Button("Open Dustpan") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 340)
        .task {
            if model.lastScan == nil { await model.scan() }
        }
    }
}
