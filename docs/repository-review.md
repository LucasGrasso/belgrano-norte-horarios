# Repository review and upgrade plan

Reviewed against `main` commit `b310abfb876bd4106524cb2e746de538bafac69b`.
This is a source and automated-test review; native release builds, sideloaded
installation and notification delivery still need Android/iPhone validation.

## What the app does well

The architecture is appropriately small: a positional PDF parser creates a
local timetable, the domain layer resolves service days and overnight trains,
Riverpod connects that data to three screens, and notifications/background work
are kept outside the UI. The parser rejects suspicious input instead of
replacing usable data. There are real-PDF fixtures and tests covering short
services, direction, overnight trips and holidays. Keep those boundaries;
introducing a backend or another state framework is unnecessary for this scope.

## Fixes included in this change

| Finding | Behavior after the fix | Relevant files |
| --- | --- | --- |
| Cache saves deleted the destination before rename, creating a crash window; foreground/background writers reused one `.tmp` path | Both caches use unique temporary directories and rename over the destination on Android/iOS | `data/atomic_file.dart`, `timetable_store.dart`, `holiday_service.dart` |
| Switching tabs disposed the search page, losing its custom date | The shell keeps pages mounted in an `IndexedStack` | `ui/app.dart` |
| Timetable refresh replaced data with a loading state, unmounting Settings and resetting search state | Existing data stays visible while refresh runs; failed downloads preserve it | `state/providers.dart` |
| App-launch alert rescheduling happened only when a new month required a timetable download; holiday fetch raced it | Launch/resume loads the timetable, refreshes holidays and then reschedules alerts, including when no download is due | `ui/app.dart`, `state/providers.dart` |
| iOS initialized with permission requests enabled despite the intended contextual permission flow; scheduled details only specified Android | Initialization defers permission requests; scheduled notifications include Darwin details | `notifications/notification_scheduler.dart` |
| Saved route IDs were trusted without bounds checks | Invalid preferences fall back to the default route | `ui/home_screen.dart` |
| Android release used a debug signing key; no CI/release automation | Release uses an explicit free Android signing key; CI and directly downloadable APK/unsigned IPA workflows are included | `android/app/build.gradle.kts`, `.github/workflows/` |

## Highest-priority remaining work

### 1. Make notification content correct for every occurrence

`NotificationScheduler._scheduleWeekly` computes the next three trains once
and sets `DateTimeComponents.dayOfWeekAndTime`. Every later weekly occurrence
reuses that text. A holiday Monday and the next normal Monday can therefore
show different timetables but identical notification content. Opening the app
now refreshes the schedule, but a user who does not reopen it can still receive
incorrect times. Android's periodic worker also only reschedules after a
monthly download.

Use a rolling queue of **dated, one-off notifications**, calculate holidays for
each service date and replenish on launch/resume and Android periodic work.
Respect iOS's pending-notification capacity across all alerts, show the scheduled
coverage horizon, and define what happens when the user does not reopen the app
before that horizon. Avoid claiming background work will run at an exact time
on iOS. Add tests for holiday → normal week, New Year, timezone changes, reboot,
permission denial and many enabled alerts.

### 2. Fetch holiday coverage for the actual query range

`HolidayService.ensureCurrentYears` fetches next year only in December, while
the date picker accepts dates 60 days ahead. In November, a January query can
silently miss a holiday. Cached years also never refresh, so later official
calendar changes are missed. The UI silently treats unknown holiday data as
ordinary weekday service.

Add `ensureYears(Set<int>)`, resolve every year touched by a search and its
previous service day, and refresh cached feeds with a sensible TTL/conditional
request. Display “Feriados sin verificar” when coverage is unknown. Test late
November → January, an offline unknown year and malformed feed recovery.

### 3. Separate downloading from notification side effects

`TimetableController.download` still catches download and rescheduling failures
in one block. If storage succeeds but scheduling fails, it restores old state
even though disk contains the new timetable. `AlertsController` similarly saves
before scheduling, so an error can leave the UI claiming an alert is active
without a corresponding OS notification.

Treat “timetable saved” and “alerts synchronized” as separate outcomes. Keep
fresh data after a successful save, expose retryable scheduling errors and
report permission/queue status alongside each alert. Serialize edits and
rescheduling so rapid toggles cannot interleave `cancelAll` with stale writes.

### 4. Improve update resilience without adding a backend

Monthly fetching can miss an operator change published mid-month. Parsing also
runs synchronously on the foreground isolate. First launch requires a working
network before the app is useful, and `http.Client` instances are not closed.

Bundle a validated initial timetable; load it when the downloaded cache is
absent. Check for changes more often with HTTP validators/hash comparison and
backoff. Run parsing in an isolate after profiling, cap response size, validate
content type/PDF signature, and close owned clients. Keep the last good cache
and make freshness visible. Add schema/station-identity validation to persisted
timetables so a future station-list change cannot silently reinterpret IDs.

### 5. Expand tests around storage and notifications

The original tests cover the domain and PDF fixture well, but do not exercise
failed downloads, cache corruption/schema changes, concurrent alert edits,
platform permissions or actual notification delivery. This change adds cache
replacement/concurrent-write tests, refresh-state tests and tab-state/invalid
preference widget regressions, plus release metadata validation tests.

Next add injected clocks, filesystems and notification adapters. Verify the
complete offline/reconnect flow and rescheduling on physical Android/iOS devices.
CI unit tests cannot establish that exact alarms survive Doze/reboot or that an
iPhone presents scheduled notifications with the intended sound.

## UI improvements I would build next

| Priority | Improvement | Concrete behavior |
| --- | --- | --- |
| High | Distinguish scheduled times from live data | “Horarios programados · sin información en tiempo real” above results; avoid a live-status visual without a feed |
| High | Calendar-day labels | Group departures under Hoy/Mañana/date; mark arrivals on the following day with “+1 día” |
| High | Freshness and calendar coverage | Compact “Actualizado d/m” status, an actionable stale-data message and an unknown-holiday warning |
| High | Accessibility and small screens | Test 320 px width, landscape and 200% text scaling; make the fixed search area scrollable when needed and adapt the large two-time row/alert editor |
| Medium | Spanish localization | Add Flutter localization delegates and `es_AR`; date/time picker buttons currently follow the default Material locale despite Spanish app text |
| Medium | Faster daily use | Saved route chips, searchable full station names and “Crear alerta para este recorrido” from search |
| Medium | Clear first result hierarchy | Promote the next departure and its wait; use quieter styling for later trains instead of repeating the same red banner on every card |
| Medium | Alert confidence and recovery | Show enabled/permission status, exact versus approximate delivery and last scheduling error; add undo for deletion |
| Medium | Helpful empty states | Explain whether there is no route, no service today, missing timetable data or unknown calendar coverage; offer a useful next action |

Preserve the existing red identity and clear Sale/Llega times. A wholesale
visual rewrite is less valuable than making dates, data freshness and alert
status unambiguous.

## Release follow-through

See [the release setup guide](releases.md). Android needs a stable, locally
generated signing key; no store account is required. The unsigned iOS download
requires each user to sign/install it with their own account and a sideloading
tool. Neither APK distribution nor unsigned IPA generation requires store
credentials. Real-device installation checks are still required.
Review redistribution rights for the bundled Segoe UI fonts before public
distribution. The PDF engine now uses Apache-2.0 packages (`pdf_document`,
`pdf_graphics` and `pdf_cos`); retain their license notices when redistributing.
Configure protected tags/review rules and automatic updates for the pinned
Actions/toolchain as the next maintenance step.
