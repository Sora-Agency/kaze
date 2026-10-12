import SwiftUI

struct ApplicationDataTreeNode: View {
    @ObservedObject private var language = AppLanguageStore.shared
    @ObservedObject var model: CleanerModel
    let application: InstalledApplication
    let item: ApplicationDataItem
    let depth: Int

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Group {
                    if model.loadingDataItemIDs.contains(item.id) {
                        SoraSpinner()
                            .controlSize(.mini)
                            .frame(width: 18, height: 30)
                    } else if item.isDirectory {
                        Button {
                            model.toggleDataItemExpansion(item)
                        } label: {
                            LucideIcon(model.expandedDataItemIDs.contains(item.id)
                                  ? "chevron-down" : "chevron-right")
                                .font(SoraTypography.body(11, weight: .semibold))
                                .frame(width: 18, height: 30)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(width: 18, height: 30)
                    }
                }

                Toggle(L10n.text("Seleccionar \(item.url.lastPathComponent)"), isOn: Binding(
                    get: { model.selectedApplicationDataIDs.contains(item.id) },
                    set: { model.toggleApplicationData(item, for: application, selected: $0) }
                ))
                .labelsHidden()
                .toggleStyle(SoraCheckboxStyle(showsLabel: false))
                .disabled(
                    !item.canRemove || model.selectedApplicationIDs.contains(application.id)
                    || model.hasSelectedDataAncestor(of: item)
                    || model.isRemovingApplicationData
                )

                LucideIcon(item.isDirectory ? "folder" : "file")
                    .foregroundStyle(item.isDirectory ? Color.accentColor : Color.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.url.lastPathComponent)
                        .font(.callout.weight(.medium))
                    Text(item.evidence.string).font(SoraTypography.body(10)).foregroundStyle(item.canRemove ? SoraPalette.secondary : Color.orange)
                    if !item.sharedWith.isEmpty { Text(L10n.text("Compartido con \(item.sharedWith.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", "))")).font(SoraTypography.body(10)).foregroundStyle(SoraPalette.secondary) }
                    Text(item.displayPath)
                        .font(SoraTypography.body(12))
                        .foregroundStyle(SoraPalette.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(SoraPalette.secondary)
            }
            .padding(.leading, CGFloat(depth) * 22)
            .padding(.vertical, 3)

            if item.isDirectory && model.expandedDataItemIDs.contains(item.id) {
                if let error = model.directoryLoadErrors[item.id] {
                    Text(error)
                        .font(SoraTypography.body(12))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, CGFloat(depth + 1) * 22 + 60)
                        .padding(.vertical, 5)
                }

                if !model.loadingDataItemIDs.contains(item.id) {
                    let children = model.children(of: item)
                    if children.isEmpty && model.directoryLoadErrors[item.id] == nil {
                        Text(L10n.text("Carpeta vacía"))
                            .font(SoraTypography.body(12))
                            .foregroundStyle(SoraPalette.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, CGFloat(depth + 1) * 22 + 60)
                            .padding(.vertical, 5)
                    } else {
                        ForEach(children) { child in
                            SoraDivider().padding(.leading, CGFloat(depth + 1) * 22 + 52)
                            ApplicationDataTreeNode(
                                model: model,
                                application: application,
                                item: child,
                                depth: depth + 1
                            )
                        }
                    }
                }
            }
        }
        .soraAnimate(model.expandedDataItemIDs)
    }
}
