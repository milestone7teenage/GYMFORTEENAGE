# CI Failure Analysis Report

**Repository:** `milestone7teenage/GYMFORTEENAGE`  
**Commit:** `cef84f5`  
**Workflow:** `.github/workflows/ios.yml`  
**Failed Stage:** `Run XCTest suite`  
**Date:** 2026-11-12

---

## 1. Краткое описание проблемы

CI-пайплайн завершается ошибкой на этапе компиляции XCTest suite. Компилятор Swift сообщает о четырёх ошибках в файле `GymForTeenage/PremiumViews.swift`, все вызванные **отсутствием закрывающей скобки `)` в конструкторе `Button(...)`** в двух местах (строки 93 и 109).

---

## 2. Точное место каждой ошибки

**Файл:** `GymForTeenage/PremiumViews.swift`

### Ошибка 1: `Expected ',' separator` (строка 93 → 94)

```swift
Button(action: { ... } label: {          // Button( открыта на строке 85
    Image(systemName: "arrow.left")
        .font(.title3)
        .foregroundStyle(...)
        .frame(width: 30, height: 30)
        .background(.ultraThinMaterial, in: Circle())
}                                        // строка 93: закрывает label closure, но НЕ Button(
.buttonStyle(PlainButtonStyle())         // строка 94: парсер ещё внутри Button(, ожидает , или )
```

Парсер, находясь внутри незакрытого `Button(`, видит `.buttonStyle(...)` и ожидает запятую или `)`, но получает новый метод.

**Строка:** 93 (отсутствие `)`)

### Ошибка 2: `Cannot convert value of type 'ModifiedContent<some View, AccessibilityAttachmentModifier>' to expected argument type '() -> Label'` (строка 95)

Из-за того что `Button(` не закрыта, `.accessibilityLabel("Предыдущая тренировка")` интерпретируется как аргумент внутри конструктора `Button`, а не как модификатор. Возвращаемый тип `ModifiedContent<..., AccessibilityAttachmentModifier>` не совпадает с ожидаемым `() -> Label`.

**Строка:** 95

### Ошибка 3: `Generic parameter 'Label' could not be inferred` (строки 109 → 111)

Аналогичная проблема для второй кнопки (стрелка вправо). `Button(` на строке 101 не закрыта `)` на строке 109.

**Строки:** 109 (отсутствие `)`), 111 (`.accessibilityLabel`)

### Ошибка 4: `Function value was used as a property; add () to call it`

Следствие каскадного сбоя парсинга. Компилятор, не имея правильного контекста для `Button(...)`, интерпретирует цепочки модификаторов как доступ к свойствам function-типа.

---

## 3. Перопричина

**Отсутствует закрывающая скобка `)` в двух конструкторах `Button(...)`** — на строках 93 и 109.

Текущий код:
```swift
Button(action: { ... } label: {
    Image(systemName: "arrow.left")
        .font(.title3)
        .foregroundStyle(selectedWorkoutIndex == 0 ? TeenTheme.muted : TeenTheme.lime)
        .frame(width: 30, height: 30)
        .background(.ultraThinMaterial, in: Circle())
}                          // ← только } закрывает label closure
.buttonStyle(PlainButtonStyle())       // Button( по-прежнему открыта!
.accessibilityLabel("Предыдущая тренировка")
```

`Button(` открывается на строке 85 и никогда не закрывается `)`. Закрывающая скобка label closure `}` есть, но нет `)` для завершения вызова конструктора.

Это не баг компилятора и не проблема API — это **чистая синтаксическая ошибка**: пропущен один символ `)` в двух местах.

---

## 4. Почему предыдущая реализация не компилируется

Swift парсит код строго. Когда `Button(` остаётся незакрытой:

1. **Парсер остаётся в контексте вызова `Button(...)`** — он ждёт либо запятую (следующий аргумент), либо `)` (закрытие вызова).
2. `.buttonStyle(PlainButtonStyle())` на строке 94 — парсер видит это как продолжение аргументов `Button(`, а не как метод на результате. Отсюда `Expected ',' separator`.
3. `.accessibilityLabel("...")` на строке 95 — парсер пытается сопоставить возвращаемый `ModifiedContent` с ожидаемым типом параметра `label:`, но они не совпадают. Отсюда ошибка конвертации типов.
4. Без правильного закрытия `Button(...)` компилятор не может вывести тип `Label`, отсюда `Generic parameter 'Label' could not be inferred`.
5. Каскадно, компилятор теряет контекст и начинает интерпретировать цепочки как свойства, отсюда `Function value was used as a property`.

**Подтверждение:** анализ баланса скобок показывает 1087 открытых `(` vs 1085 закрытых `)` — ровно 2 недостающие закрывающие скобки, что соответствует двум незакрытым `Button(...)`.

---

## 5. Предлагаемое исправление

### Строка 93: добавить `)` после `}`

```swift
// БЫЛО (строка 93):
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Предыдущая тренировка")

// СТАЛО (строка 93):
                })
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Предыдущая тренировка")
```

### Строка 109: добавить `)` после `}`

```swift
// БЫЛО (строка 109):
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Следующая тренировка")

// СТАЛО (строка 109):
                })
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Следующая тренировка")
```

**Итог:** изменение двух символов — добавление `)` в конце строк 93 и 109.

---

## 6. Возможные побочные эффекты

- **Визуальных изменений нет:** `.buttonStyle()` и `.accessibilityLabel()` применяются к `Button` как и задумано, просто теперь синтаксически корректно.
- **Accessibilty:** метки `"Предыдущая тренировка"` и `"Следующая тренировка"` корректно привязываются к кнопкам.
- **Другие кнопки в файле:** проверены все остальные `Button` в `PremiumViews.swift` — у них скобки сбалансированы, проблемы нет.
- **Другие файлы:** `GymForTeenageApp.swift`, `PremiumDesign.swift` — скобки сбалансированы.

---

## 7. План проверки после исправления

### 7.1 Локальная компиляция (macOS + Xcode)

```bash
xcodebuild build -project GymForTeenage.xcodeproj -scheme GymForTeenage -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```

Ожидание: сборка без ошибок.

### 7.2 Запуск XCTest suite

```bash
xcodebuild test -project GymForTeenage.xcodeproj -scheme GymForTeenage -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```

Ожидание: все тесты зелёные.

### 7.3 Затронутые тесты

Прямых unit-тестов на UI-компоненты (карусель тренировок, стрелки навигации) нет. Затронуты **косвенно**:

- **Все тесты** (`MetricsTests`, `StoreIntegrationTests`) — они не запускались, потому что модуль `GymForTeenage` не компилировался. После исправления все 13 тестов станут исполняемыми:
  - `MetricsTests` (5 тестов)
  - `StoreIntegrationTests` (8 тестов)

### 7.4 Статический анализ

```bash
xcodebuild analyze -project GymForTeenage.xcodeproj -scheme GymForTeenage -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```

### 7.5 CI-валидация

После пуша:
1. Стадия `Run XCTest suite` — проходит
2. Стадия `Xcode static analysis` — проходит
3. Стадии `Archive` и `Package` — проходят

### 7.6 Ручная проверка (опционально)

- Карусель тренировок: стрелки влево/вправо работают
- Accessibility Inspector: метки "Предыдущая тренировка" / "Следующая тренировка" привязаны к кнопкам

---

## 8. Дополнительные наблюдения

### Предупреждения о deprecated headermap style

В логе CI присутствуют предупреждения о `traditional headermap style`. Они **не являются причиной падения** и могут быть исправлены отдельно.

### Баланс скобок (до исправления)

| Тип | Открыто | Закрыто | Разница |
|-----|---------|---------|---------|
| `{ }` | 419 | 419 | 0 |
| `( )` | 1087 | 1085 | **−2** |
| `[ ]` | 27 | 27 | 0 |

Недостающие 2 закрывающие `(` — это ровно два незакрытых `Button(...)`.

### История введения ошибки

Коммит `903a4f0` ("polish: swipe arrows + delete confirmation") добавил стрелки навигации в карусель тренировок вместе с `.accessibilityLabel`. Скорее всего, при переносе/редактировании кода была потеряна закрывающая скобка.

---

## 9. Статус

- [x] Все четыре ошибки объяснены
- [x] Перопричина установлена (пропущена `)` в двух `Button(...)`)
- [x] Исправление обосновано (добавить `)` на строках 93 и 109)
- [x] Исходный код не изменён
- [x] Отчёт готов к проверке

**Ожидание подтверждения перед реализацией исправления.**
