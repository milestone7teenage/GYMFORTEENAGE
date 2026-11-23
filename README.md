# 💪 Gym For Teenage

<p align="center">
  <img src="https://img.shields.io/badge/iOS-17.0+-blue.svg?style=flat&logo=apple" alt="iOS Version">
  <img src="https://img.shields.io/badge/SwiftUI-5.0+-orange.svg?style=flat&logo=swift" alt="SwiftUI">
  <img src="https://img.shields.io/badge/License-MIT-green.svg?style=flat" alt="License">
</p>

<p align="center">
  <strong>Профессиональный трекер тренировок для подростков и новичков</strong><br>
  Полностью локальное приложение без облака, рекламы и регистраций
</p>

---

## 🌟 О приложении

**Gym For Teenage** — это современное iOS-приложение для ведения тренировок, отслеживания прогресса и управления весом. Приложение разработано специально для подростков и начинающих в зале, с простым и интуитивным интерфейсом.

### 🎯 Ключевые особенности

- 💪 **Тренировки** — 3 готовых шаблона с 20 упражнениями
- 📊 **Прогресс** — детальная статистика и графики динамики
- 💧 **Вода** — напоминания и отслеживание водного баланса (цель: 3000 мл/день)
- 📈 **Измерения** — история веса и роста с графиками 12 месяцев
- 🤖 **AI Coach** — интеллектуальный помощник с OpenRouter и Gemini
- 📱 **Локально** — все данные хранятся только на устройстве
- 🔄 **Резервная копия** — экспорт/импорт JSON для безопасности

---

## 🚀 Возможности

### Тренировочный процесс

- 📋 **3 шаблона тренировок** — готовые комплексы для разных целей
- ✅ **Платформенный подход** — отслеживание веса и повторений
- ✏️ **Пользовательская техника** — редактирование рекомендаций по упражнениям
- 🔙 **Возврат к пропущенному** — возможность заполнить пропуски после свайпа
- 🔄 **Автосохранение** — данные сохраняются при каждом действии

### Анализ и статистика

- 📊 **Графики динамики** — визуализация прогресса по упражнениям
- 🏆 **Лучший день** — определение самого продуктивного дня
- 📅 **Частота тренировок** — недельная и месячная статистика
- 📉 **12-месячная динамика** — тренды веса и роста

### AI Coach (Интеллектуальный помощник)

- 🤖 **Gemini и OpenRouter** — выбор провайдера ИИ
- 💬 **Анализ тренировок** — подробные инсайты после каждой сессии
- 🎯 **Рекомендации** — персонализированные советы по прогрессу
- 📝 **История диалогов** — сохранение бесед в приложении

---

## 📱 Скриншоты

<p align="center">
  <img src="https://img.shields.io/badge/Скриншоты-добавить_в_релизе-purple?style=flat" alt="Work in Progress">
</p>

*Скриншоты будут добавлены в релиз v1.0.0*

---

## 🛠 Технические детали

### Архитектура

```
SwiftUI Views (4 вкладки)
         ↓
Feature State & ViewModels
         ↓
Services (WorkoutSession, Metrics, Water, Notifications, Backup/Restore)
         ↓
Local JSON store (Atomic operations)
```

### Технологии

- **SwiftUI** — современный UI-фреймворк
- **Swift 5.9+** — последний стабильный язык
- **iOS 17.0+** — минимальная версия
- **Local JSON Storage** — атомарные операции в Application Support
- **UserNotifications** — локальные напоминания о воде
- **OpenRouter API** — интеграция LLM для AI Coach

### Структура проекта

```
GymForTeenage/
├── GymForTeenageApp.swift       # Точка входа
├── AIChatView.swift             # Чат с AI Coach
├── AICoachSession.swift         # Управление AI сессиями
├── AIConfiguration.swift        # Настройки ИИ провайдеров
├── AIContextBuilder.swift       # Формирование контекста ИИ
├── AIInsightsCoordinator.swift  # Координация инсайтов
├── OneTimeTaskView.swift        # Одноразовые задачи
├── RecurringTaskView.swift      # Повторяющиеся задачи
├── TaskModels.swift             # Модели задач
├── TaskNotificationManager.swift # Управление уведомлениями
├── PremiumViews.swift           # Дизайн системы
├── Assets/упражнения/          # 15 PNG изображений
└── Tests/                       # Unit & Integration тесты
```

---

## 📦 Установка

### Через Xcode (разработка)

```bash
# Клонируйте репозиторий
git clone https://github.com/milestone7teenage/GYMFORTEENAGE.git
cd GYMFORTEENAGE

# Откройте в Xcode 16+
open GymForTeenage.xcodeproj
```

### Через GitHub Releases (тестирование)

1. Перейдите в [Releases](https://github.com/milestone7teenage/GYMFORTEENAGE/releases)
2. Скачайте `unsigned-ipa-for-esign-validation` из последнего релиза
3. Используйте ESign или аналогичный инструмент для установки

> ⚠️ **Важно**: CI-сборки подписаны временным сертификатом. Для установки на устройство требуется ESign или подпись личным сертификатом.

---

## 🔄 CI/CD

GitHub Actions автоматически собирает и тестирует приложение на каждый push/PR:

```yaml
# .github/workflows/ios.yml
- macOS runner (latest)
- Xcode validation
- Static analysis
- Unit tests
- Unsigned IPA packaging
```

Артефакты загружаются как GitHub Actions Artifacts для последующей валидации.

---

## 📝 История изменений

Смотрите [CHANGELOG.md](CHANGELOG.md) для подробной истории версий.

---

## 🤝 Как внести вклад

Мы приветствуем вклад в проект! Вот как вы можете помочь:

1. Fork репозитория
2. Создайте ветку для вашей фичи (`git checkout -b feature/AmazingFeature`)
3. Закоммитьте изменения (`git commit -m 'Add some AmazingFeature'`)
4. Отправьте в ветку (`git push origin feature/AmazingFeature`)
5. Откройте Pull Request

---

## 📄 Лицензия

Этот проект распространяется под лицензией [MIT](LICENSE). Смотрите файл [LICENSE](LICENSE) для подробной информации.

---

## 🙏 Благодарности

- Все подростки и новички в залах России и СНГ
- Сообщество iOS-разработчиков
- Авторы открытых библиотек и инструментов

---

## 📞 Контакты

- Telegram: [@sellyou4ss](https://t.me/sellyou4ss)
- GitHub: [@milestone7teenage](https://github.com/milestone7teenage)

---

<p align="center">
  <strong>Сделано с 💪 для сообщества</strong><br>
  Gym For Teenage v1.0.0 — 23 ноября 2026
</p>
