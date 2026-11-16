import AppKit
import DustpanCore
import SwiftUI

struct ProjectsView: View {
    @Environment(AppModel.self) private var model
    @State private var review: ReviewRequest?

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Project builds").font(.title.weight(.bold))
                    Text("Rebuildable folders inside projects you haven't touched in a while. Source code is never selected.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Review & clean \(DiskSize.format(model.selectedProjectSize))") {
                    review = model.projectReview()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedProjectSize == 0 || model.isScanning)
            }

            HStack(spacing: 12) {
                Picker("Untouched for", selection: $model.staleDays) {
                    Text("30+ days").tag(30)
                    Text("90+ days").tag(90)
                    Text("6+ months").tag(180)
                    Text("1+ year").tag(365)
                }
                .fixedSize()

                Menu("Scanning \(model.roots.count) folder\(model.roots.count == 1 ? "" : "s")") {
                    ForEach(model.roots, id: \.self) { root in
                        Button("Stop scanning \(root.path)") {
                            model.removeRoot(root)
                            Task { await model.scan() }
                        }
                    }
                }
                .fixedSize()

                Button("Add folder…", action: addFolder)
                ScanStatus()
            }

            if model.projects.isEmpty {
                if model.isScanning {
                    Spacer()
                } else {
                    ContentUnavailableView(
                        "No stale project builds",
                        systemImage: "folder",
                        description: Text(model.roots.isEmpty
                            ? "Add a folder that holds your projects."
                            : "Nothing in the scanned folders has sat untouched that long.")
                    )
                }
            } else {
                ColumnHeader(columns: [
                    ("Project", nil, .leading),
                    ("Rebuildable folders", 170, .leading),
                    ("Last change", 110, .leading),
                    ("Version control", 150, .leading),
                    ("Size", 80, .trailing),
                ])
                .padding(.bottom, -10)
                List(model.projects) { project in
                    ProjectRow(project: project, isOn: binding(for: project.id))
                }
                .listStyle(.inset(alternatesRowBackgrounds: false))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
            }

            Text("Projects with uncommitted work or no Git history are left unselected. A folder only counts as rebuildable when its project file sits next to it, for example package.json beside node_modules.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .onChange(of: model.staleDays) { _, _ in
            model.persistSettings()
            Task { await model.scan() }
        }
        .sheet(item: $review) { request in
            ReviewSheet(request: request)
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan this folder"
        if panel.runModal() == .OK, let url = panel.url {
            model.addRoot(url)
            Task { await model.scan() }
        }
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { model.selectedProjects.contains(id) },
            set: { isOn in
                if isOn { model.selectedProjects.insert(id) } else { model.selectedProjects.remove(id) }
            }
        )
    }
}

private struct ProjectRow: View {
    let project: StaleProject
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Toggle(project.name, isOn: $isOn)
                .toggleStyle(.checkbox)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name).font(.body.weight(.semibold))
                Text(project.url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(project.artifactNames)
                .lineLimit(1)
                .frame(width: 170, alignment: .leading)
            Text(project.lastChange.formatted(.relative(presentation: .named)))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(project.git.label)
                .fontWeight(project.git == .clean ? .regular : .semibold)
                .foregroundStyle(project.git == .clean ? Color.secondary : Theme.review)
                .frame(width: 150, alignment: .leading)
            Text(DiskSize.format(project.size))
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }
}
