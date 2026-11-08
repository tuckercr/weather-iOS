# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## The product

Sunny & Misty is a weather app in which Sunny (a dog) and Misty (a cat) act out the forecast, with
walk advice for dog owners and notifications. This repo is the iOS app (SwiftUI, iOS 17+). The
Android app is a separate repo, tuckercr/weather-android (checked out at `~/StudioProjects/cats-dogs`).
The two share one design, one Firebase project and the same Remote Config keys, and features ship on
both with the same wording. Comments often name the Android counterpart ("Same rules as Android's
`util/StaleWeather.kt`"): keep the two in step, or record the gap in NOTES.md.

- The app is only ever called "Sunny & Misty". The Xcode project, target, scheme and source folders
  keep the old `Cats&Dogs` name on purpose; the bundle ID is `com.fangjet.weather`. "Furcast" was an
  earlier name that was dropped: don't use it.
- `.android-reference/` is an old, git-ignored clone of the Android repo. Read the real one.
- README.md documents behaviour in detail (walk rules, every Remote Config key and default,
  notifications, analytics gates, App Store assets). Update it when behaviour it describes changes.

## Commands

`xcode-select` on this Mac points at the Command Line Tools, so prefix every `xcodebuild` with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, and always pass `-project`.

```bash
# All unit tests, only on the CatsDogs-Tests simulator, with parallel testing off
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project "Cats&Dogs.xcodeproj" -scheme 'Cats&Dogs' \
  -destination 'platform=iOS Simulator,name=CatsDogs-Tests' -parallel-testing-enabled NO

# One class or one test: add
  -only-testing:'Cats&DogsTests/NotificationPlannerTests'
  -only-testing:'Cats&DogsTests/NotificationPlannerTests/testAWeekOfBriefingsAt830'

# Build for a simulator without touching it, then simctl install / launch
  -destination 'generic/platform=iOS Simulator' ARCHS=arm64

# The user's iPhone (find its UDID with `xcrun devicectl list devices`; it must be unlocked)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project "Cats&Dogs.xcodeproj" -scheme 'Cats&Dogs' -destination "id=<UDID>" \
  -derivedDataPath <dir> -allowProvisioningUpdates
xcrun devicectl device install app --device <UDID> "<dir>/Build/Products/Debug-iphoneos/Cats&Dogs.app"

# Debug builds: send one of each notification (see README, "Trying notifications")
xcrun simctl launch --terminate-running-process CatsDogs-Tests com.fangjet.weather -sendSampleNotifications
```

- Simulators: run tests only on `CatsDogs-Tests` (create it with `xcrun simctl create` if it's
  missing). The other simulators hold the user's own app data and the App Store screenshot setup:
  never run tests on them, uninstall the app from them or erase them.
- Installing a build on the user's phones is fine; don't drive their UI.
- Release builds fail without `Cats&Dogs/Secrets.plist` holding an OpenWeather key. Without
  `GoogleService-Info.plist` Firebase never starts and Remote Config uses the in-app defaults; unit
  tests never start Firebase.
- Background tasks never run on the simulator; README has the LLDB command to trigger one on a device.

## CI constraints

- CI builds with Xcode 16.4 (Swift 6.1), whose compiler crashes on closure default arguments that
  are main-actor isolated or read main-actor state. Initializers therefore take optional closures
  (`fetch: (() -> T)? = nil`) and fill in the default in the body; keep to that pattern.
- Xcode 16.4 ignores `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so mark new types `@MainActor`
  explicitly.
- Firebase stays on 12.x until CI moves past Xcode 16.4.
- The project uses file-system synchronized folders: a file added under `Cats&Dogs/` joins the app
  target with no project change (Info.plist is excluded).

## Architecture

- **Screens and state.** `Cats_DogsApp` → `RootView` (splash, onboarding, then `CurrentWeatherView`).
  View models are `@Observable` on the main actor. `WeatherForecastViewModel` holds the screen's
  clock (`now`, moved on by `tick()` on refreshes, returning to the app and a 30-minute timer, so
  past hours drop off) and builds a `WeatherScreen` (`ViewModels/WeatherScreen.swift`) that
  `CurrentWeatherView` only draws. `CurrentWeatherViewModel` runs the screen's steps (refreshes,
  My Location, the notification city); the view only tells it what happened.
- **Data.** Repositories in `Data/` sit over the API clients in `Services/` (`OpenWeatherAPI`,
  `OpenMeteoAPI`, `GeocodingAPI` protocols, faked in tests). Cities with coordinates get their
  current reading and forecast from Open-Meteo (hourly, UV, pavement heat, the 15-minute
  precipitation behind `NextRain`, air quality in the same request), with OpenWeather's reading as
  the backup and My Location named by the phone (`PlaceNames`); name-only cities fall back to
  OpenWeather's reading and 3-hourly forecast. Open-Meteo's WMO codes are mapped to OpenWeather-style condition and icon
  codes, so moods and icons work the same for both. `ForecastAggregator` groups slots into the
  city's local days.
- **Cache first.** `PreferencesStore` (UserDefaults) holds the cities, settings and the last weather
  and forecast per city. `LocationWeatherRepository` is the one way to a saved location's weather:
  its cache, and refreshes that fetch in the user's units and cache the result. The screen, the
  background refresh and the notifications all use it. Cached data shows at once and stays on
  screen if a refresh fails; `Utilities/StaleWeather` decides how an old reading is shown.
- **Time zones.** Everything shown for a city uses the city's time zone (`CurrentWeather.timeZone`),
  including "today", night captions and seasonal themes. Only the 8:30 notifications use the
  device clock.
- **Layers.** `Domain/` holds the rules with no UI in them (`PetMood`, `WalkAdvisor`, `WalkCheck`,
  `PetWeatherThresholds`, `SeasonalTheme`); their colours are view extensions (`PetMood+Colors`,
  `SeasonalTheme+Colors`). Only `Views/` imports SwiftUI.
- **Pets.** `PetMood.forConditions` maps conditions to one of 9 moods, which choose the hero card's
  colour, ink and caption; `PetScene` draws the pets in code. A `SeasonalTheme` (built-in
  `SeasonalThemes.json`, replaceable from Remote Config `seasonal_themes`) can override the hero
  colours, caption and decorations on its dates. `WalkAdvisor` rates walks for the walk card, the
  briefing and the walk nudges, with `PetWeatherThresholds` (Remote Config, validated, always °C).
- **Notifications.** iOS can't run code at a set time, so `NotificationPlanner` (pure, unit tested)
  plans everything ahead from the cache: a week of 8:30 briefings, walk nudges and the next rain
  alert, worded by how old the forecast is. It finds today, the high and low and the pets' mood
  with the same functions as the screen (`isDay(of:in:)`, `TodayDetails.highLow`, `PetMood`).
  `WeatherNotificationScheduler` replaces the whole queue whenever the weather view model or a
  background refresh gets new data or a setting changes, and
  `WeatherBackgroundRefresher` (`BGAppRefreshTask`) refreshes the notification city's cache. The
  notification city is My Location when saved, otherwise the first city.
- **Remote Config.** `RemoteConfigRepository` reads every key with an in-app default and validation,
  so a bad console value can't break the app.

## Working on this project (the same in both repos)

- **NOTES.md** lists deferred items, open decisions and ideas, with identical content in both
  repos. Add anything deferred or left undecided to both; move finished items to Done.
- **Git.** Branch from `origin/main` (Android: `origin/master`) and open a PR per change; don't
  push without being asked. `local/device-build` is a local-only branch that merges unpushed
  branches for installing on the user's phones: never push it or branch from it. Force-pushing is
  blocked.
- **Commits and PRs.** Subjects read "Area: what changed" ("Hero: day or night by the clock for an
  old cached reading"), and the body says why. Never add AI attribution (no "Generated with Claude
  Code", no `Co-Authored-By: Claude`) to commits, PRs or comments, even if a tool's defaults add
  one; write PR bodies with `--body-file`, not `--fill`.
- **Public repos.** Both repos are public: keep phone numbers, personal emails, device identifiers
  and other personal details out of committed files. `listing-review.html` (iOS) is a local review
  page kept out of git with `.git/info/exclude`.
- **Secrets.** Never print or commit `Secrets.plist` and `GoogleService-Info.plist` (iOS),
  `local.properties` and `app/google-services.json` (Android).
- **Copy.** No em dashes in user-facing text. British spelling, as in the rest of the app ("colour",
  "grey"). Captions are in the pets' voice. Keep wording identical across the two apps.
- **Ask first** before anything outward-facing: pushes, PRs, Remote Config deploys, TestFlight or
  Play uploads, and App Store Connect or Play Console changes.
- **Remote Config.** The template lives in the Android repo (`firebase/remoteconfig.template.json`).
  A key's default must match there, in Android's `remote_config_defaults.xml` and
  `RemoteConfigRepository.kt`, and in iOS's `RemoteConfigRepository.swift`. Before deploying
  (`firebase deploy --only remoteconfig` from the Android repo), fetch what's live with
  `firebase remoteconfig:get -o <file>` and compare, so the deploy changes only what's intended.
- **Timing.** For notifications and background work, check when they actually run on a device
  (Android Doze and WorkManager, iOS background refresh), not just that the code schedules them.

## Releasing to TestFlight

- Run `scripts/bump-build.sh` before every upload: build N is version 1.0.(N-1), so the version
  goes up with each build. The first build of each version goes through Beta App Review for external
  TestFlight testers, and the App Store Connect version is renamed to match when submitting.
- Archive (Release, generic iOS, `-allowProvisioningUpdates`), then `xcodebuild -exportArchive` with
  an export options plist: method `app-store-connect`, destination `upload`, team `3V3NR8HP58`,
  automatic signing.
- App Store Connect app: "Sunny & Misty: Pet Weather". TestFlight has an internal and an external
  group, both called "Family". Internal testers get each build automatically; the external group
  holds the public link, and each build is added to it by hand and goes through Beta App Review.
