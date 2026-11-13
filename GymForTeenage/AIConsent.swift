import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AIConsentStore {
    static let currentVersion = 1

    private(set) var consentedCategories: Set<AIDataCategory>
    private(set) var consentVersion: Int

    @ObservationIgnored private let defaults: UserDefaults
    private let categoriesKey = "aiCoachConsentCategories"
    private let versionKey = "aiCoachConsentVersion"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedVersion = defaults.integer(forKey: versionKey)
        consentVersion = storedVersion
        if storedVersion == Self.currentVersion,
           let rawValues = defaults.array(forKey: categoriesKey) as? [String] {
            consentedCategories = Set(rawValues.compactMap(AIDataCategory.init(rawValue:)))
        } else {
            consentedCategories = []
        }
    }

    var hasConsent: Bool {
        consentVersion == Self.currentVersion && !consentedCategories.isEmpty
    }

    func allows(_ categories: Set<AIDataCategory>) -> Bool {
        hasConsent && categories.isSubset(of: consentedCategories)
    }

    func grant(_ categories: Set<AIDataCategory>) {
        consentedCategories = categories
        consentVersion = Self.currentVersion
        defaults.set(categories.map(\.rawValue).sorted(), forKey: categoriesKey)
        defaults.set(Self.currentVersion, forKey: versionKey)
    }

    func revoke() {
        consentedCategories = []
        consentVersion = 0
        defaults.removeObject(forKey: categoriesKey)
        defaults.removeObject(forKey: versionKey)
    }
}

struct AIConsentSheet: View {
    @Environment(AIConsentStore.self) private var consentStore
    @Environment(\.dismiss) private var dismiss
    let requiredCategories: Set<AIDataCategory>
    @State private var selectedCategories: Set<AIDataCategory>

    init(requiredCategories: Set<AIDataCategory>, initialCategories: Set<AIDataCategory> = []) {
        self.requiredCategories = requiredCategories
        _selectedCategories = State(initialValue: requiredCategories.union(initialCategories))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Передача данных в Google Gemini")
                        .font(.title2.bold())
                    Text("AI Coach отправит в Google Gemini только данные выбранных ниже категорий. Если выбраны сообщения чата, ваши сообщения также передаются для подготовки ответа. Выбор действует только после нажатия «Разрешить выбранные данные». Это не включает AI-помощника.")
                        .font(.subheadline).foregroundStyle(TeenTheme.muted)
                    Text("Выберите категории, которые разрешаете отправлять:")
                        .font(.subheadline.weight(.semibold))
                    ForEach(AIDataCategory.allCases, id: \.self) { category in
                        Toggle(isOn: binding(for: category)) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(category.consentTitle)
                                Text(category.consentDescription)
                                    .font(.caption).foregroundStyle(TeenTheme.muted)
                            }
                        }
                        .tint(TeenTheme.violet)
                        .disabled(requiredCategories.contains(category))
                    }
                    Text("Google обрабатывает запросы по условиям Gemini API. Условия хранения и обработки могут зависеть от действующих правил Google; приложение не обещает, что Google не сохраняет данные.")
                        .font(.caption).foregroundStyle(TeenTheme.muted)
                    Text("Без согласия выбранные категории и текст чата не отправляются. Отказ можно изменить позже в настройках AI.")
                        .font(.caption).foregroundStyle(TeenTheme.muted)
                }
                .padding(20)
            }
            .background(TeenTheme.ink.ignoresSafeArea())
            .navigationTitle("Конфиденциальность")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { dismiss() }.foregroundStyle(TeenTheme.lime)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Разрешить выбранные данные") { confirm() }
                        .fontWeight(.semibold).foregroundStyle(TeenTheme.lime)
                        .disabled(selectedCategories.isEmpty || !requiredCategories.isSubset(of: selectedCategories))
                }
            }
        }
        .tint(TeenTheme.lime)
        .presentationDetents([.large])
    }

    private func binding(for category: AIDataCategory) -> Binding<Bool> {
        Binding(
            get: { selectedCategories.contains(category) },
            set: { isSelected in
                if isSelected { selectedCategories.insert(category) }
                else { selectedCategories.remove(category) }
            }
        )
    }

    private func confirm() {
        guard !selectedCategories.isEmpty, requiredCategories.isSubset(of: selectedCategories) else { return }
        consentStore.grant(selectedCategories)
        dismiss()
    }
}

extension AIDataCategory {
    var consentTitle: String {
        switch self {
        case .chatMessages: "Текст сообщений чата"
        case .exerciseHistory: "История упражнения"
        case .waterIntake: "Записи о воде"
        case .bodyMeasurements: "Измерения веса и роста"
        case .weeklyInsights: "Показатели недельной сводки"
        }
    }

    var consentDescription: String {
        switch self {
        case .chatMessages: "Ваши вопросы и сообщения, отправленные в чате."
        case .exerciseHistory: "Выбранные тренировки, подходы, вес, повторы и даты."
        case .waterIntake: "Записи о воде только за период вопроса."
        case .bodyMeasurements: "Только выбранные измерения и период вопроса."
        case .weeklyInsights: "Локально рассчитанные недельные показатели и ограниченный сравнительный контекст."
        }
    }
}
