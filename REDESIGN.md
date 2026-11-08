# teenage — Premium UI redesign

## Direction

The application uses an Apple Native × Premium Fitness visual language. The redesign preserves the JSON store, workout catalogue, session recovery, metrics, notifications, import and export. It changes presentation and navigation only.

## Tokens

| Token | Use |
| --- | --- |
| `Ink` | near-black application canvas |
| `Surface` / `SurfaceRaised` | layered graphite cards and controls |
| `Lime` | primary action, completed sets, progress |
| `Violet` | measurement and analytical accent |
| `Ice` | water and secondary analytical accent |
| `Muted` | secondary labels and inactive controls |

System San Francisco is used throughout. Titles are bold, compact and mostly lower-case; metrics use rounded, monospaced digits where it improves scanning. Cards use a 20–24 point radius, a subtle white outline and a restrained highlight gradient. Base spacing is 8 points, with 12/16/24 point component rhythm.

## Navigation and motion

The four destinations are Home, Progress, Statistics and Settings. A floating, dark bottom bar uses icon and text states instead of a stock unstyled tab bar. Content transitions use short spring or ease-in-out motion; cards scale subtly on press. Progress rings, water fills and charts animate when values change. Views respect Reduce Motion by relying on system animation settings.

## Screens

- **Home:** `teenage` header, prominent weight and height tiles, three distinct workout cards with active-session status, and a large water gauge with direct 200 ml action.
- **Progress:** three top metric tiles and one dense history card for each workout. Each card shows session count, latest six training loads and recent results.
- **Statistics:** frequency and best-day overview, workout comparison, seven-day water columns, and individual 12-month weight and height charts. Empty states provide a clear next action rather than an empty grid.
- **Settings:** actionable backup cards, a notification card with schedule, a local-only storage explanation and discreet developer destination.
- **Workout and exercise:** dark training list, thumbnail rows, circular session progress, compact action controls, clear set columns, lime completed states, red skipped states and preserved technique/history/replacement flow.

## State design

Pending controls are outlined graphite. Completed work is lime. Skipped items use subdued red and remain editable. Empty states use a compact icon, a clear explanation and no invented values. Destructive actions stay red and retain confirmation.

## Product and architecture alignment

The visual layer consumes the existing `Store`, `Metrics`, `Catalog`, `Record`, `Session`, JSON backup and notification scheduling APIs. No persistence field, backup schema or catalogue entry changes as part of the redesign.
