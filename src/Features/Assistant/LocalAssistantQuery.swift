import Foundation

@MainActor
extension LocalAssistantModel {
    func ask(_ question: String, analysis: SmartScanModel) {
        guard phase == .ready, !isGenerating, !analysis.busy, !chats.isLoading,
              !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let question = String(question.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000))
        currentTurnID = chats.begin(question)
        submittedQuestion = question
        response = ""; error = nil; contextNotice = nil; discardProposals(); activity.reset()
        if AssistantQueryIntent.detect(submittedQuestion) == .greeting {
            response = L10n.text("Hola. Puedo ayudarte a entender tu disco y preparar acciones para que las revises y confirmes. ¿Qué te gustaría revisar?")
            activity.complete(.greeting, detail: .message("Respondió localmente, sin consultar archivos."))
            persistConversation(); return
        }
        if analysis.index.files.isEmpty {
            error = nil
            response = L10n.text("Primero ejecuta Smart Scan para obtener recomendaciones sobre tu disco.")
            activity.complete(.missingAnalysis, detail: .message("No hay un análisis disponible para consultar.")); persistConversation(); return
        }
        #if KAZE_PREVIEW
        return
        #else
        let index = analysis.index, findings = analysis.findings, totals = analysis.systemTotals
        let systemPotential = analysis.systemPotential, potential = analysis.potential
        let scanDate = index.date, revision = analysis.revision, catalog = analysis.catalog
        let stale = analysis.isStale, english = L10n.language == "en"
        let memory = chats.turns.filter { $0.id != currentTurnID && $0.status == .completed }
        activity.complete(.context, detail: .message("Tamaños y categorías medidos por Smart Scan."), snapshotDate: scanDate)
        let checksFiles = AssistantQueryIntent.detect(question) == .fileActions
        if checksFiles { activity.start(.files) }
        else { activity.start(.response) }
        if stale { showContextNotice(scanDate) }
        token.cancel(); token = ScanCancellation(); request = UUID()
        let service = service, token = token, request = request
        isGenerating = true; error = nil; response = ""
        queue.async { [weak self] in
            let result = Result { () -> AssistantReply in
                guard !token.isCancelled else { throw LocalAIError.cancelled }
                let plan = AssistantFilePlanner.plan(index: index, findings: findings, question: question,
                    catalog: catalog, cancellation: token)
                guard !token.isCancelled else { throw LocalAIError.cancelled }
                let candidates = plan.candidates
                if checksFiles {
                    DispatchQueue.main.async {
                        guard let self, self.request == request, self.isGenerating else { return }
                        self.activity.complete(.files, detail: .message("\(plan.checked) ubicaciones comprobadas: \(candidates.count) disponibles y \(plan.skipped) omitidas. Se verificaron ubicación e identidad mediante metadatos."), paths: candidates.map { $0.file.url }, checked: plan.checked)
                        self.activity.start(.response)
                    }
                }
                let prompt = LocalAssistantPrompt.make(question: question, index: index, findings: findings,
                    totals: totals, systemPotential: systemPotential, potential: potential,
                    stale: stale, english: english, candidates: candidates, memory: memory)
                let response = try service.answer(prompt: prompt, cancellation: token, responseSchema: AssistantReply.schema(candidates: candidates))
                return AssistantReply.parse(response, candidates: candidates)
            }
            DispatchQueue.main.async {
                guard let self, self.request == request else { return }; self.isGenerating = false
                switch result {
                case .success(let reply):
                    self.activity.complete(.response, detail: .message("Preparó la explicación en tu Mac usando el resumen del análisis, sin enviar datos."))
                    self.response = reply.answer
                    if analysis.index.date == scanDate && analysis.revision == revision && !analysis.busy {
                        self.proposals = reply.proposals; self.proposalScanDate = scanDate; self.proposalRevision = revision
                        if !self.proposals.isEmpty {
                            self.activity.complete(.proposals, detail: .message("Acciones para revisar: \(self.proposals.count). Ningún archivo se mueve sin tu confirmación."), paths: self.proposals.map { $0.file.url }, criteria: self.proposals.map { proposal in
                                proposal.rule.map { .message(L10n.Message(stringLiteral: $0.reason)) } ?? .message("Puede contener datos personales. Revisa el contenido antes de borrar.")
                            })
                        }
                    }
                    else { self.showContextNotice(scanDate) }
                case .failure(let error):
                    self.activity.stop(error: error.localizedDescription)
                    self.error = error.localizedDescription
                    if let error = error as? LocalAIError, error == .integrity || error == .notInstalled { self.phase = .missing }
                }
                self.persistConversation()
            }
        }
        #endif
    }

}
