import SwiftUI
import UIKit

struct AIInsightsSection: View {
    @Environment(Store.self) private var store
    @Environment(AIInsightsCoordinator.self) private var coordinator
    @Environment(AIConsentStore.self) private var consentStore
    @AppStorage("aiCoachEnabled") private var isAIEnabled = false
    @State private var keychainError: String?
    @State private var presentsChat = false
    @State private var presentsConsent = false

    var body: some View {
        TeenCard(accent: TeenTheme.violet) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles").foregroundStyle(TeenTheme.violet).font(.title3)
                    Text("Teenage Coach").font(.headline)
                    Spacer()
                    if showsAction {
                        Button {
                            if coordinator.state.availability == .consentRequired {
                                presentsConsent = true
                            } else {
                                Task { await refresh(force: true, allowGeneration: true) }
                            }
                        } label: {
                            Image(systemName: coordinator.state.availability == .loading ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(TeenTheme.lime)
                                .frame(width: 36, height: 36).background(TeenTheme.raised, in: Circle())
                        }
                        .buttonStyle(TeenPressStyle())
                        .disabled(coordinator.state.availability == .loading)
                        .accessibilityLabel(actionTitle)
                    }
                    Button { presentsChat = true } label: {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(TeenTheme.lime)
                            .frame(width: 36, height: 36).background(TeenTheme.raised, in: Circle())
                    }
                    .buttonStyle(TeenPressStyle())
                    .accessibilityLabel("Открыть чат Teenage Coach")
                }

                if let insights = coordinator.state.insights, coordinator.state.availability != .disabled {
                    Text(insights.summary).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                    if !insights.observations.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(insights.observations.prefix(3).enumerated()), id: \.offset) { _, observation in
                                Label(observation.text, systemImage: "checkmark.circle.fill")
                                    .font(.caption).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                            }
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
            }
        }
        .task(id: analysisFingerprint) { await refresh(force: false, allowGeneration: false) }
        .onChange(of: analysisFingerprint) { _, _ in coordinator.cancelCurrentRequest() }
        .onChange(of: isAIEnabled) { _, _ in
            Task { await refresh(force: false, allowGeneration: false) }
        }
        .onChange(of: consentStore.consentedCategories) { oldCategories, newCategories in
            coordinator.consentCategoriesChanged(from: oldCategories, to: newCategories)
            Task { await refresh(force: false, allowGeneration: false) }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.NSCalendarDayChanged)) { _ in
            Task { await refresh(force: false, allowGeneration: false) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await refresh(force: false, allowGeneration: false) }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.NSSystemTimeZoneDidChange)) { _ in
            coordinator.updateCalendarContext()
            Task { await refresh(force: false, allowGeneration: false) }
        }
        .sheet(isPresented: $presentsChat) {
            AIChatView().environment(store).environment(coordinator).presentationDetents([.large])
        }
        .sheet(isPresented: $presentsConsent) {
            AIConsentSheet(requiredCategories: coordinator.requiredConsentCategories, initialCategories: consentStore.consentedCategories)
                .environment(consentStore)
        }
    }

    private var statusText: some View {
        Group {
            switch coordinator.state.availability {
            case .disabled:
                Text("Teenage Coach выключен. Его можно включить в настройках.")
            case .missingKey:
                Text("Сначала добавь API-ключ в настройках.")
            case .consentRequired:
                Text("Перед анализом можно выбрать, какие показатели разрешено отправлять.")
            case .loading:
                Text("Готовим сводку из локально рассчитанных показателей…")
            case .ready:
                Text("Показатели рассчитаны приложением; текст — пояснение Teenage Coach.")
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
        case .missingKey, .failed, .consentRequired, .ready: return true
        case .disabled, .loading, .noData: return false
        }
    }

    private var actionTitle: String {
        if keychainError != nil || coordinator.state.availability == .missingKey { return "Повторить проверку ключа" }
        if coordinator.state.availability == .consentRequired { return "Выбрать данные для передачи" }
        return coordinator.state.insights == nil ? "Сгенерировать сводку" : (coordinator.state.isStale ? "Обновить сводку" : "Снова вычислить сводку")
    }

    private var analysisFingerprint: String {
        AIInsightsEngine().build(from: store).fingerprint
    }

    @MainActor
    private func refresh(force: Bool, allowGeneration: Bool) async {
        guard isAIEnabled else {
            await coordinator.refresh(store: store, isAIEnabled: false, apiKey: nil, consentedCategories: consentStore.consentedCategories, allowGeneration: false)
            return
        }
        do {
            let apiKey = try AIKeychainStore().retrieveKey()
            keychainError = nil
            await coordinator.refresh(
                store: store,
                isAIEnabled: isAIEnabled,
                apiKey: apiKey,
                consentedCategories: consentStore.consentedCategories,
                allowGeneration: allowGeneration,
                forceRefresh: force
            )
        } catch {
            keychainError = "Не удалось проверить API-ключ в защищённом хранилище. Повтори проверку в настройках."
        }
    }
}
