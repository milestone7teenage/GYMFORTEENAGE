import SwiftUI

struct AIChatView: View {
    @Environment(Store.self) private var store
    @Environment(AIInsightsCoordinator.self) private var insightsCoordinator
    @Environment(AIConsentStore.self) private var consentStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("aiCoachEnabled") private var isAIEnabled = false
    @State private var session = AICoachSession()
    @State private var draft = ""
    @State private var presentsConsent = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if session.messages.isEmpty {
                                emptyState
                            }
                            ForEach(session.messages) { message in
                                messageBubble(message).id(message.id)
                            }
                            if session.isSending {
                                HStack {
                                    ProgressView().tint(TeenTheme.violet)
                                    Text("AI Coach отвечает…").font(.caption).foregroundStyle(TeenTheme.muted)
                                    Spacer()
                                }.padding(.horizontal, 16).id("loading")
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 18)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: session.messages.count) { _, _ in
                        if let lastMessage = session.messages.last {
                            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(lastMessage.id, anchor: .bottom) }
                        }
                    }
                    .onChange(of: session.isSending) { _, sending in
                        if sending { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("loading", anchor: .bottom) } }
                    }
                }

                if let statusMessage {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(statusMessage).font(.caption).foregroundStyle(statusIsError ? .orange : TeenTheme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if session.canRetry {
                            Button("Повторить") { retry() }
                                .font(.caption.weight(.semibold)).foregroundStyle(TeenTheme.lime)
                        }
                        if session.availability == .consentRequired {
                            Button("Настроить согласие") { presentsConsent = true }
                                .font(.caption.weight(.semibold)).foregroundStyle(TeenTheme.lime)
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 8)
                }

                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Спроси про тренировку…", text: $draft, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($inputFocused)
                        .padding(.horizontal, 13).padding(.vertical, 10)
                        .background(TeenTheme.raised, in: RoundedRectangle(cornerRadius: 18))
                        .disabled(session.isSending)
                        .accessibilityLabel("Сообщение AI Coach")
                    Button(action: send) {
                        Image(systemName: "arrow.up")
                            .font(.headline).foregroundStyle(TeenTheme.ink)
                            .frame(width: 42, height: 42).background(TeenTheme.lime, in: Circle())
                    }
                    .buttonStyle(TeenPressStyle())
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.isSending)
                    .accessibilityLabel("Отправить сообщение")
                }
                .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 12)
                .background(TeenTheme.ink)
            }
            .background(TeenTheme.ink.ignoresSafeArea())
            .navigationTitle("AI Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть") { close() }.foregroundStyle(TeenTheme.lime)
                }
            }
        }
        .tint(TeenTheme.lime)
        .task {
            let insights = insightsCoordinator.state.isStale ? nil : insightsCoordinator.state.insights
            session.setStartingInsights(insights)
        }
        .onDisappear { session.cancelAndClear(); draft = "" }
        .sheet(isPresented: $presentsConsent) {
            AIConsentSheet(requiredCategories: session.pendingConsentCategories, initialCategories: consentStore.consentedCategories)
                .environment(consentStore)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "sparkles").foregroundStyle(TeenTheme.violet).font(.title2)
            Text("Новый чат").font(.headline)
            Text("Можно спросить про упражнения, тренировочную историю или общие принципы занятий. Начни с одного вопроса.")
                .font(.subheadline).foregroundStyle(TeenTheme.muted)
            Text("Чат хранится только пока открыт этот экран.")
                .font(.caption).foregroundStyle(TeenTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16).background(TeenTheme.raised, in: RoundedRectangle(cornerRadius: 18))
    }

    private func messageBubble(_ message: AIChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 42) }
            Text(message.text)
                .font(.body).foregroundStyle(message.role == .user ? TeenTheme.ink : .white)
                .textSelection(.enabled)
                .padding(13)
                .background(message.role == .user ? TeenTheme.lime : TeenTheme.raised, in: RoundedRectangle(cornerRadius: 18))
            if message.role == .assistant { Spacer(minLength: 42) }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message.role == .user ? "Ты: \(message.text)" : "AI Coach: \(message.text)")
    }

    private var statusMessage: String? {
        switch session.availability {
        case .idle: return nil
        case .disabled: return "Включи AI-помощника в настройках, чтобы начать чат."
        case .missingKey: return "Добавь API-ключ Gemini в настройках."
        case .consentRequired: return "Перед отправкой сообщения и выбранных данных нужно отдельно подтвердить передачу Google Gemini."
        case .loading: return nil
        case .failed(let message): return message
        }
    }

    private var statusIsError: Bool {
        if case .failed = session.availability { return true }
        return false
    }

    private func send() {
        let question = draft
        Task {
            do {
                let apiKey = try AIKeychainStore().retrieveKey()
                let consumed = await session.send(
                    question,
                    store: store,
                    apiKey: apiKey,
                    isAIEnabled: isAIEnabled,
                    consentedCategories: consentStore.consentedCategories
                )
                if consumed { draft = "" }
            } catch {
                session.setLocalError("Не удалось проверить API-ключ в защищённом хранилище. Повтори проверку в настройках.")
            }
        }
    }

    private func retry() {
        Task {
            do {
                guard let apiKey = try AIKeychainStore().retrieveKey() else {
                    session.setLocalError("API-ключ не найден. Добавь его в настройках, затем повтори запрос.")
                    return
                }
                _ = await session.retryLast(
                    store: store,
                    apiKey: apiKey,
                    isAIEnabled: isAIEnabled,
                    consentedCategories: consentStore.consentedCategories
                )
            } catch {
                session.setLocalError("Не удалось проверить API-ключ в защищённом хранилище. Повтори проверку в настройках.")
            }
        }
    }

    private func close() {
        session.cancelAndClear()
        draft = ""
        dismiss()
    }
}
