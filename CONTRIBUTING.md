# 🤝 How to Contribute / Как внести вклад

Благодарим за ваш интерес к проекту **Gym For Teenage**! Мы приветствуем любой вклад в развитие приложения — от исправления багов до добавления новых функций.

## 📋 Содержание

- [Вопросы и идеи](#-вопросы-и-идеи)
- [Как начать](#-как-начать)
- [Процесс разработки](#-процесс-разработки)
- [Стиль кода](#-стиль-кода)
- [Проверка перед PR](#-проверка-перед-pr)
- [Отправка Pull Request](#-отправка-pull-request)

---

## 💬 Вопросы и идеи

Прежде чем начать разработку новой функции, **откройте Issue** с меткой `enhancement`. Это поможет:

- Избежать дублирования работы
- Получить обратную связь от сообщества
- Согласовать архитектурные решения
- Найти менторов для сложных задач

**Для багов** откройте Issue с меткой `bug` и укажите:

1. Шаги для воспроизведения
2. Ожидаемое поведение
3. Фактическое поведение
4. Окружение (iOS версия, устройство)

---

## 🚀 Как начать

### 1. Форкните репозиторий

```
https://github.com/milestone7teenage/GYMFORTEENAGE/fork
```

### 2. Клонируйте локально

```bash
git clone https://github.com/ВАШ_НИКНЕЙМ/GYMFORTEENAGE.git
cd GYMFORTEENAGE
```

### 3. Создайте ветку для своей работы

```bash
# Для новых функций
git checkout -b feature/название-функции

# Для исправлений
git checkout -b fix/описание-бага
```

---

## 🔧 Процесс разработки

### Структура веток

```
main              — стабильная версия (только релизы)
feature/*         — новые функции
fix/*             — исправления багов
refactor/*        — рефакторинг кода
docs/*            — обновления документации
```

### Workflow

```
1. Создайте ветку
2. Разработайте функцию/исправление
3. Напишите тесты
4. Обновите документацию
5. Отправьте PR
6. Пройдите code review
7. Слейте в main
```

---

## 📐 Стиль кода

### Swift

Мы используем [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/):

```swift
// ✅ Правильно
func calculateWeight(in kilograms: Double) -> Double { ... }
let workoutSession = WorkoutSession()

// ❌ Неправильно
func calc(wt: Double) -> Double { ... }
let WorkoutSession = WorkoutSession()
```

### Именование

- **Классы**: CamelCase (`WorkoutSession`, `AIInsightsCoordinator`)
- **Переменные/Функции**: camelCase (`currentExercise`, `calculateMetrics()`)
- **Константы**: camelCase (`maxWaterIntake = 3000`)
- **Типы протоколов**: окончание `-able` или `-Delegate` (`Identifiable`, `Delegate`)

### Комментарии

Используйте SwiftDoc для документирования публичных API:

```swift
/// Calculates total weight lifted in kilograms.
/// - Parameter sets: Array of completed sets with valid weight and reps.
/// - Returns: Total weight in kilograms, or 0 if no valid sets.
func calculateTotalWeight(sets: [SetEntry]) -> Double { ... }
```

---

## ✅ Проверка перед PR

### 1. Тесты

```bash
# Запустите все тесты
xcodebuild test -project GymForTeenage.xcodeproj \
  -scheme GymForTeenage \
  -sdk iphonesimulator
```

**Требования:**
- Все unit тесты проходят успешно
- Покрытие кода тестами > 80% для новых функций
- Добавьте тесты для всех новых публичных функций

### 2. Сборка

```bash
# Проверьте сборку
xcodebuild build -project GymForTeenage.xcodeproj \
  -scheme GymForTeenage \
  -sdk iphonesimulator \
  -configuration Debug
```

**Требования:**
- Нет предупреждений компилятора
- Нет статических анализаторов (SwiftLint)

### 3. Документация

- Обновите `README.md` если изменился API
- Добавьте примеры использования
- Обновите `CHANGELOG.md` с описанием изменений

---

## 📤 Отправка Pull Request

### Заголовок PR

```
<type>: <brief-description>
```

Типы:
- `feat` — новая функция
- `fix` — исправление бага
- `docs` — обновления документации
- `refactor` — рефакторинг
- `test` — добавление тестов
- `chore` — улучшение конфигурации

**Примеры:**
```
feat: add AI Coach integration
fix: resolve workout session mismatch
docs: update README with screenshots
```

### Описание PR

Используйте шаблон:

```markdown
## Описание изменений
[Краткое описание]

## Как протестировать
[Инструкция для проверки]

## Связанные issues
Closes #123
```

---

## 🏆 Благодарности

Мы ценим каждый вклад:

- Новые участники попадают в `AUTHORS.md`
- Значительные вклады упоминаются в CHANGELOG
- Регулярные менторы получают доступ к закрытым задачам

---

## ❓ Нужна помощь?

- Откройте Issue с меткой `help-wanted`
- Присоединитесь к Telegram-чату: [@sellyou4ss](https://t.me/sellyou4ss)
- Проверьте существующие вопросы в Issues

---

**Спасибо за вклад в Gym For Teenage! 💪**

*Последнее обновление: 23 ноября 2026*
