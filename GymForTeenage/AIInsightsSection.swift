import SwiftUI
import UIKit

struct AIInsightsSection: View {
    @Environment(Store.self) private var store
    @Environment(AIInsightsCoordinator.self) private var coordinator
    @AppStorage("aiCoachEnabled") private var isAIEnabled = false
    @State private var keychainError: String?

    var body: some View {
        TeenCard(accent: TeenTheme.violet) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles").foregroundStyle(TeenTheme.violet).font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI Coach").font(.headline)
                        Text("Insights по тренировкам").font(.caption).foregroundStyle(TeenTheme.muted)
                    }
                    Spacer()
                    if coordinator.state.availability == .loading {
                        ProgressView().tint(TeenTheme.lime)
                    }
                }

                if let insights = coordinator.state.insights, coordinator.state.availability != .disabled {
                    Text(insights.summary).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                    if !insights.observations.isEmpty {
                        VStack(alignment: .leading, spacing: 9) {
                            ForEach(Array(insights.observations.enumerated()), id: \.offset) { _, observation in
                                VStack(alignment: .leading, spacing: 5) {
                                    Label(observation.text, systemImage: "checkmark.circle.fill")
                                        .font(.caption).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                                    HStack(spacing: 6) {
                                        ForEach(observation.evidenceKeys, id: \.self) { key in
                                            if let metric = insights.computedMetrics.first(where: { $0.key == key }) {
                                                Text("\(metricTitle(key)): \(metric.value.formatted(.number.precision(.fractionLength(0...1)))) \(metric.unit)")
                                                    .font(.caption2).foregroundStyle(TeenTheme.muted)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        ForEach(insights.computedMetrics, id: \.key) { metric in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(metricTitle(metric.key)).font(.caption2).foregroundStyle(TeenTheme.muted)
                                Text("\(metric.value.formatted(.number.precision(.fractionLength(0...1)))) \(metric.unit)")
                                    .font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(9).background(TeenTheme.raised, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    if coordinator.state.isStale {
                        Label("Сохранённая сводка может быть неактуальной", systemImage: "clock.arrow.circlepath")
                            .font(.caption2).foregroundStyle(TeenTheme.muted)
                    }
                }

                if let keychainError {
                    Label(keychainError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                } else if let message = coordinator.state.message {
                    Text(message).font(.caption).foregroundStyle(TeenTheme.muted).fixedSize(horizontal: false, vertical: true)
                } else {
                    statusText
                }

                if showsAction {
                    Button(actionTitle) {
                        Task { await refresh(force: true, allowGeneration: true) }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TeenTheme.ink)
                    .padding(.horizontal, 13).padding(.vertical, 8)
                    .background(TeenTheme.lime, in: Capsule())
                    .disabled(coordinator.state.availability == .loading)
                }
            }
        }
        .task(id: analysisFingerprint) { await refresh(force: false, allowGeneration: false) }
        .onChange(of: analysisFingerprint) { _, _ in coordinator.cancelCurrentRequest() }
        .onChange(of: isAIEnabled) { _, _ in
            Task { await refresh(force: false, allowGeneration: false) }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.NSCalendarDayChanged)) { _ in
            Task { await refresh(force: false, allowGeneration: false) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await refresh(force: false, allowGeneration: false) }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.NSSystemTimeZoneDidChange)) { _ in
            Task { await refresh(force: false, allowGeneration: false) }
        }
    }

    private var statusText: some View {
        Group {
            switch coordinator.state.availability {
            case .disabled:
                Text("AI-помощник выключен. Его можно включить в настройках.")
            case .missingKey:
                Text("Сначала добавь API-ключ Gemini в настройках.")
            case .consentRequired:
                Text("Перед анализом потребуется отдельно подтвердить отправку показателей тренировок в Google Gemini.")
            case .loading:
                Text("Готовим сводку из локально рассчитанных показателей…")
            case .ready:
                Text("Показатели рассчитаны приложением; текст — пояснение AI Coach.")
            case .noData:
                Text("Заверши тренировку, чтобы появилась недельная сводка.")
            case .failed:
                Text("Не удалось обновить сводку. Предыдущая версия сохранена.")
            }
        }
        .font(.caption).foregroundStyle(TeenTheme.muted).fixedSize(horizontal: false, vertical: true)
    }

    private var showsAction: Bool {
        if keychainError != nil { return true }
        switch coordinator.state.availability {
        case .missingKey, .failed: return true
        case .ready: return coordinator.state.isStale
        case .disabled, .consentRequired, .loading, .noData: return false
        }
    }

    private var actionTitle: String {
        if keychainError != nil || coordinator.state.availability == .missingKey { return "Повторить проверку ключа" }
        return coordinator.state.insights == nil ? "Повторить запрос" : "Обновить сводку"
    }

    private var analysisFingerprint: String {
        AIInsightsEngine().build(from: store).fingerprint
    }

    @MainActor
    private func refresh(force: Bool, allowGeneration: Bool) async {
        guard isAIEnabled else {
            await coordinator.refresh(store: store, isAIEnabled: false, apiKey: nil, allowsPersonalData: false, allowGeneration: false)
            return
        }
        do {
            let apiKey = try AIKeychainStore().retrieveKey()
            keychainError = nil
            await coordinator.refresh(
                store: store,
                isAIEnabled: isAIEnabled,
                apiKey: apiKey,
                allowsPersonalData: false,
                allowGeneration: allowGeneration,
                forceRefresh: force
            )
        } catch {
            keychainError = "Не удалось проверить API-ключ в защищённом хранилище. Повтори проверку в настройках."
        }
    }

    private func metricTitle(_ key: String) -> String {
        switch key {
        case "workouts_7d": return "Тренировки · 7 дн."
        case "completed_sets_7d": return "Подходы · 7 дн."
        case "tonnage_7d": return "Тоннаж · 7 дн."
        default: return key
        }
    }
}
