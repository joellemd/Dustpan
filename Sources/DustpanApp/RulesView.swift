import AppKit
import DustpanCore
import SwiftUI

/// Read-only list of the cleanup rules in use, and a way to get to the folder for custom ones.
struct RulesView: View {
    @State private var rules: [Rule] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Rules").font(.system(size: 24, weight: .bold))
                    Text("What Dustpan looks for under Developer caches. Add your own by putting a JSON file in the rules folder.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open rules folder", action: openFolder)
            }

            ScrollView {
                Card {
                    ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                        if index > 0 { Divider() }
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.name).font(.system(size: 14, weight: .semibold))
                                Text(rule.paths.joined(separator: "  ·  "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text("Afterwards: \(rule.afterEffect)")
                            }
                            Spacer()
                            Text(rule.category.title).foregroundStyle(.secondary)
                            SafetyBadge(safety: rule.safety)
                                .frame(width: 64, alignment: .leading)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }
                .padding(1)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 28)
        .task { rules = RuleStore.all() }
    }

    private func openFolder() {
        let folder = RuleStore.userRulesDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }
}
