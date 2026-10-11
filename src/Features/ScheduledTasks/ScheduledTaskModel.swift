import Foundation
import Combine

@MainActor
final class ScheduledTaskModel: ObservableObject {
    static let shared = ScheduledTaskModel()
    @Published private(set) var tasks: [ScheduledCleanupTask] = []
    @Published private(set) var registeredIDs = Set<UUID>()
    @Published private(set) var isSaving = false
    @Published private(set) var canManage = true
    @Published var error: String?
    private let service: ScheduleService
    private let queue = DispatchQueue(label: "kaze.schedule", qos: .utility)
    init(service: ScheduleService = ScheduleService(), inspectSystem: Bool = true) {
        self.service = service
        do {
            if inspectSystem { try service.prepareForUse() }
            tasks = try service.load()
            if inspectSystem { registeredIDs = try service.registeredIDs(in: tasks) }
        } catch { self.error = error.localizedDescription; canManage = false }
    }
    func isEnabled(_ task: ScheduledCleanupTask) -> Bool { registeredIDs.contains(task.id) }
    func refreshStatus() {
        guard !isSaving, canManage else { return }
        let current = tasks
        queue.async { [weak self, service] in
            do {
                let ids = try service.registeredIDs(in: current)
                DispatchQueue.main.async { [weak self] in self?.registeredIDs = ids.intersection(Set(self?.tasks.map(\.id) ?? [])) }
            } catch { DispatchQueue.main.async { [weak self] in self?.error = error.localizedDescription } }
        }
    }
    func upsert(_ task: ScheduledCleanupTask, completion: (() -> Void)? = nil) {
        var next = tasks
        if let index = next.firstIndex(where: { $0.id == task.id }) { next[index] = task }
        else { next.append(task) }
        apply(next, completion: completion)
    }
    func setEnabled(_ id: UUID, _ enabled: Bool) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        var next = tasks; next[index].configuration.enabled = enabled
        apply(next)
    }
    func delete(_ id: UUID) { apply(tasks.filter { $0.id != id }) }
    private func apply(_ next: [ScheduledCleanupTask], completion: (() -> Void)? = nil) {
        guard !isSaving, canManage else { return }
        do { try ScheduleCollection(tasks: next).validate() } catch { self.error = error.localizedDescription; return }
        isSaving = true; error = nil
        queue.async { [weak self, service] in
            do {
                try service.saveTasks(next)
                let ids = Set(next.filter { $0.configuration.enabled }.map(\.id))
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.tasks = next; self.registeredIDs = ids; self.isSaving = false
                    completion?()
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isSaving = false; self.error = error.localizedDescription; self.refreshStatus()
                }
            }
        }
    }
}
