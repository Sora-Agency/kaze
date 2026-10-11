import Foundation
import AppKit

extension CleanerModel {
    func scanApplications() {
        guard !isScanningApps else { return }
        isScanningApps = true
        let home = fileManager.homeDirectoryForCurrentUser

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let result = CleanerOperations.discoverApplications(home: home)
            DispatchQueue.main.async {
                self.applications = result.sorted { $0.totalBytes > $1.totalBytes }
                self.selectedApplicationIDs = self.selectedApplicationIDs.intersection(Set(result.map(\.id)))
                let currentDataIDs = Set(result.flatMap(\.relatedData).map(\.id))
                self.selectedApplicationDataIDs = self.selectedApplicationDataIDs.intersection(currentDataIDs)
                self.expandedApplicationIDs = self.expandedApplicationIDs.intersection(Set(result.map(\.id)))
                self.expandedDataItemIDs.removeAll()
                self.directoryChildren.removeAll()
                self.loadingDataItemIDs.removeAll()
                self.directoryLoadErrors.removeAll()
                self.isScanningApps = false
            }
        }
    }

    func toggleSelection(for application: InstalledApplication, selected: Bool) {
        if selected {
            selectedApplicationIDs.insert(application.id)
            selectedApplicationDataIDs = Set(selectedApplicationDataIDs.filter { selectedID in
                !application.relatedData.contains { root in
                    selectedID == root.id || selectedID.hasPrefix(root.id + "/")
                }
            })
        } else {
            selectedApplicationIDs.remove(application.id)
        }
    }

    func setExpanded(_ application: InstalledApplication, expanded: Bool) {
        if expanded {
            expandedApplicationIDs.insert(application.id)
        } else {
            expandedApplicationIDs.remove(application.id)
        }
    }

    func toggleApplicationData(_ item: ApplicationDataItem, for application: InstalledApplication, selected: Bool) {
        guard !selectedApplicationIDs.contains(application.id) else { return }
        if selected {
            guard !hasSelectedDataAncestor(of: item) else { return }
            selectedApplicationDataIDs = Set(
                selectedApplicationDataIDs.filter { !$0.hasPrefix(item.id + "/") }
            )
            selectedApplicationDataIDs.insert(item.id)
        } else {
            selectedApplicationDataIDs.remove(item.id)
        }
    }

    func hasSelectedDataAncestor(of item: ApplicationDataItem) -> Bool {
        selectedApplicationDataIDs.contains { selectedID in
            item.id.hasPrefix(selectedID + "/")
        }
    }

    func children(of item: ApplicationDataItem) -> [ApplicationDataItem] {
        sortedData(directoryChildren[item.id] ?? [])
    }

    func sortedData(_ items: [ApplicationDataItem]) -> [ApplicationDataItem] {
        items.sorted {
            dataOrder.sorts(
                FileEntry(url: $0.url, isDirectory: $0.isDirectory, isSymbolicLink: false, modified: nil, measurement: DiskMeasurement(bytes: $0.bytes)),
                FileEntry(url: $1.url, isDirectory: $1.isDirectory, isSymbolicLink: false, modified: nil, measurement: DiskMeasurement(bytes: $1.bytes))
            )
        }
    }

    func toggleDataItemExpansion(_ item: ApplicationDataItem) {
        guard item.isDirectory else { return }
        if expandedDataItemIDs.contains(item.id) {
            expandedDataItemIDs.remove(item.id)
            return
        }

        expandedDataItemIDs.insert(item.id)
        guard directoryChildren[item.id] == nil,
              !loadingDataItemIDs.contains(item.id) else { return }
        loadingDataItemIDs.insert(item.id)
        directoryLoadErrors[item.id] = nil

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = CleanerOperations.discoverDirectoryChildren(of: item)
            DispatchQueue.main.async {
                guard let self else { return }
                self.directoryChildren[item.id] = result.items
                self.loadingDataItemIDs.remove(item.id)
                self.directoryLoadErrors[item.id] = result.error
            }
        }
    }

    var selectedApplications: [InstalledApplication] {
        applications.filter { selectedApplicationIDs.contains($0.id) }
    }

    var selectedTotalBytes: Int64 {
        selectedApplications.reduce(0) { $0 + $1.totalBytes }
    }

    var selectedApplicationData: [(application: InstalledApplication, item: ApplicationDataItem)] {
        let allItems = applications.flatMap(\.relatedData) + directoryChildren.values.flatMap { $0 }
        var itemsByID: [String: ApplicationDataItem] = [:]
        for item in allItems { itemsByID[item.id] = item }
        let applicationsByID = Dictionary(uniqueKeysWithValues: applications.map { ($0.id, $0) })
        return selectedApplicationDataIDs.compactMap { id in
            guard let item = itemsByID[id],
                  let application = applicationsByID[item.applicationID] else { return nil }
            return (application, item)
        }
    }

    var selectedApplicationDataBytes: Int64 {
        selectedApplicationData.reduce(0) { $0 + $1.item.bytes }
    }

    func confirmRemoval() {
        guard !selectedApplications.isEmpty else { return }
        showingRemovalConfirmation = true
    }

    func removeSelectedApplications() {
        let targets = selectedApplications
        guard !targets.isEmpty else { return }
        showingRemovalConfirmation = false
        isScanningApps = true
        progressText = .message("Moviendo aplicaciones a la Papelera…")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            for application in targets {
                if let bundleIdentifier = application.bundleIdentifier {
                    NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                        .forEach { _ = $0.terminate() }
                    Thread.sleep(forTimeInterval: 0.5)
                }

                self.appendLogFromBackground(L10n.text("Desinstalación: \(application.name)"))
                CleanerOperations.recycle(application.url, label: L10n.text("aplicación \(application.name)"))

                for relatedURL in application.relatedURLs {
                    CleanerOperations.recycle(relatedURL, label: L10n.text("dato relacionado de \(application.name)"))
                }
            }

            DispatchQueue.main.async {
                self.selectedApplicationIDs.removeAll()
                self.isScanningApps = false
                self.progressText = .message("Aplicaciones movidas a la Papelera")
                self.refreshStorage()
                self.refreshLogs()
                self.scanApplications()
            }
        }
    }

    func confirmApplicationDataRemoval() {
        guard !selectedApplicationData.isEmpty else { return }
        showingDataRemovalConfirmation = true
    }

    func removeSelectedApplicationData() {
        let targets = selectedApplicationData
        guard !targets.isEmpty else { return }
        showingDataRemovalConfirmation = false
        isRemovingApplicationData = true
        progressText = .message("Moviendo datos seleccionados a la Papelera…")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let grouped = Dictionary(grouping: targets, by: { $0.application.id })

            for entries in grouped.values {
                guard let application = entries.first?.application else { continue }
                if let bundleIdentifier = application.bundleIdentifier {
                    NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                        .forEach { _ = $0.terminate() }
                    Thread.sleep(forTimeInterval: 0.5)
                }

                for entry in entries {
                    CleanerOperations.recycle(entry.item.url, label: L10n.text("dato de \(application.name)"))
                }
            }

            DispatchQueue.main.async {
                self.selectedApplicationDataIDs.removeAll()
                self.isRemovingApplicationData = false
                self.progressText = .message("Datos seleccionados movidos a la Papelera")
                self.refreshStorage()
                self.refreshLogs()
                self.scanApplications()
            }
        }
    }

}
