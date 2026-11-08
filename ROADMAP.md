# ROADMAP.md — план реализации

**Статус:** план будущей работы. Код и сборка на этапе документации не выполнялись.

## Этап 0. Утверждение проектных решений

- Утвердить минимальную iOS-версию и SwiftData (предложено iOS 17+).
- Утвердить правила подходов, графики, каталога и замены, одну активную сессию.
- Подтвердить соответствие 15 PNG упражнениям; решить несоответствия названий в тренировке 2.
- Определить поддерживаемую Xcode и проверить unsigned IPA/ESign риск отдельным техническим прототипом после разрешения реализации.

**Готово, когда:** нерешённые пункты ARCHITECTURE.md решены или приняты как явные ограничения.

## Этап 1. Каркас приложения и каталог

Создать Xcode-проект SwiftUI, минимальную навигацию четырёх вкладок, систему стилей и адаптивные контейнеры; заложить каталог 3 тренировок/15 упражнений и Assets из предоставленного архива без дубликатов.

**Приёмка:** приложение запускается на выбранном iOS simulator; есть четыре вкладки; порядок 7/6/7 соответствует утверждённым спискам; все ссылки на изображения единичны и пропорции сохранены; dark mode и Dynamic Type просмотрены.

## Этап 2. Локальная модель и надёжность

Добавить выбранное persistence, schema versioning/migrations и репозитории; реализовать измерения, воду, настройки, инструкции, историю и автоматическое состояние сессии.

**Приёмка:** данные остаются после принудительного закрытия/повторного запуска; значения активной тренировки и текущая позиция восстанавливаются; смена календарного дня создаёт новый водный день; ограничения 3000 мл и 7 дней соблюдены; ошибка сохранения не стирает сессию.

## Этап 3. Тренировочные сценарии

Реализовать выбор любой программы, экран упражнения, два начальных подхода, копирование первого веса во второй, независимое редактирование, дополнительные подходы, пропуск, временную замену, автосохранение и явное завершение со снимками истории.

**Приёмка:** пропущенное не влияет на тоннаж; заменённая позиция не меняет шаблон; исторические названия/подходы не меняются после обновления каталога; незавершённая сессия возобновляется; двойное завершение не создаёт дубль.

## Этап 4. Прогресс, статистика, вода и напоминания

Сделать сводки, графики по одинаковым упражнениям, частоту по локальным календарным периодам, продуктивный день, 12-месячную историю измерений, 7-дневную воду и локальные уведомления.

**Приёмка:** unit-тесты расчётов покрывают пустые/пропущенные/выполненные подходы, границы недели/месяца, равный лучший день и достижение лимита воды; график не смешивает разные упражнения; отказ уведомлений обработан; расписание не дублируется.

## Этап 5. Резервные копии и очистка

Реализовать версионированный JSON export/import с DTO, валидацией и атомарной заменой; очистку пользовательских данных с подтверждением; системный URL разработчика.

**Приёмка:** round-trip backup сохраняет все требуемые данные, включая активную сессию и инструкции; невалидный/неподдерживаемый файл не меняет локальное состояние; успешный импорт заменяет всё; очистка не удаляет встроенный каталог.

## Этап 6. Доступность, качество и тестирование

Проверить VoiceOver, Dynamic Type, контраст, зоны нажатия, Reduce Motion, ошибочные/пустые данные и адаптацию экранов. Добавить unit- и интеграционные тесты, миграционные fixtures и корректную обработку ошибок.

**Приёмка:** критические сценарии покрыты тестами; нет блокирующих проблем доступности; данные не теряются при ошибках; тесты проходят на утверждённом simulator/runtime.

## Этап 7. CI и IPA

Создать GitHub Actions на macOS runner: форматирование, статический анализ, тесты, сборка, упаковка IPA без личной подписи, валидация содержимого, artifact upload. Проверить самостоятельную подпись пользователем в ESign, не помещая сертификаты/секреты в CI.

**Приёмка:** workflow воспроизводимо проходит с чистого runner; артефакт загружается и содержит ожидаемое приложение; процесс загрузки и подписи через ESign документирован и реально проверен. Если неподписанная упаковка не работает с выбранными Xcode/ESign, остановить релизный этап и согласовать технический вариант, не добавляя личные сертификаты в CI.

## Сквозные критерии релиза

- Четыре вкладки реализуют утверждённую спецификацию.
- Нет регистрации, сервера и обязательной авторизации.
- История, активная сессия и измерения переживают перезапуск.
- Тоннаж и статистика проверены тестами.
- Backup/import и очистка безопасны и предсказуемы.
- Все 15 предоставленных изображений соответствуют упражнениям и хранятся локально без дубликатов.
- CI публикует проверенный артефакт; реальный ESign-процесс подтверждён.

## Implementation follow-up status (2026-11-08)

Implemented in the existing app: recent-session comparison by workout type, 12-month measurement charts, seven-day water chart, left-swipe skipping, recovery navigation to the stored active position, centralized tonnage/set-count functions, version/structure validation for JSON import, atomic file replacement before applying imported state, and integration tests for restart recovery, measurements/water round-trip, rejected import without mutation, replacement import, clear, and corrupt-store preservation.

The GitHub Actions workflow now runs XCTest and Xcode static analysis on macOS, archives with signing disabled, packages and inspects the IPA payload, and uploads an artifact explicitly labelled for ESign compatibility validation. The repository has no Git metadata or remote configured in this workspace, and this machine is Windows without Xcode; therefore the workflow, XCTest suite, archive, IPA structure, and ESign installation have not been executed here. These checks remain outstanding rather than passed.

### Verification checklist for the next macOS runner execution

The workflow must be run from a GitHub-connected checkout before the project can be called build-verified. Review and fix any compiler/test failures reported by `xcodebuild test`, then confirm `xcodebuild analyze` and archive succeed. Inspect the uploaded IPA's `Payload/GymForTeenage.app` contents and test signing that artifact in ESign on a compatible iOS device. An unsigned archive may be structurally valid yet unusable by a specific signer; this remains an explicit external compatibility check.
