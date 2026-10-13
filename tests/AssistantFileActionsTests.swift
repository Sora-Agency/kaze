import Foundation
import CryptoKit

@main
struct AssistantFileActionsTests {
    static func check(_ value: @autoclosure () -> Bool, _ label: String) {
        precondition(value(), label); print("PASS: \(label)")
    }
    @MainActor static func wait(_ predicate: () -> Bool) {
        let deadline = Date().addingTimeInterval(10)
        while !predicate() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        check(predicate(), "Assistant file operation completes")
    }
    @MainActor static func main() throws {
        let fm = FileManager.default
        let home = URL(fileURLWithPath: canonicalFilePath(fm.temporaryDirectory)).appendingPathComponent("kaze-agent-\(UUID())")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }
        let url = home.appendingPathComponent("Documents/example.bin")
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("private fixture".utf8).write(to: url)
        let info = DiskScanner.metadata(url)!
        let file = IndexedFile(url: url, parent: nil, directory: false, symbolicLink: false, protected: false,
            fingerprint: StorageIndexer.fingerprint(info), links: 1, ownAllocated: 4096, logical: 15,
            allocated: 100_000_000, modified: Date())
        let index = StorageIndex(date: Date(), roots: [home], home: home, files: [file], children: [-1: [0]], byPath: [url.path: 0])
        let resources = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("src")
        let catalog = try RuleCatalog(directory: resources.appendingPathComponent("Rules"))
        let journal = OperationJournal(home: home, leaseURL: home.appendingPathComponent("fixture.lock"))
        let analysis = SmartScanModel(home: home, resources: resources, initialIndex: index, journal: journal)
        let candidates = AssistantFileProposal.candidates(index: index, findings: analysis.findings, question: "Review example")
        check(candidates.count == 1, "Only an indexed eligible item becomes a candidate")
        for question in ["hola", "hello", "¿Por qué crece System Data?", "no quiero borrar nada", "don't delete anything"] {
            check(AssistantFileProposal.candidates(index: index, findings: analysis.findings, question: question).isEmpty,
                  "Greetings, informational questions and refusals never offer file actions")
        }
        var visits = 0
        let interrupted = AssistantFileProposal.candidates(index: index, findings: analysis.findings, question: "delete", cancelled: {
            visits += 1; return true
        })
        check(interrupted.isEmpty && visits == 1, "Cancellation stops candidate preparation before retaining actions")
        var large = index
        large.files = (0..<30).map { number in
            IndexedFile(url: url.deletingLastPathComponent().appendingPathComponent("example-\(number).bin"),
                parent: nil, directory: false, symbolicLink: false, protected: false, fingerprint: file.fingerprint,
                links: 1, ownAllocated: 4096, logical: 15, allocated: Int64(number + 1) * 100_000_000, modified: Date())
        }
        let many = large.files.indices.map { StorageFinding(node: $0, group: .review, rule: nil, potential: 0) }
        let bounded = AssistantFileProposal.candidates(index: large, findings: many + many, question: "review")
        check(bounded.count == 6 && Set(bounded.map { $0.file.id }).count == 6 && bounded[0].file.url.lastPathComponent == "example-29.bin",
              "Bounded selection retains late high-priority files without duplicate proposals")
        let reply = "{\"answer\":\"Review this file before approving.\",\"proposals\":[\"file_1\"]}"
        check(AssistantReply.parse(reply, candidates: candidates).proposals.first?.file.url == url, "Structured IDs resolve to measured files")
        for raw in ["delete " + url.path, "{\"answer\":\"Done\",\"proposals\":[\"/etc/passwd\"]}",
                    "{\"answer\":\"Done\",\"proposals\":[\"file_1\"],\"command\":\"rm\"}",
                    "{\"answer\":\"Done\",\"proposals\":[\"file_1\",\"unknown\"]}", String(reply.dropLast())] {
            check(AssistantReply.parse(raw, candidates: candidates).proposals.isEmpty, "Commands, invented paths, unknown IDs and incomplete JSON cannot authorize actions")
        }
        var guarded = index
        var protectedFile = file; protectedFile.containsProtected = true
        guarded.files = [protectedFile]
        check(AssistantFileProposal.candidates(index: guarded, findings: analysis.findings, question: "delete").isEmpty,
              "Protected descendants are excluded from proposals")
        let engineFolder = home.appendingPathComponent("fixture-engine")
        try fm.createDirectory(at: engineFolder, withIntermediateDirectories: true)
        let executable = engineFolder.appendingPathComponent("llama-completion")
        let fixture = """
        #!/bin/sh
        schema_seen=no
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --json) exit 1 ;;
            --json-schema) schema_seen=yes ;;
          esac
          shift
        done
        [ "$schema_seen" = yes ] || exit 1
        printf '%s\\n' '\(reply)'
        """
        try fixture.write(to: executable, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let archive = home.appendingPathComponent("engine.tar.gz")
        let packed = CleanerOperations.runCommand("/usr/bin/tar", arguments: ["-czf", archive.path, "-C", home.path, "fixture-engine"], timeout: 5)
        check(packed.status == 0, "Temporary inference fixture archived")
        let engine = try Data(contentsOf: archive), model = Data("fixture model".utf8)
        func asset(_ bytes: Data, name: String) -> LocalAIAsset {
            LocalAIAsset(url: URL(string: "https://example.invalid/" + name)!, bytes: Int64(bytes.count),
                sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), filename: name)
        }
        let package = LocalAIPackage(version: "fixture", engine: asset(engine, name: "engine.tar.gz"),
            model: asset(model, name: "model.gguf"), engineFolder: "fixture-engine")
        let service = LocalAIService(home: home, package: package) { asset, destination, _, _ in
            try (asset.filename == "model.gguf" ? model : engine).write(to: destination)
        }
        try service.install(cancellation: ScanCancellation(), progress: { _ in })
        let conversationStore = AssistantChatStore(directory: home.appendingPathComponent("ChatFixture"))
        let assistant = LocalAssistantModel(service: service, chatStore: conversationStore)
        assistant.checkAvailability(); wait { assistant.phase == .ready && !assistant.chats.isLoading }
        assistant.ask("hola", analysis: analysis)
        check(!assistant.isGenerating && assistant.response.hasPrefix("Hola.") && assistant.proposals.isEmpty,
              "Greeting replies locally without launching inference or requiring cleanup approval")
        check(assistant.activity.steps.map(\.kind) == [.greeting], "A local greeting records no invented analysis or inference")
        var moves = 0
        let trashService = ReviewedTrashService(home: home, catalog: catalog, runningProcesses: { ("", 0) }, move: { item in
            moves += 1
            let destination = home.appendingPathComponent(".Trash/\(UUID())")
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: item, to: destination); return destination
        })
        let trash = ReviewedTrashModel(service: trashService, journal: journal,
            authorization: { assistant.canReview($0, analysis: analysis) })
        assistant.ask("Delete example.bin", analysis: analysis); wait { !assistant.isGenerating }
        check(assistant.proposals.count == 1 && moves == 0 && fm.fileExists(atPath: url.path), "AI proposals never move files automatically")
        check(assistant.activity.steps.map(\.kind) == [.context, .files, .response, .proposals]
            && assistant.activity.steps.allSatisfy { $0.status == .completed }, "Activity records the actual query stages in order")
        check(assistant.activity.steps.first { $0.kind == .files }?.checked == 1
            && !assistant.activity.steps.contains { $0.kind == .trash }, "Activity reports real metadata checks and never claims an unapproved move")
        let target = assistant.proposals[0].target
        let rememberedChat = assistant.chats.archive.selectedID!
        assistant.chats.flush()
        let reopened = LocalAssistantModel(service: service, chatStore: conversationStore)
        reopened.checkAvailability(); wait { reopened.phase == .ready && !reopened.chats.isLoading }
        check(reopened.response == assistant.response && reopened.chats.turns.count == assistant.chats.turns.count,
              "Restart restores conversation text without generating a new answer")
        check(reopened.proposals.isEmpty && !reopened.canReview(target, analysis: analysis),
              "Restored conversations never restore old deletion authority")
        reopened.newChat(); reopened.ask("hola", analysis: analysis)
        check(reopened.chats.turns.count == 1 && reopened.chats.archive.selectedID != rememberedChat,
              "A new chat starts with isolated memory")
        reopened.selectChat(rememberedChat)
        check(reopened.response == assistant.response && reopened.proposals.isEmpty,
              "Selecting a saved chat restores its final response but no actionable proposal")
        trash.request(target); wait { !trash.busy }
        check(trash.pending != nil && moves == 0, "Review opens a confirmation without deleting")
        trash.dismiss()
        check(fm.fileExists(atPath: url.path) && moves == 0, "Cancelling preserves the proposed file")
        trash.request(target); wait { !trash.busy }
        assistant.ask("Review example again", analysis: analysis); wait { !assistant.isGenerating }
        trash.confirm(contentsReviewed: true) { _ in fatalError("Previous query approval executed") }
        check(moves == 0 && trash.pending == nil && !assistant.canReview(target, analysis: analysis),
              "Another query revokes previous approvals even for the same file")
        trash.request(assistant.proposals[0].target); wait { !trash.busy }
        analysis.markChanged()
        trash.confirm(contentsReviewed: true) { _ in fatalError("Stale approval executed") }
        check(moves == 0 && trash.pending == nil, "An analysis change revokes a pending AI approval")
        assistant.ask("Que mas cosas puedo eliminar?", analysis: analysis); wait { !assistant.isGenerating }
        check(assistant.error == nil && assistant.contextNotice != nil && assistant.proposals.count == 1,
              "An old analysis still answers follow-up questions with freshly checked file proposals")
        check(assistant.canReview(assistant.proposals[0].target, analysis: analysis), "An unchanged file can be reviewed without rescanning the disk")
        assistant.ask("Delete example.bin", analysis: analysis)
        analysis.markChanged(); wait { !assistant.isGenerating }
        check(!assistant.response.isEmpty && assistant.error == nil && assistant.proposals.isEmpty,
              "A change during inference preserves the explanation while revoking action authority")
        let cache = AnalysisCache(home: home)
        let rootInfo = DiskScanner.metadata(home)!
        let rootFile = IndexedFile(url: home, parent: nil, directory: true, symbolicLink: false, protected: false,
            fingerprint: StorageIndexer.fingerprint(rootInfo), links: 1, ownAllocated: 4096,
            logical: file.logical, allocated: file.allocated, modified: Date())
        let childFile = IndexedFile(url: file.url, parent: 0, directory: false, symbolicLink: false, protected: false,
            fingerprint: file.fingerprint, links: 1, ownAllocated: file.ownAllocated,
            logical: file.logical, allocated: file.allocated, modified: file.modified)
        let savedIndex = StorageIndex(date: index.date, roots: [home], home: home, files: [rootFile, childFile], scannedCount: 2)
        check(cache.saveAnalysis(CachedStorageAnalysis(schema: 1, index: savedIndex, duplicates: DuplicateReport(), snapshots: [], snapshotStatus: "Sin analizar")),
              "Fixture baseline is saved without rescanning")
        let restoredAnalysis = SmartScanModel(home: home, resources: resources, journal: journal, cache: cache)
        wait { !restoredAnalysis.isRestoring }
        assistant.ask("Que mas cosas puedo eliminar?", analysis: restoredAnalysis); wait { !assistant.isGenerating }
        check(restoredAnalysis.showingCached && assistant.error == nil && assistant.proposals.count == 1,
              "A restored baseline allows the assistant to continue without another Smart Scan")
        let current = SmartScanModel(home: home, resources: resources, initialIndex: index, journal: journal)
        let authorized = ReviewedTrashModel(service: trashService, journal: journal,
            authorization: { assistant.canReview($0, analysis: current) })
        assistant.ask("Delete example.bin", analysis: current); wait { !assistant.isGenerating }
        authorized.request(assistant.proposals[0].target); wait { !authorized.busy }
        assistant.recordReview(authorized.pending!.target)
        let originChat = assistant.chats.archive.selectedID!, originTurn = assistant.currentTurnID!
        authorized.confirm(contentsReviewed: true) { moved in assistant.newChat(); assistant.recordMove(moved); current.markChanged() }
        wait { !authorized.busy }
        check(moves == 1 && assistant.proposals.isEmpty, "Only explicit confirmation moves the exact file and consumes its proposal")
        let origin = assistant.chats.archive.chats.first { $0.id == originChat }!.turns.first { $0.id == originTurn }!
        check(assistant.chats.turns.isEmpty && assistant.activity.steps.isEmpty
            && origin.activity.last?.kind == .trash && origin.activity.last?.paths == [url],
              "A successful move finishing after chat selection is recorded with its exact target in the originating chat")
        assistant.ask("Que mas cosas puedo eliminar?", analysis: current); wait { !assistant.isGenerating }
        check(assistant.error == nil && !assistant.response.isEmpty && assistant.proposals.isEmpty,
              "After deletion the conversation continues and missing files are excluded from proposals")
        let record = try journal.records().first!
        try journal.restore(record)
        check(fm.fileExists(atPath: url.path), "An approved AI action is reversible through History")
        authorized.request(target)
        check(authorized.pending == nil && moves == 1, "Old proposals cannot be reused after restoration")
        let before = assistant.activity.steps
        assistant.recordReview(target)
        check(assistant.activity.steps == before, "An obsolete confirmation cannot overwrite the current chat's review provenance")
        if CommandLine.arguments.contains("--real-model") {
            let real = LocalAIService()
            let questions = [("¿Qué diferencia hay entre tamaño lógico y espacio asignado?", false),
                ("Quiero mover example.bin a la Papelera. Propón la acción para que pueda revisarla y confirmarla.", false),
                ("Que mas cosas puedo eliminar?", true)]
            let latestInfo = DiskScanner.metadata(url)!
            let latestFile = IndexedFile(url: url, parent: nil, directory: false, symbolicLink: false, protected: false,
                fingerprint: StorageIndexer.fingerprint(latestInfo), links: 1, ownAllocated: file.ownAllocated,
                logical: file.logical, allocated: file.allocated, modified: file.modified)
            let historical = StorageIndex(date: index.date.addingTimeInterval(-3600), roots: [home], home: home, files: [latestFile])
            for (question, stale) in questions {
                let proposed = AssistantFilePlanner.plan(index: historical, findings: analysis.findings, question: question,
                    catalog: catalog, cancellation: ScanCancellation()).candidates
                let prompt = LocalAssistantPrompt.make(question: question, index: historical, findings: analysis.findings,
                    totals: [:], systemPotential: [:], potential: 0, stale: stale, english: false, candidates: proposed)
                let response = try real.answer(prompt: prompt, cancellation: ScanCancellation(), responseSchema: AssistantReply.schema(candidates: proposed))
                let json = try JSONSerialization.jsonObject(with: Data(response.utf8)) as! [String: Any]
                check(json["answer"] is String && json["proposals"] is [String], "Pinned engine accepts the native schema option and returns structured JSON")
                let parsed = AssistantReply.parse(response, candidates: proposed)
                check(parsed.proposals.count == (proposed.isEmpty ? 0 : 1), "The real model explains without actions and offers an exact file only when requested")
                print("Real model: \(response)")
            }
        }
    }
}
