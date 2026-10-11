import Foundation

extension CleanerModel {
    var selectedResources: [ManagedResource] {
        managedResources.filter { selectedResourceIDs.contains($0.id) }
    }

    var selectedResourceBytes: Int64 {
        selectedResources.reduce(0) { $0 + $1.sizeBytes }
    }

    func toggleResource(_ resource: ManagedResource, selected: Bool) {
        guard resource.canSelect else { return }
        if selected {
            selectedResourceIDs.insert(resource.id)
        } else {
            selectedResourceIDs.remove(resource.id)
        }
    }

    func refreshResources(startDocker: Bool = false) {
        guard !isScanningResources && !isRemovingResources else { return }
        isScanningResources = true
        resourceText = startDocker ? .message("Iniciando Docker…") : .message("Analizando recursos…")
        let startedAt = Date()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }

            let dockerInstalled = CleanerOperations.dockerExecutable() != nil
            let dockerProcessesRunning = CleanerOperations.runCommand(
                "/usr/bin/pgrep",
                arguments: ["-f", "com.docker.backend"],
                timeout: 2
            ).status == 0
            var dockerReady = CleanerOperations.runDocker(arguments: ["info"], timeout: 4).status == 0

            if startDocker && !dockerReady {
                _ = CleanerOperations.runCommand("/usr/bin/open", arguments: ["-gj", "-a", "Docker"])
                let deadline = Date().addingTimeInterval(30)
                while Date() < deadline {
                    Thread.sleep(forTimeInterval: 1)
                    if CleanerOperations.runDocker(arguments: ["info"], timeout: 3).status == 0 {
                        dockerReady = true
                        break
                    }
                }
            }

            let dockerResources = dockerReady ? CleanerOperations.discoverDockerResources() : []
            let xcodeResources = CleanerOperations.discoverXcodeResources()
            let resources = (dockerResources + xcodeResources).sorted {
                if $0.kind.rawValue == $1.kind.rawValue { return $0.sizeBytes > $1.sizeBytes }
                return $0.kind.rawValue < $1.kind.rawValue
            }

            DispatchQueue.main.async {
                self.managedResources = resources
                self.selectedResourceIDs = self.selectedResourceIDs.intersection(Set(resources.map(\.id)))
                if dockerReady {
                    self.dockerText = .count("docker.resources", dockerResources.count)
                } else if dockerProcessesRunning {
                    self.dockerText = .message("Docker abierto; motor sin respuesta")
                } else if dockerInstalled {
                    self.dockerText = .message("Docker está detenido")
                } else {
                    self.dockerText = .message("Docker no está instalado")
                }
                self.resourceText = resources.isEmpty
                    ? .message("No se encontraron recursos administrables")
                    : .count("resources.detected", resources.count)
                self.isScanningResources = false
                let elapsed = Date().timeIntervalSince(startedAt)
                self.appendLog(
                    String(
                        format: L10n.text("Recursos: análisis terminado en %.1f s; Docker %@; %d elementos."),
                        elapsed,
                        dockerReady ? L10n.text("activo") : L10n.text("detenido o sin respuesta"),
                        resources.count
                    )
                )
            }
        }
    }

    func confirmDockerRestart() {
        showingDockerRestartConfirmation = true
    }

    func restartDockerDesktop() {
        showingDockerRestartConfirmation = false
        guard !isScanningResources && !isRemovingResources else { return }
        isScanningResources = true
        resourceText = .message("Reiniciando el motor de Docker…")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = CleanerOperations.runDocker(
                arguments: ["desktop", "restart", "--detach", "--timeout", "20"],
                timeout: 25
            )
            if result.status == 0 {
                self.appendLogFromBackground(L10n.text("Docker Desktop: reinicio solicitado desde Recursos."))
            } else {
                let detail = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                self.appendLogFromBackground(L10n.text("ERROR al reiniciar Docker Desktop: \(detail)"))
            }

            DispatchQueue.main.async {
                self.isScanningResources = false
                self.refreshLogs()
                self.refreshResources(startDocker: true)
            }
        }
    }

    func confirmResourceRemoval() {
        guard !selectedResources.isEmpty else { return }
        showingResourceRemovalConfirmation = true
    }

    func removeSelectedResources() {
        let targets = selectedResources
        guard !targets.isEmpty else { return }
        showingResourceRemovalConfirmation = false
        isRemovingResources = true
        resourceText = .message("Eliminando recursos seleccionados…")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            for resource in targets {
                let result: (output: String, status: Int32)
                switch resource.kind {
                case .dockerImage:
                    result = CleanerOperations.runDocker(arguments: ["image", "rm", resource.identifier])
                case .dockerContainer:
                    result = CleanerOperations.runDocker(arguments: ["container", "rm", "--force", resource.identifier])
                case .dockerVolume:
                    result = CleanerOperations.runDocker(arguments: ["volume", "rm", resource.identifier])
                case .xcodeDevice:
                    result = CleanerOperations.runCommand("/usr/bin/xcrun", arguments: ["simctl", "delete", resource.identifier])
                case .xcodeRuntime:
                    result = CleanerOperations.runCommand("/usr/bin/xcrun", arguments: ["simctl", "runtime", "delete", resource.identifier])
                }

                if result.status == 0 {
                    self.appendLogFromBackground(L10n.text("Recurso eliminado: \(L10n.string(resource.kind.rawValue)) — \(resource.title)"))
                } else {
                    let detail = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.appendLogFromBackground(L10n.text("ERROR eliminando \(L10n.string(resource.kind.rawValue)) \(resource.title): \(detail)"))
                }
            }

            DispatchQueue.main.async {
                self.selectedResourceIDs.removeAll()
                self.isRemovingResources = false
                self.resourceText = .message("Eliminación terminada; revisa los logs")
                self.refreshStorage()
                self.refreshLogs()
                self.refreshResources()
                self.scanApplications()
            }
        }
    }

}
