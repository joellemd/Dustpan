import AppKit
import DustpanCore
import SwiftUI

struct MediaView: View {
    @Environment(AppModel.self) private var model
    @State private var review: ReviewRequest?

    /// Long groups show only their largest files; selecting the group still selects all of them.
    private let visibleLimit = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Files & media").font(.title.weight(.bold))
                    HStack(spacing: 8) {
                        Text("Your own files that take the most space. Nothing here is selected for you.")
                            .foregroundStyle(.secondary)
                        ScanStatus()
                    }
                }
                Spacer()
                Button("Review & clean \(DiskSize.format(model.selectedMediaSize))") {
                    review = model.mediaReview()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedMediaSize == 0 || model.isScanning)
            }

            if !model.media.isEmpty {
                StorageBar(segments: typeSegments)
            }

            if model.media.isEmpty {
                if model.isScanning {
                    Spacer()
                } else {
                    ContentUnavailableView(
                        "Nothing large or redundant found",
                        systemImage: "photo.on.rectangle",
                        description: Text("Looked in Downloads, Desktop, Documents, Movies and Pictures.")
                    )
                }
            } else {
                List(model.media) { group in
                    DisclosureGroup {
                        ForEach(group.items.prefix(visibleLimit)) { item in
                            FileRow(item: item, isOn: binding(for: item.id))
                        }
                        if group.items.count > visibleLimit {
                            Text("\(group.items.count - visibleLimit) smaller files not shown")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } label: {
                        GroupRow(group: group, isOn: binding(for: group))
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: false))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
            }

            Text("Your Photos library is never opened or changed; manage it in Photos. Folders that look like code projects are skipped.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .sheet(item: $review) { request in
            ReviewSheet(request: request)
        }
    }

    /// The bar at the top: space by kind of file, as in the design.
    private var typeSegments: [StorageBar.Segment] {
        func size(_ ids: [String]) -> Int64 {
            model.media.filter { ids.contains($0.id) }.reduce(0) { $0 + $1.size }
        }
        let kinds: [(String, [String], Color)] = [
            ("Videos", ["screen-recordings", "large-videos"], Theme.videos),
            ("Images", ["large-images", "duplicate-images", "old-screenshots"], Theme.images),
            ("Installers", ["installers"], Theme.installers),
            ("Phone backups", ["phone-backups"], Theme.backups),
            ("Archives", ["unpacked-archives"], Theme.archives),
        ]
        return kinds.map { kind in
            let bytes = size(kind.1)
            return StorageBar.Segment(label: "\(kind.0) \(DiskSize.format(bytes))", value: bytes, color: kind.2)
        }
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { model.selectedMedia.contains(id) },
            set: { isOn in
                if isOn { model.selectedMedia.insert(id) } else { model.selectedMedia.remove(id) }
            }
        )
    }

    /// On when every file in the group is selected.
    private func binding(for group: MediaGroup) -> Binding<Bool> {
        let ids = group.items.map { $0.id }
        return Binding(
            get: { !ids.isEmpty && ids.allSatisfy { model.selectedMedia.contains($0) } },
            set: { isOn in
                if isOn { model.selectedMedia.formUnion(ids) } else { model.selectedMedia.subtract(ids) }
            }
        )
    }
}

private struct GroupRow: View {
    let group: MediaGroup
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Toggle(group.title, isOn: $isOn)
                .toggleStyle(.checkbox)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(group.title).font(.body.weight(.semibold))
                if let warning = group.warning {
                    Text(warning)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.review)
                } else {
                    Text(group.detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(group.items.count) item\(group.items.count == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
            Text(DiskSize.format(group.size))
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .frame(width: 90, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }
}

private struct FileRow: View {
    let item: ScanItem
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Toggle(item.url.lastPathComponent, isOn: $isOn)
                .toggleStyle(.checkbox)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 1) {
                Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Text(item.url.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if let modified = item.modified {
                Text(modified.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(.secondary)
            }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            .buttonStyle(.link)
            Text(DiskSize.format(item.size))
                .monospacedDigit()
                .frame(width: 90, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}
