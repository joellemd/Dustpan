import DustpanCore
import SwiftUI

struct HistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("History & undo").font(.title.weight(.bold))
                Text("Everything Dustpan has moved to the Trash. Items can be put back until you empty the Trash.")
                    .foregroundStyle(.secondary)
            }

            if model.history.isEmpty {
                ContentUnavailableView(
                    "Nothing cleaned yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Cleans will be listed here.")
                )
            } else {
                List(model.history) { entry in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.label).font(.body.weight(.semibold))
                            Text(entry.originalPath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                        Text(DiskSize.format(entry.size))
                            .monospacedDigit()
                            .frame(width: 80, alignment: .trailing)
                        if entry.restored {
                            Text("Put back")
                                .foregroundStyle(.secondary)
                                .frame(width: 80)
                        } else {
                            Button("Put back") { model.undo(entry) }
                                .disabled(!entry.canRestore)
                                .frame(width: 80)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset(alternatesRowBackgrounds: false))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
            }
        }
        .padding(24)
    }
}
