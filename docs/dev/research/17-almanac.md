# 17 — Almanac: what it could provide, and for whom

**Research, not design.** Facts and candidates for the almanac driver (12d, M3.4): what data exists, which designed device or driver would use it and why, where it comes from, how it behaves offline. Proposals in §7 are not binding.

Input from Tomas (2026-10-28):

- **Forecast:** the almanac is authoritative.
- **Actuals:** local hardware sensors first; the almanac only where none is available.
- The almanac provides the **sun position** and **how much light the sun gives, in %**, from visibility and clouds.
- Light % is the **clear-sky index** (§3.2 A): `100 × GHI / GHI_clear`.

## 1. Who asks for what

Places in the design that already wait for the almanac, and candidates found here.

| Consumer | Needs | For | Status |
|---|---|---|---|
| `WindowCovering` (12c-06 §3.4) | gust m/s + the time it applies to | built-in wind protection | Open → M3.4 |
| `WindowCovering` rules (12c-06 says sun/rain/frost are rules) | sun azimuth/elevation, sun on a facade, light % | sun shading, glare, heat gain | candidate |
| `Closure` roof/facade windows (12c-07) | rain now / soon, gust, storm warning | close before rain or storm | candidate |
| `driver-rainwater` (12i §11) | rain amount expected in the next hours | early transfer to make room | Open → M3.4 |
| `IrrigationSystem` (12c-08 §1.2: "a rule or the almanac calls `run`") | rain past 24 h and forecast, ET₀, soil moisture, frost | rain skip, seasonal adjust, no watering in frost | candidate |
| `Thermostat` / `RoomAirConditioner` (12c-10) | outdoor temperature (3 h and 24 h averages), later forecast | source order, cooling/AC-heating lockouts | `outdoor` role exists; source = local first (Input) |
| `Thermostat` presets (12c-10: "a rule or the almanac sets `preset`") | workday / weekend / public holiday, school holiday | comfort vs eco by calendar | candidate |
| Central heating (12h, M3.3e) | outdoor actual (ISM8i first), forecast min/max | summer mode, pre-heat before a cold night | candidate |
| Heat recovery unit (research/16 §4.5) | outdoor temperature + humidity at night, air quality | night ventilation, close intake on smog/pollen | candidate |
| Lights, rules (12b), `TimerRelay` (12c-05: "time of day and schedules — the almanac driver") | sunrise, sunset, civil dusk/dawn, light % | lights on at dusk, not at a fixed time | candidate |
| `LightSensor` (12c-04) fallback | estimated outdoor light | rules where no lux sensor is fitted | candidate |

## 2. Calendar

Computed locally — no network.

| Item | Example | Use |
|---|---|---|
| day kind | `workday`, `weekend`, `publicHoliday` | presets, schedules |
| holiday name | "Den české státnosti" | UI |
| school holidays | `school` type | family schedules |
| DST change today | `dstShift: +1h` | timers, rules around 02:00–03:00 |
| season | astronomical or meteorological | rule conditions |

- **`date-holidays`** (npm): ISC code, data CC BY-SA 3.0; 206 countries; subdivisions by ISO 3166-2; types `public`, `bank`, `school`, `optional`, `observance`; data ships in the package, no network call; holiday `start`/`end` in the zone of the chosen country/region; `isHoliday(date)`, `getHolidays(year)` [V S9]. How complete school holidays are per country: [GAP] — not stated [V S9].
- CC BY-SA on the data may matter for distribution — not checked [I].

## 3. Sun

### 3.1. Position and times

Computed locally from latitude, longitude and time — no network.

| Item | Example |
|---|---|
| `elevation`, `azimuth` (°) | `{ elevation: 23.4, azimuth: 212.0 }` |
| times | sunrise, sunset, solar noon, civil dawn/dusk, nautical, astronomical |
| sun on a facade | `facadeAzimuth` 225°, sun azimuth within ±90° and elevation > 0 ⇒ sun hits the facade [I] |

- **SunCalc** (npm `suncalc`): BSD; `getPosition` → `altitude`, `azimuth` in radians, azimuth "measured from south to west"; `getTimes` → 14 named times (sunrise, sunriseEnd, goldenHourEnd, solarNoon, goldenHour, sunsetStart, sunset, dusk, nauticalDusk, night, nadir, nightEnd, nauticalDawn, dawn); `addTime(angle, …)` for own angles; moon position and phase; formulas from Astronomy Answers [V S10].
- **NREL SPA** (`solar-spa`, WASM; pure JS port `nrel-spa`): MIT wrapper, the NREL C source under its own terms; zenith, azimuth, incidence angle, sunrise, sunset, solar noon [V S11]. Accuracy not stated on the page [GAP].
- For shading, SunCalc's accuracy is likely enough; SPA if exact angles matter [I]. SunCalc's south-based azimuth differs from the usual north-based compass [V S10] — pick one convention for the DeviceType [I].

### 3.2. Light in % — candidates

What "how much light the sun gives" can be built from:

| Candidate | Formula | Source data | Note |
|---|---|---|---|
| **A. clear-sky index** | `light% = 100 × GHI / GHI_clear` | GHI forecast/actual; clear-sky GHI from a model | the physical answer: 100 % = as bright as a cloudless sky could be now. Needs a clear-sky model |
| **B. sunshine share** | `light% = 100 × sunshine_duration / 3600` | Open-Meteo `sunshine_duration` (s per hour; direct > 120 W/m²) [V S2] | "how long the sun shines"; 0 or 100 in most hours [I] |
| **C. cloud-based** | Kasten–Czeplak: `G = G_clear × (1 − 0.75 (N/8)^3.4)`, N in octas | cloud cover only | form and 0.75 [V S5]; exponent 3.4 not readable in the source — [GAP] |
| **D. linear cloud** | `G = G_clear × (off + (1 − off)(1 − cc))`, off = 35 % | cloud cover only | pvlib, after Larson et al. 2016: "0% cloud cover returns ghi_clear. 100% … returns offset*ghi_clear" [V S6] |
| **E. per facade** | `GTI(tilt 90°, azimuth facade)` in W/m² | Open-Meteo `global_tilted_irradiance` [V S3] | heat on a window, not a % — for shading and room gain |

- Clear-sky GHI from Open-Meteo: `shortwave_radiation_clear_sky` exists "only for DWD MTG data" (Satellite Radiation API) [V S3]. Otherwise a local clear-sky model is needed (e.g. Haurwitz, Ineichen) [I]; formula not verified here [GAP].
- **Visibility** is a weak input: Open-Meteo says visibility (DWD ICON) "is only available until November 2026" [V S2]. Fog shows in MET Norway's `fog_area_fraction` and in cloud cover [V S7].
- Outdoor lux from W/m²: a luminous-efficacy factor [I], not verified [GAP].

## 4. Weather

### 4.1. Variables worth taking

| Variable | Open-Meteo (DWD ICON) [V S2] | MET Norway [V S7] | Main use |
|---|---|---|---|
| temperature 2 m | yes | `air_temperature` | climate, heating, frost |
| humidity, dew point | yes | yes | night ventilation, frost on covers |
| precipitation amount | yes (+ rain, showers, snowfall) | `precipitation_amount` (+ min/max), 1 h and 6 h | rainwater, irrigation, windows |
| precipitation probability | ensemble share > 0.1 mm/h | `probability_of_precipitation` | windows, irrigation |
| thunder | lightning potential, CAPE | `probability_of_thunder` | covers up, windows shut |
| wind speed, gust, direction | 10 m; gust = max of preceding hour (research/matter/06 §4.4) | `wind_speed_of_gust` m/s | wind protection |
| cloud cover total/low/mid/high | % | `cloud_area_fraction` (+ low/medium/high) | light % |
| fog | — | `fog_area_fraction` | light % |
| radiation GHI, DNI, diffuse, GTI | yes, hourly mean or `_instant` | — | light %, shading, gain |
| sunshine duration | s per hour | — | light % (B) |
| ET₀ (FAO-56) | `et0_fao_evapotranspiration` | — | irrigation amount |
| soil temperature / moisture | 0–54 cm / 0–81 cm | — | irrigation, frost |
| weather code | WMO codes | `symbol_code` | UI icon |
| UV index | not on ICON page; Air Quality API has `uv_index` [V S4] | `ultraviolet_index_clear_sky` | UI |

### 4.2. Resolution and update

- Open-Meteo ICON: ICON-D2 ~2 km, 2 days, every 3 h, 15-minutely; ICON-EU ~7 km, 5 days, every 3 h; ICON global ~11 km, 7.5 days, every 6 h [V S2]. The page lists ICON-D2 for "Germany, Switzerland, Austria"; whether Brno is inside its domain: [GAP].
- `minutely_15` native only in Central Europe, interpolated elsewhere [V S2].
- `current` = every hourly variable as the current value [V S2]. It is a model value, not a measurement [I].
- `past_days` 0–92 [V S2] — fills averages and rain sums after an outage.
- MET Norway: hourly for ~60 h, then 6-hourly up to ~10 days [V S7].

## 5. Warnings and air quality

- **ČHMÚ warnings** as CAP 1.2 XML (systems SIVS, HPPS, SVRS); `awareness_type` e.g. Wind, snow-ice, Thunderstorm, Fog, high-temperature, low-temperature, forest-fire, Rain, flooding; `severity` Minor…Extreme ↔ Meteoalarm levels 1–4 (green…red); area per kraj or listed ORP, `geocode` CISORP, also EMMAID/NUTS3; no polygons; `onset` = expected start, `expires` = end of validity, absent for warnings "do odvolání" [V S8]. Feed URL and update rate are not in the document [GAP].
- **Use:** an official storm/wind warning raises covers and closes windows before the gust arrives — the forecast's 10 m wind "says nothing of the facade" (research/matter/06 §4.4) [I].
- **Air quality — Open-Meteo Air Quality API (CAMS):** PM10, PM2.5, O₃, NO₂, European AQI, UV index; pollen (alder, birch, grass, mugwort, olive, ragweed) "only available in Europe during pollen season with 4 days forecast"; CAMS Europe ~11 km, hourly, updated every 24 h [V S4]. Use: heat recovery intake, "don't open windows" [I].

## 6. Sources: terms and offline

| | Open-Meteo | MET Norway |
|---|---|---|
| key | none for the free API [V S1] | none; identifying `User-Agent` required [V S12] |
| free use | non-commercial; "personal home automation purposes" named as an example [V S1] | — |
| limits | < 10 000 calls/day, 5 000/h, 600/min [V S1] | > 20 req/s per application needs agreement [V S12] |
| licence | CC BY 4.0 [V S1] | CC BY 4.0 — credit, link, changes [V S12] |
| client duties | — | cache; `If-Modified-Since`; don't fetch before `Expires`; coordinates ≤ 4 decimals (5+ ⇒ 403 on new products) [V S12] |
| breach | — | 429, permanent ban on deliberate breach [V S12] |

- An installer running evok-node for paying customers is likely commercial under Open-Meteo's terms → paid plan or another source [I]. The almanac should allow more than one provider [I].
- Hourly fetch for one location = 24 calls/day, plus air quality — far under the limits [I].
- **Offline by kind:** calendar and sun are local and always available; forecast and warnings are cached with their fetch time and go stale; actuals from hardware need no network [I].

## 7. Proposals (not binding)

- **P1 — one almanac per site.** One instance (location, providers) on one PLC; other PLCs import its devices over a remote link (12a §4b) [I].
- **P2 — actual = local first.** A role takes a hardware source first and the almanac's `current` as fallback; the value says where it came from, e.g. `{ value: 7.2, source: 'local' | 'almanac', at }` [I]. Matches the Input rule.
- **P3 — light % as A (clear-sky index)** — chosen (Input) with B as a second field; E (per-facade GTI) as a separate reading for shading. Needs a local clear-sky model; Open-Meteo has clear-sky only for satellite data.
- **P4 — wind for 12c-06:** `{ gustMs, at, kind: 'forecast' | 'measured' }`; forecast gust = max of the hour it ends at.
- **P5 — rain for 12i §11:** `rainNextMm { h3, h6, h24 }` and probability; `rainPastMm { h24 }` for irrigation.
- **P6 — warnings as a device** with active list `{ type, level, onset, expires }` for the site's CISORP, so rules react to level ≥ 2.
- **P7 — averages in the almanac or the consumer?** 12c-10 needs 3 h and 24 h outdoor averages. Computing them where the value is made (one place) vs in each thermostat — to decide in 12d [I].

## 8. Gaps

- Kasten–Czeplak exponent; a verified clear-sky formula.
- Brno inside ICON-D2's domain; what replaces ICON visibility after November 2026.
- ČHMÚ CAP feed URL and update rate.
- MET Norway: which fields are only in `/complete`.
- `date-holidays` school holidays for CZ; CC BY-SA impact.
- Open-Meteo `current` — how often it refreshes.
- Outdoor lux from W/m².

## 9. Sources

- S1 — Open-Meteo, Terms & Privacy: https://open-meteo.com/en/terms
- S2 — Open-Meteo, DWD ICON API: https://open-meteo.com/en/docs/dwd-api
- S3 — Open-Meteo, Satellite Radiation API: https://open-meteo.com/en/docs/satellite-radiation-api
- S4 — Open-Meteo, Air Quality API: https://open-meteo.com/en/docs/air-quality-api
- S5 — Kasten & Czeplak (1980), *Solar Energy* 24(2), 177–189, as cited and used in CSBE paper CSBE17057: https://library.csbe-scgab.ca/docs/meetings/2017/CSBE17057.pdf
- S6 — pvlib 0.9.0, `cloud_cover_to_ghi_linear`: https://pvlib-python.readthedocs.io/en/v0.9.0/generated/pvlib.forecast.NAM.cloud_cover_to_ghi_linear.html
- S7 — MET Norway, forecast JSON format: https://docs.api.met.no/doc/ForecastJSON
- S8 — ČHMÚ, CAP documentation: https://opendata.chmi.cz/meteorology/weather/alerts/metadata/Dokumentace_CAP.pdf
- S9 — `date-holidays` 3.33.0 README: https://unpkg.com/date-holidays@3.33.0/README.md
- S10 — SunCalc README (copy in a `node_modules`): https://git.efi.th-nuernberg.de/gitea/partoschph68073/SmartMirror-Projektarbeit/blame/branch/master/node_modules/suncalc/README.md
- S11 — `solar-spa`: https://github.com/acamarata/solar-spa
- S12 — MET Norway, Terms of Service: https://docs.api.met.no/doc/TermsOfService
