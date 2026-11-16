import DustpanCore
import SwiftUI

struct CachesView: View {
    @Environment(AppModel.self) private var model
    @State private var review: ReviewRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if model.results.isEmpty {
                if model.isScanning {
                    Spacer()
                } else {
                    ContentUnavailableView(
                        "Nothing to clean",
                        systemImage: "sparkles",
                        description: Text("No developer caches or old logs were found.")
                    )
                }
            } else {
                List(model.results) { result in
                    RuleRow(result: result, isOn: binding(for: result.id))
                }
                .listStyle(.inset(alternatesRowBackgrounds: false))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
            }

            Text("Everything goes to the Trash first, so any clean can be undone from History until you empty the Trash.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .sheet(item: $review) { request in
            ReviewSheet(request: request)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Developer caches")
                    .font(.title.weight(.bold))
                HStack(spacing: 8) {
                    if model.reviewSize > 0 {
                        Text("Another \(DiskSize.format(model.reviewSize)) needs a look from you first.")
                            .foregroundStyle(.secondary)
                    }
                    ScanStatus()
                }
            }
            Spacer()
            Button("Scan again") {
                Task { await model.scan() }
            }
            .disabled(model.isScanning)

            Button("Review & clean \(DiskSize.format(model.selectedCacheSize))") {
                review = model.cacheReview()
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.selectedCacheSize == 0 || model.isScanning)
        }
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { model.selectedRules.contains(id) },
            set: { isOn in
                if isOn { model.selectedRules.insert(id) } else { model.selectedRules.remove(id) }
            }
        )
    }
}

private struct RuleRow: View {
    let result: RuleResult
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Toggle(result.rule.name, isOn: $isOn)
                .toggleStyle(.checkbox)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(result.rule.name).font(.body.weight(.semibold))
                Text(result.rule.summary).foregroundStyle(.secondary)
            }
            Spacer()
            SafetyBadge(safety: result.rule.safety)
            Text(DiskSize.format(result.size))
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .frame(width: 90, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }
}
