# Sunny & Misty: App Store listing (draft)

Copy each field into App Store Connect. Character counts are checked against Apple's limits.

## App information

| Field | Value |
|---|---|
| Name (26/30) | Sunny & Misty: Pet Weather |
| Subtitle (28/30) | Best walk times & live radar |
| Primary category | Weather |
| Secondary category | Lifestyle |
| Bundle ID | com.fangjet.weather |
| SKU | sunny-and-misty-ios |
| Content rights | Does not contain, show or access third-party content that needs rights (weather data is licensed from the providers below) |
| Copyright | 2026 FangJet LLC |

## Version 1.0

**Promotional text** (149/170, can be changed any time without a new build)

> Rain or shine, your cat and dog act out the forecast and tell you the best time for a walk, with hot-pavement warnings, live radar and daily updates.

**Description** (up to 4,000)

> Sunny & Misty is the weather app for people who share their home with a cat, a dog, or both. Sunny the dog and Misty the cat act out the forecast, so you can tell at a glance whether it's a sunglasses day, an umbrella day or a stay-under-the-blanket day.
>
> BEST TIME FOR A WALK
> Sunny & Misty looks at the next 24 hours and tells you when to head out: right now, later today, or tomorrow morning. It checks rain chance, comfortable temperatures and daylight hours, and warns you when sun-baked pavement is too hot for paws, even on a mild day.
>
> PETS THAT REACT TO THE WEATHER
> Sun, cloud, rain, storms, snow, heat, cold and night each get their own scene, with a fresh caption every day.
>
> EVERYTHING ELSE YOU'D EXPECT
> - Air quality for every city, and walk times that steer clear of smoky or polluted hours
> - Current conditions, feels-like, humidity, wind, visibility, cloud cover, UV index, sunrise and sunset
> - An hourly strip with rain chance, and a 7-day forecast with hour-by-hour detail for each day
> - Animated precipitation radar
> - Save as many cities as you like, or use your current location, each shown in its own time zone
> - Optional daily weather updates at 9 AM, 1 PM and 7 PM
> - Celsius or Fahrenheit, or follow your device setting
> - Designed for iPhone and iPad, in portrait and landscape
>
> PRIVATE BY DESIGN
> No account, no ads, no tracking. Sunny & Misty keeps your saved cities on your device. Anonymous usage statistics help improve the app, and you can turn them off in Settings.
>
> Weather data by OpenWeather and Open-Meteo.com. Radar by RainViewer. Maps © OpenStreetMap contributors.

**Keywords** (92/100, comma-separated, no spaces; the name and subtitle are already indexed)

> dog,cat,puppy,kitten,forecast,radar,rain,paws,pavement,heat,umbrella,hourly,leash,sunrise,uv

**URLs**

| Field | Value |
|---|---|
| Support URL | https://sunnyandmisty.com/support |
| Marketing URL (optional) | https://sunnyandmisty.com |
| Privacy policy URL | https://sunnyandmisty.com/privacy |

**Screenshots** (both sets are required, because the app runs on iPhone and iPad):
- 6.9-inch iPhone (1320 × 2868) from `screenshots/app-store/`, suggested order 02, 03, 04, 05, 06 (01 optional); the README's App Store section lists what each shows
- 13-inch iPad (2064 × 2752): `screenshots/app-store/ipad-02-tokyo.png`, then `ipad-01-amsterdam.png`

## App Review information

- Sign-in required: No
- Contact: Colin Tucker, colin@fangjet.com, plus a phone number
- Notes:

> Sunny & Misty needs no account. On first launch it asks for notification and location permission; both are optional. Without location, tap + to add any city by name. The best-walk-time card, hourly strip and radar appear on the main screen; tap a day in "Rest of week" for its hourly detail. Settings has units, permissions, saved cities and a "Share usage statistics" switch. Weather comes from OpenWeather and Open-Meteo, radar from RainViewer.

## Age rating

Answer **None** / **No** to every content question (violence, sexual content, profanity, horror, drugs, gambling, medical, contests). No unrestricted web access (links open in Safari), no user-generated content, no messaging. Result: **4+**.

## App Privacy (nutrition label)

Tracking: **No**. Data collected, all **not linked to the user's identity** and **not used for tracking**:

| Data type | Purpose | Why |
|---|---|---|
| Location > Precise Location | App Functionality | Coordinates of the active city or current location are sent to the weather services to fetch a forecast |
| Location > Coarse Location | Analytics | Google Analytics derives general location from the (masked) IP address |
| Identifiers > Device ID | Analytics | Google Analytics assigns a per-install app instance ID |
| Usage Data > Product Interaction | Analytics | The four anonymous events (onboarding complete, city added, settings opened, weather error) |

Not collected: contact info, health, financial, user content, browsing or search history, contacts, purchases, diagnostics. No advertising ID (FirebaseAnalyticsCore, no AdSupport).

## Export compliance

Answered in the build (`ITSAppUsesNonExemptEncryption = NO`); App Store Connect won't ask.

## Before you submit

Not settled by code; each needs an outside answer or account:

- **Signing team**: FangJet LLC (`3V3NR8HP58`), with automatic signing. Xcode needs the colin@fangjet.com account added under Settings, then Accounts.
- **RainViewer**: the free radar API is offered "for personal and educational use only". Get written permission or a commercial agreement for a published app, or launch with Remote Config `radar_enabled` set to false.
- **Open-Meteo**: the free API is for non-commercial use. Confirm with Open-Meteo that a free, ad-free app from FangJet LLC qualifies, or take a paid plan; until then `open_meteo_enabled` can fall back to OpenWeatherMap.
- **OpenWeather key**: it ships inside the app (Secrets.plist), so anyone can extract it. Watch usage in the OpenWeather dashboard and rotate it if it's abused; a small key-proxy backend would remove it from the app entirely.
- **OpenStreetMap tiles**: requests now identify the app and are cached, as the tile policy asks, but heavy use of tile.openstreetmap.org can still be blocked. At scale, move to a commercial tile provider.
