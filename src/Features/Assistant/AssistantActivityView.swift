import SwiftUI

struct AssistantActivityView: View {
    var steps: [AssistantActivityStep]
    @ViewState private var localExpanded = false
    private var expansion: Binding<Bool>?
    private var expanded: Bool { expansion?.wrappedValue ?? localExpanded }

    init(steps: [AssistantActivityStep], contextNotice: String? = nil, expanded: Binding<Bool>? = nil) {
        self.steps = steps; self.contextNotice = contextNotice; expansion = expanded
    }
    var contextNotice: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !steps.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Button {
                    withAnimation(reduceMotion ? nil : SoraMotion.content) {
                        if let expansion { expansion.wrappedValue.toggle() }
                        else { localExpanded.toggle() }
                    }
                } label: {
                    HStack(alignment: .center, spacing: 8) {
                        if steps.contains(where: { $0.status == .running }) { SoraSpinner(size: 14) }
                        else { LucideIcon("activity", size: 14) }
                        Text(AssistantActivityModel.summary(steps)).font(SoraTypography.body(11)).lineLimit(2).multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        LucideIcon(expanded ? "chevron-down" : "chevron-right", size: 13)
                    }.foregroundStyle(SoraPalette.secondary).contentShape(Rectangle())
                }.buttonStyle(.plain).help(L10n.text("Ver actividad y criterios"))
                    .accessibilityLabel(L10n.text("Actividad y criterios de la respuesta"))
                    .accessibilityValue(L10n.text(expanded ? "Detalles abiertos" : "Detalles cerrados"))
                if expanded {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(steps) { step in
                            HStack(alignment: .top, spacing: 10) {
                                if step.status == .running { SoraSpinner(size: 13).padding(.top, 2) }
                                else { LucideIcon(step.icon, size: 14).foregroundStyle(SoraPalette.muted).padding(.top, 1) }
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 8) {
                                        Text(step.title).font(SoraTypography.body(11, weight: .medium))
                                        Spacer(minLength: 4)
                                        if let duration = step.duration, duration >= 0.1 {
                                            Text(duration.formatted(.number.precision(.fractionLength(0...1)).locale(L10n.locale)) + " s")
                                                .font(SoraTypography.body(10)).monospacedDigit().foregroundStyle(SoraPalette.muted)
                                        }
                                    }
                                    if let date = step.snapshotDate {
                                        Text(L10n.text("Análisis del \(L10n.date(date, includeTime: true))")).font(SoraTypography.body(10))
                                    }
                                    if !step.detail.string.isEmpty {
                                        Text(step.detail.string).font(SoraTypography.body(10)).lineSpacing(3).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                                    }
                                    ForEach(step.paths, id: \.path) { url in
                                        Text(url.path).font(SoraTypography.body(10)).lineLimit(2).truncationMode(.middle)
                                            .textSelection(.enabled).help(url.path)
                                    }
                                    ForEach(Array(step.criteria.enumerated()), id: \.offset) { _, criterion in
                                        Text(criterion.string).font(SoraTypography.body(10)).lineSpacing(3)
                                    }
                                }.foregroundStyle(SoraPalette.secondary)
                            }
                        }
                        if let contextNotice {
                            Text(contextNotice).font(SoraTypography.body(10)).foregroundStyle(SoraPalette.muted).lineSpacing(3)
                        }
                    }.padding(.leading, 2).fixedSize(horizontal: false, vertical: true).transition(.opacity)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4).fixedSize(horizontal: false, vertical: true).clipped()
        }
    }
}
