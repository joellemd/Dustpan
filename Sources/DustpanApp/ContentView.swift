import DustpanCore
import SwiftUI

enum Pane: String, Hashable {
    case overview, caches, projects, apps, toolchains, media, history, rules
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var pane: Pane? = .overview

    var body: some View {
        NavigationSplitView {
            List(selection: $pane) {
                Section("Clean") {
                    sidebarRow("Overview", icon: "square.grid.2x2", size: model.safeSize + model.reviewTotal)
                        .tag(Pane.overview)
                    sidebarRow("Developer caches", icon: "hammer", size: model.cacheSize)
                        .tag(Pane.caches)
                    sidebarRow("Project builds", icon: "folder", size: model.projectSize)
                        .tag(Pane.projects)
                }
                Section("Find") {
                    sidebarRow("Unused apps", icon: "app.dashed", size: model.appsSize)
                        .tag(Pane.apps)
                    sidebarRow("SDKs & toolchains", icon: "shippingbox", size: model.toolchainSize)
                        .tag(Pane.toolchains)
                    sidebarRow("Files & media", icon: "photo.on.rectangle", size: model.mediaSize)
                        .tag(Pane.media)
                }
                Section("Manage") {
                    Label("History & undo", systemImage: "clock.arrow.circlepath")
                        .tag(Pane.history)
                    Label("Rules", systemImage: "list.bullet.rectangle")
                        .tag(Pane.rules)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("Dustpan 0.1 · MIT\nNo network access. No telemetry.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            switch pane ?? .overview {
            case .overview: OverviewView(pane: $pane)
            case .caches: CachesView()
            case .projects: ProjectsView()
            case .rules: RulesView()
            case .apps: AppsView()
            case .toolchains: ToolchainsView()
            case .media: MediaView()
            case .history: HistoryView()
            }
        }
        .task {
            if model.lastScan == nil { await model.scan() }
        }
        .alert("Something went wrong", isPresented: errorShown) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.lastError ?? "")
        }
    }

    private var errorShown: Binding<Bool> {
        Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )
    }

    private func sidebarRow(_ title: String, icon: String, size: Int64) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            if size > 0 {
                Text(DiskSize.format(size))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

/// Blue "Safe" or orange "Review" tag. The word carries the meaning, not just the colour.
struct SafetyBadge: View {
    let safety: Safety

    var body: some View {
        Text(safety == .safe ? "Safe" : "Review")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(safety == .safe ? Theme.accent : Theme.review)
            .background(
                (safety == .safe ? Theme.accent : Theme.review).opacity(0.12),
                in: RoundedRectangle(cornerRadius: 5)
            )
    }
}

struct ScanStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.isScanning {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Scanning…")
            }
            .foregroundStyle(.secondary)
        } else if let last = model.lastScan {
            Text("Scanned \(last.formatted(date: .omitted, time: .shortened))")
                .foregroundStyle(.secondary)
        }
    }
}
