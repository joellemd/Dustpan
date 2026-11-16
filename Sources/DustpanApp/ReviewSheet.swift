import AppKit
import DustpanCore
import SwiftUI

/// The confirmation step. Nothing is moved until the user presses the button here.
struct ReviewSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: ReviewRequest
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Move \(DiskSize.format(request.size)) to the Trash?")
                    .font(.title2.weight(.bold))
                Text("\(request.targets.count) item\(request.targets.count == 1 ? "" : "s"). Nothing is erased until you empty the Trash.")
                    .foregroundStyle(.secondary)
            }

            List(request.lines) { line in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(line.title).font(.body.weight(.semibold))
                        Text(line.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                        Text("Afterwards: \(line.afterEffect)")
                    }
                    Spacer()
                    Text(DiskSize.format(line.size))
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                }
                .padding(.vertical, 4)
            }
            .listStyle(.inset(alternatesRowBackgrounds: false))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))

            HStack {
                if isWorking {
                    ProgressView().controlSize(.small)
                    Text("Moving to Trash…").foregroundStyle(.secondary)
                }
                Button("Export dry-run report…", action: exportReport)
                    .disabled(isWorking)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isWorking)
                Button("Move to Trash") {
                    isWorking = true
                    Task {
                        await model.clean(request.targets)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isWorking)
            }
        }
        .padding(24)
        .frame(width: 640, height: 560)
    }

    /// Saves the full list of paths as a text file without moving anything.
    private func exportReport() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "dustpan-dry-run.txt"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try DryRunReport.text(for: request.targets).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            model.lastError = error.localizedDescription
        }
    }
}
