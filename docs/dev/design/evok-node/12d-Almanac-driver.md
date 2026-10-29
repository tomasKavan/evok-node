# 12d — Almanac driver

## 1. Scope

Package: `packages/driver-almanac` (`@evok-node/driver-almanac`). Config `type: almanac`. Kinds `almanac.*`.

The site's calendar, clock, sun and weather: what other drivers, templates and rules need to know about time and the outside. Its endpoints are raw driver-kit devices (05a), shown in the Inspector UI (16). The Home UI and rules see them through the home devices of 12c-13; their templates are in the `@evok-node/driver-almanac/home` subpath.

```
providers (Open-Meteo, ČHMÚ) ──► master almanac (basement PLC) ──RemoteLink──► replica almanac (each other PLC)
local sensors (master's PLC) ──►        │                                           │
                                 almanac.* endpoints                         almanac.* endpoints, the same
                                        │                                           │
                          12c-13 templates, 12i, 12c-10, rules           12c-13 templates, rules
```

- **One master per site.** It alone calls providers and reads local sensors.
- **A replica on every other PLC.** It takes the master's configuration, computes calendar, clock and sun itself, and relays the rest. Consumers on its PLC address it locally; the master being down shows as `source` and `stale` on values, never as `unreachable` (§6).
- **Forecast is the almanac's.** For actual values, a local sensor comes first; the model only where there is none (§4.5).

**Not for:**

- History. Only the latest forecast run and 72 h of actual values are kept (§7). Timeseries storage of readings is a non-goal (README).
- Schedules. A schedule is a rule (12b) on `Clock` (12c-13 §1.2).
- Facades — sun on a wall, GTI. A rule compares `Sun.position.azimuth` with a facade's azimuth.
- Provider plugins. Providers are built in (§5).

**Must not depend on:** any api, `main`, another driver. The home templates import `driver-home`'s types (12a §3); the driver itself never does.

**Dependencies:** `suncalc` (BSD-2) for the sun, `date-holidays` (ISC; data CC BY-SA 3.0) for holidays — research/17 §2, §3.1. Both compute locally, no network.

## 2. Configuration

```ts
interface Location {
  readonly lat: number;            // degrees; sent to providers rounded to 4 decimals
  readonly lon: number;
  readonly elevationM?: number;
  readonly timeZone: string;       // IANA, e.g. 'Europe/Prague'
}

type Linear = { readonly address: Address; readonly in: [number, number]; readonly out: [number, number] };

interface AlmanacLocal {                                       // the master's own sensors — "local first" (§4.5)
  readonly temperature?: Address | Linear;                     // unipi.temp | unipi.ai
  readonly humidity?: Address;                                 // unipi.humidity
  readonly rain?: Address | { readonly address: Address; readonly invert: true };   // unipi.di — true = raining
  readonly ghi?: Linear | { readonly address: Address; readonly luxPerWm2: number }; // pyranometer on unipi.ai, or unipi.lux
  readonly lostAfterS?: number;                                // default 600
}

interface MasterConfig {
  readonly role: 'master';
  readonly location: Location;
  readonly calendar: { readonly country: string; readonly region?: string };   // ISO 3166-1 / 3166-2
  readonly forecast: { readonly provider: 'open-meteo'; readonly everyS?: number };   // default 900
  readonly air?: { readonly provider: 'open-meteo-air'; readonly everyS?: number };   // default 10800
  readonly warnings?: { readonly provider: 'chmi-cap'; readonly cisorp: number; readonly everyS?: number };   // default 600
  readonly local?: AlmanacLocal;
  readonly sunnyPct?: number;                                  // default 60 — §4.4
}

interface ReplicaConfig {
  readonly role: 'replica';
  readonly master: { readonly url: string; readonly driverId: string };   // the master's WS API and instance (05a §3.8b)
}

type AlmanacConfig = MasterConfig | ReplicaConfig;
```

```yaml
# basement PLC
drivers:
  almanac:
    type: almanac
    role: master
    location: { lat: 49.1951, lon: 16.6068, elevationM: 237, timeZone: Europe/Prague }
    calendar: { country: CZ }
    forecast: { provider: open-meteo }
    air:      { provider: open-meteo-air }
    warnings: { provider: chmi-cap, cisorp: 6203 }
    local:
      temperature: OW:28-0000081e1f2b.unipi.temp
      humidity:    OW:26-00000210c4d1.unipi.humidity

# flat PLC
drivers:
  almanac:
    type: almanac
    role: replica
    master: { url: wss://basement-plc/api, driverId: almanac }
```

- Fatal at `configure()`: a `timeZone` the runtime doesn't know; a `country` or `region` `date-holidays` doesn't know; `lat`/`lon` out of range.
- `local` on a replica does not exist — the type has none. A replica never calls a provider.

## 3. Endpoints

Bound once at `attach()`. `air` and `warnings` are bound only when the master configures them; a replica binds what the master's `status.parts` lists.

| Tail | Kind | What |
|---|---|---|
| `status` | `almanac.status` | role, the master link, shared config, credits, parts |
| `calendar` | `almanac.calendar` | today, tomorrow, look-ahead |
| `clock` | `almanac.clock` | the minute tick |
| `sun` | `almanac.sun` | position, phase, times, light % |
| `outdoor` | `almanac.outdoor` | actual values, averages, past rain |
| `forecast` | `almanac.forecast` | summaries; the run by `series` |
| `warnings` | `almanac.warnings` | active ČHMÚ warnings |
| `air` | `almanac.air` | air quality, pollen |
| `provider.forecast`, `provider.air`, `provider.warnings` | `almanac.provider` | fetch status — master only |

```ts
// @evok-node/driver-almanac
const opt     = Codecs.optional;
const Ts      = Codecs.timestamp();
const Pct     = Codecs.float32({ min: 0, max: 100, unit: '%' });
const Celsius = Codecs.float32({ unit: '°C' });
const Deg     = Codecs.float32({ unit: '°' });
const Ms      = Codecs.float32({ min: 0, unit: 'm/s' });
const Mm      = Codecs.float32({ min: 0, unit: 'mm' });
const MmH     = Codecs.float32({ min: 0, unit: 'mm/h' });
const Wm2     = Codecs.float32({ min: 0, unit: 'W/m²' });
const MinMax  = Codecs.struct({ min: Celsius, max: Celsius });
const Source  = Codecs.string({ enumValues: ['local', 'model', 'forecast'] });   // §4.5
const Sourced = <T>(c: TypedCodec<T>) => Codecs.struct({ value: opt(c), source: Source, at: Ts, stale: Codecs.bool() });
const DateStr = Codecs.string();                                                // 'YYYY-MM-DD', local date in `timeZone`
const LocationCodec = Codecs.struct({ lat: Codecs.float64(), lon: Codecs.float64(), elevationM: opt(Codecs.float32({ unit: 'm' })), timeZone: Codecs.string() });

export const Status = device('almanac.status', {
  role:    reading(Codecs.string({ enumValues: ['master', 'replica'] })),
  master:  optional(reading(Codecs.struct({ url: Codecs.string(), up: Codecs.bool(), syncedAt: opt(Ts) }), { subscribe: true })),
  config:  reading(opt(Codecs.struct({ location: LocationCodec, calendar: Codecs.struct({ country: Codecs.string(), region: opt(Codecs.string()) }),
             sunnyPct: Pct })), { subscribe: true }),                         // what a replica takes (§6); absent on a replica before its first sync
  credits: reading(Codecs.array(Codecs.text()), { subscribe: true }),          // CC BY attribution of the providers in use, for the UIs
  parts:   reading(Codecs.struct({ air: Codecs.bool(), warnings: Codecs.bool() }), { subscribe: true }),
});

const Holiday = Codecs.struct({ name: Codecs.text(), type: Codecs.string({ enumValues: ['public', 'bank', 'optional', 'observance'] }) });
const Day = Codecs.struct({
  date:     DateStr,
  weekday:  Codecs.string({ enumValues: ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'] }),
  isoWeek:  Codecs.uint8({ min: 1, max: 53 }),
  kind:     Codecs.string({ enumValues: ['workday', 'weekend', 'publicHoliday'] }),
  holidays: Codecs.array(Holiday),                                   // [] = none
  dst:      opt(Codecs.struct({ shiftMin: Codecs.int16(), at: Ts })), // the day of a change
});

export const Calendar = device('almanac.calendar', {
  today:    reading(Day, { subscribe: true }),
  tomorrow: reading(Day, { subscribe: true }),
  season:   reading(Codecs.string({ enumValues: ['spring', 'summer', 'autumn', 'winter'] }), { subscribe: true }),   // astronomical
  timeZone: reading(Codecs.string()),
  days:     method('reads', Codecs.struct({ from: DateStr, count: Codecs.uint16({ min: 1, max: 400 }) }), Codecs.array(Day),
              { errorKinds: ['outOfRange'] }),
});

export const Clock = device('almanac.clock', {
  now:  reading(Codecs.struct({ hour: Codecs.uint8({ max: 23 }), minute: Codecs.uint8({ max: 59 }), date: DateStr, at: Ts }),
          { subscribe: true }),                                      // every full minute, local wall time
  hour: reading(Codecs.uint8({ max: 23 }), { subscribe: true }),      // every full hour
});

const Phase = Codecs.string({ enumValues: [
  'night', 'astroDawn', 'nauticalDawn', 'civilDawn', 'day', 'civilDusk', 'nauticalDusk', 'astroDusk'] });
const SunTimes = Codecs.struct({ date: DateStr,
  astroDawn: opt(Ts), nauticalDawn: opt(Ts), civilDawn: opt(Ts), sunrise: opt(Ts), solarNoon: Ts,
  sunset: opt(Ts), civilDusk: opt(Ts), nauticalDusk: opt(Ts), astroDusk: opt(Ts) });   // absent = doesn't happen that day

export const Sun = device('almanac.sun', {
  position: reading(Codecs.struct({ elevation: Deg, azimuth: Deg }), { subscribe: true }),   // compass: 0 = north, clockwise
  phase:    reading(Phase, { subscribe: true }),
  next:     reading(Codecs.struct({ phase: Phase, at: Ts }), { subscribe: true }),
  times:    reading(SunTimes, { subscribe: true }),                                         // today
  light:    reading(Codecs.struct({ percent: opt(Pct), ghi: opt(Wm2), ghiClear: Wm2, source: Source, at: Ts }), { subscribe: true }),
  days:     method('reads', Codecs.struct({ from: DateStr, count: Codecs.uint16({ min: 1, max: 400 }) }), Codecs.array(SunTimes)),
});

export const Outdoor = device('almanac.outdoor', {
  temperature: reading(Sourced(Celsius), { subscribe: true }),
  humidity:    reading(Sourced(Pct), { subscribe: true }),
  wind:        reading(Sourced(Codecs.struct({ speed: Ms, gust: Ms, direction: Deg })), { subscribe: true }),   // gust: max of the preceding hour
  rain:        reading(Sourced(Codecs.struct({ mmH: opt(MmH), raining: Codecs.bool() })), { subscribe: true }),
  averages:    reading(Codecs.struct({ t3h: opt(Celsius), t24h: opt(Celsius) }), { subscribe: true }),
  rainPast:    reading(Codecs.struct({ h24: opt(Mm), h72: opt(Mm) }), { subscribe: true }),
});

const Sky = Codecs.string({ enumValues: ['clear', 'partlyCloudy', 'cloudy', 'fog', 'drizzle', 'rain', 'snow', 'thunderstorm'] });   // from WMO codes
const LightDay = Codecs.struct({ date: DateStr, meanPct: opt(Pct), sunnyH: Codecs.float32({ min: 0, unit: 'h' }) });
const Row = Codecs.struct({ at: Ts, minutes: Codecs.uint8(),          // 15 or 60 — the row's length
  temperature: opt(Celsius), humidity: opt(Pct), rainMm: opt(Mm), rainProbability: opt(Pct), wind: opt(Ms), gust: opt(Ms),
  cloudPct: opt(Pct), ghi: opt(Wm2), lightPct: opt(Pct), sky: opt(Sky), et0Mm: opt(Mm), past: Codecs.bool() });   // past: a ring-buffer actual

export const Forecast = device('almanac.forecast', {
  issuedAt:  reading(opt(Ts), { subscribe: true }),
  horizon:   reading(opt(Ts), { subscribe: true }),
  sky:       reading(opt(Sky), { subscribe: true }),                                      // the current slot
  rainNext:  reading(Codecs.struct({ h3: Mm, h6: Mm, h24: Mm, probability6h: Pct }), { subscribe: true }),
  gustMax:   reading(Codecs.struct({ h6: Ms, h24: Ms, at: Ts }), { subscribe: true }),     // at: when the 24 h maximum is expected
  thunder6h: reading(Pct, { subscribe: true }),
  frost:     reading(opt(Ts), { subscribe: true }),                                       // first slot ≤ 0 °C within 24 h
  temp:      reading(Codecs.struct({ today: MinMax, tomorrow: MinMax }), { subscribe: true }),
  et0:       reading(Codecs.struct({ today: Mm, tomorrow: Mm }), { subscribe: true }),
  light:     reading(Codecs.struct({ days: Codecs.array(LightDay), next3h: opt(Pct) }), { subscribe: true }),   // today and 2 more, to the horizon
  series:    method('reads',
               Codecs.struct({ from: Ts, hours: Codecs.uint16({ min: 1, max: 312 }), fields: opt(Codecs.array(Codecs.string())) }),
               Codecs.array(Row), { errorKinds: ['outOfRange'] }),                        // now − 72 h … horizon
});

const WarnType = Codecs.string({ enumValues: ['wind', 'thunderstorm', 'rain', 'snowIce', 'highTemp', 'lowTemp', 'fog', 'fire', 'flood', 'other'] });
const Level    = Codecs.uint8({ min: 0, max: 4 });   // 0 = none; 1–4 = Meteoalarm green…red

export const Warnings = device('almanac.warnings', {
  active:   reading(Codecs.array(Codecs.struct({ id: Codecs.string(), type: WarnType, level: Level,
              onset: opt(Ts), expires: opt(Ts), text: Codecs.text() })), { subscribe: true }),
  maxLevel: reading(Codecs.struct({ wind: Level, thunderstorm: Level, rain: Level, snowIce: Level,
              highTemp: Level, lowTemp: Level, fog: Level, fire: Level, flood: Level }), { subscribe: true }),
  stale:    reading(Codecs.bool(), { subscribe: true }),
});

const UgM3 = Codecs.float32({ min: 0, unit: 'µg/m³' });
const PollenLevel = Codecs.float32({ min: 0, unit: 'grains/m³' });
export const Air = device('almanac.air', {
  quality: reading(Codecs.struct({ europeanAqi: opt(Codecs.uint16()), pm25: opt(UgM3), pm10: opt(UgM3), at: Ts, stale: Codecs.bool() }),
             { subscribe: true }),
  pollen:  reading(opt(Codecs.struct({ alder: PollenLevel, birch: PollenLevel, grass: PollenLevel,
             mugwort: PollenLevel, ragweed: PollenLevel })), { subscribe: true }),       // absent out of season
});

export const Provider = device('almanac.provider', {
  status: reading(Codecs.struct({ provider: Codecs.string(), lastOk: opt(Ts), error: opt(Codecs.string()),
            nextAt: Ts, callsToday: Codecs.uint32() }), { subscribe: true }),
  fetch:  method('mutates', Codecs.void, Codecs.void, { errorKinds: ['tooSoon'] }),     // Inspector: fetch now; ≥ 60 s since the last
});
```

## 4. Computation

### 4.1. Clock

- A tick at every full minute of the system clock, rescheduled from the clock each time (04 §5.2), never by adding 60 s.
- `now` is local wall time in `timeZone`; `hour` changes with the first tick of an hour.
- Clocks are assumed in sync on every PLC. A jump of the system clock is followed at the next tick; ticks in between are not invented.
- DST: the spring hour that doesn't exist has no ticks; the autumn hour that happens twice ticks twice with the same `hour`/`minute` and a different `at`. How rules treat it is 12c-13 §1.2.

### 4.2. Calendar

- From `date-holidays` with `country` and `region`. `kind`: `publicHoliday` if a holiday of type `public` falls on the day; else `weekend` on Saturday and Sunday; else `workday`.
- `holidays` lists every type but `school`, which is not used.
- `today` and `tomorrow` change at the first tick of a day. `days` answers `outOfRange` beyond the years the data covers.

### 4.3. Sun

- Position and times from `suncalc`. Its azimuth (from south, radians) is converted to compass degrees.
- `phase` from the elevation, morning or evening by solar noon:

  | Elevation | Morning | Evening |
  |---|---|---|
  | ≥ −0.833° (sunrise, sunset) | `day` | `day` |
  | −6° … −0.833° | `civilDawn` | `civilDusk` |
  | −12° … −6° | `nauticalDawn` | `nauticalDusk` |
  | −18° … −12° | `astroDawn` | `astroDusk` |
  | < −18° | `night` | `night` |

- `position` is computed at every tick; `phase` and `next` change only at a boundary; `times` at the first tick of a day.

### 4.4. Light %

```
ghiClear = 1098 × cos z × exp(−0.059 / cos z), 0 when negative     // Haurwitz; z = apparent zenith (research/17 §3.2)
percent  = min(100, 100 × ghi / ghiClear)                          // absent while elevation < 5°
```

- `ghi` is the 15-minute instant value: the local sensor (§4.5), else Open-Meteo `shortwave_radiation_instant` of the current 15-min slot. `ghiClear` is computed for the same instant.
- A lux sensor is converted by `luxPerWm2`; no default — the value is the installer's.
- **Forecast:** the same formula per row of the run — 15-minute rows for about 2 days, then hourly `_instant` rows. `forecast.light.days[]`: `meanPct` over the day's slots with elevation ≥ 5°; `sunnyH` = hours with `lightPct` ≥ `sunnyPct`. `next3h`: mean over the next 3 h of such slots; absent when there are none.

### 4.5. Actual values — local first

Each `outdoor` field, and `sun.light.ghi`, takes the first source that has a value:

| Order | Source | `source` | Lost when |
|---|---|---|---|
| 1 | the local sensor (master only) | `local` | not reachable, its value stale, or no change of `at` for `lostAfterS` |
| 2 | the model's current slot (Open-Meteo `current`/`minutely_15`) | `model` | the last forecast fetch older than 2 × `everyS` |
| 3 | the cached run's slot for now | `forecast` | past the run's horizon |
| — | none | value absent | |

- `stale` is true while the value comes from 3, or from 2 with the fetch older than `everyS`.
- `wind`: no local anemometer yet (Open, §9). `rain.mmH` from a local DI is absent — the DI only says `raining`.
- A switch of source emits the field once; the value may jump.

### 4.6. Averages and past rain

- A ring buffer of 5-minute samples over 72 h: the temperature `outdoor` publishes, whatever its source, and the model's precipitation per slot.
- `t3h`, `t24h`: means over the window; absent when less than ⅔ of the window has samples.
- `rainPast.h24`, `h72`: sums of the model's precipitation; absent below ⅔ coverage.
- After a restart the buffer is restored from KV (§7); gaps up to 72 h are filled from the provider's past values (`past_days`).

### 4.7. Forecast summaries

Recomputed when a run arrives and at every full hour, from the run's rows after now. `rainNext.h3/h6/h24`: sums; `probability6h`: the highest slot probability in 6 h; `gustMax`: maxima and when; `thunder6h`: the highest lightning probability in 6 h; `frost`: the first slot ≤ 0 °C; `temp`, `et0`: per local day.

## 5. Providers

Built in, behind one internal interface each — no plugin kind.

```ts
interface ForecastProvider { fetch(loc: Location, pastDays: number): Promise<{ issuedAt: Date; rows: Row[]; current: Row }>; }
interface AirProvider      { fetch(loc: Location): Promise<{ quality: AirQuality; pollen?: Pollen }>; }
interface WarningsProvider { fetch(cisorp: number): Promise<Warning[]>; }
```

| Provider | Fetch | Calls/day at defaults |
|---|---|---|
| `open-meteo` | one request: `current`, `minutely_15` (2 days), `hourly` (7 days), `past_days` when filling (§4.6) | 96 |
| `open-meteo-air` | CAMS Europe: European AQI, PM2.5, PM10, pollen | 8 |
| `chmi-cap` | ČHMÚ CAP 1.2; `info` blocks whose `geocode` is `cisorp`; `awareness_type` → `WarnType`, Meteoalarm level → `Level` | 144 |

- Every request sends `User-Agent: evok-node/<version>`. Coordinates are rounded to 4 decimals.
- Failure: the next try at the next slot. HTTP 429: the interval doubles, up to 1 h, and halves back on success. `provider.<name>.status.error` holds the last error.
- Open-Meteo's free API is for non-commercial use, under 10 000 calls a day (research/17 §6). `status.credits` carries the CC BY credit; the UIs show it.
- A warning disappears from `active` at its `expires`, or when the feed no longer lists it.

## 6. Master and replica

| | Master | Replica |
|---|---|---|
| config | its own | the master's `status.config`, read over a `RemoteLink` (05a §3.8b) at each link-up, stored in KV |
| calendar, clock, sun (position, phase, times, `ghiClear`) | computed | computed, the same |
| providers, local sensors | yes | never |
| `outdoor` | §4.5 | the master's values, `source` kept. Master down: the cached run's slot (`forecast`), then absent |
| averages, past rain | ring buffer | its own ring buffer of what it publishes — §4.6, the same |
| `sun.light.ghi`, forecast summaries, `forecast.light` | §4.4, §4.7 | recomputed from the master's run, read by `series` at each new `issuedAt`. Master down: from the cached run, to its horizon |
| `warnings`, `air` | fetched | relayed. Master down: the last values, `stale` true; a warning still ends at its `expires` |
| `provider.*` | bound | not bound |

- Before its first sync a replica has no location: `calendar`, `sun` and `clock` (it needs `timeZone`) are not `reachable`, and `status.config` is absent. Once synced, it runs from KV even with the master down at start.
- A config change on the master reaches a replica at its next link-up or when `status.config` emits.
- The master's home devices are not `exposed` (12a §2.1); a flat's home devices come from its own replica.

## 7. Storage

The driver's KV namespace (06). No index, no history.

| Key | Holds | Size | Written |
|---|---|---|---|
| `run` | the latest forecast run | ~50 KB | at each new run |
| `ring` | the 72 h ring buffer | ~50 KB | every hour, and on stop |
| `warnings`, `air` | the last values | small | at each change |
| `masterConfig` | replica: the synced config | small | at each sync |

20-year size: constant — the same keys, replaced.

## 8. Failure modes

| Situation | Result |
|---|---|
| no network at the master | forecast ages; `outdoor` falls to local, then the cached run (§4.5); calendar, clock, sun unaffected |
| run older than its horizon | `forecast` summaries zero or absent, `issuedAt` kept; `outdoor` from local only |
| master down, at a replica | §6; calendar, clock, sun unaffected |
| replica never synced | §6 — nothing but `status` |
| KV not reachable at start | starts empty; ring buffer filled from `past_days` at the first fetch; an error logged |
| provider changes its format | that provider's `status.error`; its endpoints go `stale` |
| system clock jumps | §4.1 |

## 9. Open

- **Local anemometer** for `outdoor.wind` and `WindSensor` (12c-06 §3.4). → a hardware template with the first anemometer.
- **`luxPerWm2`** — a verified default (research/17 §8). → when a lux sensor is used for `ghi`.
- **ČHMÚ CAP feed URL and update rate** (research/17 §8). → before `chmi-cap` is coded.
- **ICON visibility ends November 2026** (research/17 §3.2): not used here; nothing to replace.

## 10. Testing

- Clock: ticks on the minute across a simulated DST change (spring: no 02:xx ticks; autumn: 02:xx twice).
- Calendar: CZ public holidays of a known year; `kind` precedence; `days` cap and `outOfRange`.
- Sun: phase boundaries and compass azimuth for Brno on fixed dates against published values; polar-day absences with a high latitude.
- Light %: Haurwitz against pvlib's for fixed zeniths; absent below 5°; clamp at 100.
- Local first: each source lost in turn, `source`/`stale` as §4.5.
- Providers: recorded responses as fixtures; 429 back-off; CAP filtering by `cisorp`.
- Replica: config sync, master down/up, summaries recomputed from the cached run, never a provider call.
