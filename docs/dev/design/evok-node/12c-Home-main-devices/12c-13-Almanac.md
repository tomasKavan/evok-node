# 12c-13 — Almanac

## 1. Scope

| DeviceType | Adds | Matter (16a) |
|---|---|---|
| `Calendar` | today and tomorrow: day kind, holidays, DST | none — 16a ignores it |
| `Clock` | the minute tick — what time-based rules trigger on | none — 16a ignores it |
| `Sun` | position, phase, today's times, light % | none — 16a ignores it |
| `WindSensor` | wind now (gust with its time) and the gust forecast | none — 16a ignores it |
| `RainSensor` | raining now, past and coming rain | Rain Sensor `0x0044` |
| `Weather` | the site's weather at a glance: now, today, tomorrow, warnings, air | none — 16a ignores it |

The source is the almanac driver (12d). The home types are declared in `driver-home`, as every home type; the templates and the bundle are in `@evok-node/driver-almanac/home` (12a §3).

| Template | DeviceType | Roles |
|---|---|---|
| `calendar-from-almanac` (§3.1) | `Calendar` | `calendar`: `almanac.calendar`, 1 |
| `clock-from-almanac` (§3.1) | `Clock` | `clock`: `almanac.clock`, 1 |
| `sun-from-almanac` (§3.1) | `Sun` | `sun`: `almanac.sun`, 1 |
| `wind-from-almanac` (§3.2) | `WindSensor` | `outdoor`: `almanac.outdoor`, 1 · `forecast`: `almanac.forecast`, 0–1 |
| `rain-from-almanac` (§3.3) | `RainSensor` | `outdoor`: `almanac.outdoor`, 1 · `forecast`: `almanac.forecast`, 0–1 |
| `weather-from-almanac` (§3.4) | `Weather` | `status`: `almanac.status`, 1 · `outdoor`, `forecast`: 1 each · `warnings`, `air`: 0–1 each |
| `temperature-from-almanac` (§3.5) | `TemperatureSensor` (12c-04) | `outdoor`: `almanac.outdoor`, 1 |
| `humidity-from-almanac` (§3.5) | `HumiditySensor` (12c-04) | `outdoor`: `almanac.outdoor`, 1 |
| bundle `almanac` (§3.6) | all of the above | anchor `almanac.status` |

**For:** rules that react to time, the sun and the weather (12b); the Home UI's weather tile; wind protection of covers (12c-06 §3.4); a thermostat's `outdoor` role (12c-10).

**Not for:**

- Schedules as devices. A schedule is a rule on `Clock` (§1.2).
- History and charts beyond `Weather.series` (12d §1).
- A facade's sun. A rule compares `Sun.position.azimuth` with the facade's azimuth.

Every device follows its almanac endpoint; nothing is saved (12a §3). On a flat's PLC the source is the local replica (12d §6), so these devices stay `reachable` while the master is down; what the master can no longer give shows as `source: 'forecast'` or `stale`.

### 1.1. Which device for what

| A rule that… | Triggers on |
|---|---|
| runs at 06:30 on workdays | `Clock.now`, with `Calendar` as a device option (12b §3) |
| runs at dusk, or 15 min before it | `Sun.phase`, or `Clock.now` against `Sun.times` |
| shades a facade | `Sun.position` and `Sun.light` |
| skips irrigation after rain | `RainSensor.rainPast` / `rainNext`, as a device option |
| closes roof windows before a storm | `RainSensor.raining`, `Weather.warnings` |

### 1.2. Time in rules

`Clock.now` changes once a minute; a rule kind holds the time it waits for as an option and compares at each change. No built-in kind does this yet (12b §2.1); a kind that does follows these rules:

- **Time spec.** `at: 'HH:MM'` local, or `{ phase, offsetMin }` against `Sun.times` — `offsetMin` negative = before. Optional `days` (weekdays) and `dayKinds` (`Calendar.today.kind`).
- **A time that doesn't exist** (spring DST) fires at the next minute that does.
- **A time that happens twice** (autumn DST) fires once — the kind keeps the date it last fired in its rule state (12b §5.5).
- **A missed tick** — the daemon down at 06:30 — is not made up.

## 2. Fields

```ts
// @evok-node/driver-home
const opt     = Codecs.optional;
const Ts      = Codecs.timestamp();
const DateStr = Codecs.string();                                   // 'YYYY-MM-DD', local
const Pct     = Codecs.float32({ min: 0, max: 100, unit: '%' });
const Celsius = Codecs.float32({ unit: '°C' });
const Deg     = Codecs.float32({ unit: '°' });
const Ms      = Codecs.float32({ min: 0, unit: 'm/s' });
const Mm      = Codecs.float32({ min: 0, unit: 'mm' });
const MmH     = Codecs.float32({ min: 0, unit: 'mm/h' });
const Source  = Codecs.string({ enumValues: ['local', 'model', 'forecast'] });   // 12d §4.5

const Day = Codecs.struct({
  date: DateStr,
  weekday: Codecs.string({ enumValues: ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'] }),
  kind: Codecs.string({ enumValues: ['workday', 'weekend', 'publicHoliday'] }),
  holidays: Codecs.array(Codecs.struct({ name: Codecs.text(), type: Codecs.string({ enumValues: ['public', 'bank', 'optional', 'observance'] }) })),
  dst: opt(Codecs.struct({ shiftMin: Codecs.int16(), at: Ts })),
});

export const Calendar = device('home.Calendar', {
  ...CommonFields,
  today:    reading(Day, { subscribe: true }),
  tomorrow: reading(Day, { subscribe: true }),
  season:   reading(Codecs.string({ enumValues: ['spring', 'summer', 'autumn', 'winter'] }), { subscribe: true }),
});

export const Clock = device('home.Clock', {
  ...CommonFields,
  now:  reading(Codecs.struct({ hour: Codecs.uint8({ max: 23 }), minute: Codecs.uint8({ max: 59 }), date: DateStr, at: Ts }), { subscribe: true }),
  hour: reading(Codecs.uint8({ max: 23 }), { subscribe: true }),
});

const Phase = Codecs.string({ enumValues: [
  'night', 'astroDawn', 'nauticalDawn', 'civilDawn', 'day', 'civilDusk', 'nauticalDusk', 'astroDusk'] });

export const Sun = device('home.Sun', {
  ...CommonFields,
  position: reading(Codecs.struct({ elevation: Deg, azimuth: Deg }), { subscribe: true }),   // compass, 0 = north
  phase:    reading(Phase, { subscribe: true }),
  next:     reading(Codecs.struct({ phase: Phase, at: Ts }), { subscribe: true }),
  times:    reading(Codecs.struct({ date: DateStr, civilDawn: opt(Ts), sunrise: opt(Ts), solarNoon: Ts,
              sunset: opt(Ts), civilDusk: opt(Ts) }), { subscribe: true }),
  light:    reading(Codecs.struct({ percent: opt(Pct), source: Source, at: Ts }), { subscribe: true }),   // absent below 5° (12d §4.4)
});

export const WindSensor = device('home.WindSensor', {
  ...CommonFields,
  wind:     reading(Codecs.struct({ speed: opt(Ms), gust: opt(Ms), direction: opt(Deg), source: Source, at: Ts }), { subscribe: true }),
  forecast: optional(reading(Codecs.struct({ gustMaxH6: Ms, gustMaxH24: Ms, at: Ts }), { subscribe: true })),
});

export const RainSensor = device('home.RainSensor', {
  ...CommonFields,
  raining:  reading(Codecs.bool(), { subscribe: true }),
  rate:     reading(opt(MmH), { subscribe: true }),
  source:   reading(Source, { subscribe: true }),
  rainPast: reading(Codecs.struct({ h24: opt(Mm), h72: opt(Mm) }), { subscribe: true }),
  rainNext: optional(reading(Codecs.struct({ h3: Mm, h6: Mm, h24: Mm, probability6h: Pct }), { subscribe: true })),
});

const Sky = Codecs.string({ enumValues: ['clear', 'partlyCloudy', 'cloudy', 'fog', 'drizzle', 'rain', 'snow', 'thunderstorm'] });
const DayOutlook = Codecs.struct({ date: DateStr, min: Celsius, max: Celsius, rainMm: Mm, lightPct: opt(Pct), sunnyH: Codecs.float32({ unit: 'h' }) });

export const Weather = device('home.Weather', {
  ...CommonFields,
  now:      reading(Codecs.struct({ temperature: opt(Celsius), humidity: opt(Pct), sky: opt(Sky), source: Source, at: Ts }), { subscribe: true }),
  days:     reading(Codecs.array(DayOutlook), { subscribe: true }),            // today, tomorrow, +1 — to the horizon
  warnings: optional(reading(Codecs.array(Codecs.struct({ type: Codecs.string(), level: Codecs.uint8({ min: 1, max: 4 }),
              onset: opt(Ts), expires: opt(Ts), text: Codecs.text() })), { subscribe: true })),
  air:      optional(reading(Codecs.struct({ europeanAqi: opt(Codecs.uint16()), pollen: Codecs.bool() }), { subscribe: true })),   // pollen: in season
  issuedAt: reading(opt(Ts), { subscribe: true }),
  credits:  reading(Codecs.array(Codecs.text()), { subscribe: true }),        // shown with the tile
  series:   method('reads', Codecs.struct({ from: Ts, hours: Codecs.uint16({ min: 1, max: 312 }) }),
              Codecs.array(Codecs.json()), { errorKinds: ['outOfRange'] }),   // 12d `forecast.series` rows, passed through
});
```

- `identify` is unbound on all six.
- `Sun.times` carries the civil times only; the nautical and astronomical ones stay on the driver's `sun` (12d §3).

## 3. Templates

Nothing saved; no settings unless named. A source not reachable makes the device not `reachable` (12a §4.2); a role marked 0–1 that is unbound leaves its optional field unbound.

### 3.1. `calendar-from-almanac`, `clock-from-almanac`, `sun-from-almanac`

Each field is its source's field of the same name, emitted when the source emits. `Sun.light` drops `ghi` and `ghiClear`.

### 3.2. `wind-from-almanac`

- `wind` = `outdoor.wind`: `value` spread, `source` and `at` kept. A `stale` source value is shown as it is; staleness is for the consumer to judge by `at`.
- `forecast` = `forecast.gustMax` (`h6`, `h24`, `at`); unbound without the role.
- As 12c-06's `wind` role, the cover reads `wind.gust` and `wind.at` (12c-06 §3.4). The gust is the maximum of the preceding hour from the model, or of the slot from the cached run.

### 3.3. `rain-from-almanac`

- `raining`, `rate`, `source` from `outdoor.rain`; `rainPast` from `outdoor.rainPast`; `rainNext` from `forecast.rainNext`, unbound without the role.
- Value absent ⇒ `raining` false, `rate` absent — and the device stays `reachable`: no rain information is not rain.

### 3.4. `weather-from-almanac`

| Field | From |
|---|---|
| `now` | `outdoor.temperature`, `outdoor.humidity`, `forecast.sky`; `source` and `at` of the temperature |
| `days` | `forecast.temp`, `forecast.light.days`, and rain per day from `series` — computed at each new `issuedAt` and at the first tick of a day |
| `warnings` | `warnings.active` |
| `air` | `air.quality.europeanAqi`; `pollen` true when `air.pollen` is present |
| `issuedAt`, `credits` | `forecast.issuedAt`, `status.credits` |
| `series` | forwarded to `forecast.series` |

### 3.5. `temperature-from-almanac`, `humidity-from-almanac`

- `temperature` / `humidity` = the `outdoor` field's `value`. Absent value ⇒ not `reachable`.
- For 12c-10's `outdoor` role. Its 3 h and 24 h averages are the thermostat's own (12c-10 §1); the almanac's `outdoor.averages` serve rules and other drivers.

### 3.6. Bundle `almanac`

| Anchor | Members |
|---|---|
| `almanac.status`, 1 | `calendar` · `clock` · `sun` · `wind` · `rain` · `weather` · `outdoorTemperature` · `outdoorHumidity` |

`resolve` uses the anchor's driver id and its `parts` (12d §3): the tails are fixed — `calendar`, `clock`, `sun`, `outdoor`, `forecast` — and `warnings`, `air` only when `parts` says so.

```
anchor  almanac:status   parts { air: true, warnings: true }
  → calendar  { calendar: ['almanac:calendar'] }
  → weather   { status: ['almanac:status'], outdoor: ['almanac:outdoor'], forecast: ['almanac:forecast'],
                warnings: ['almanac:warnings'], air: ['almanac:air'] }
  → …
```

On the basement PLC the bundle's devices are created with `exposed` false (12d §6): each flat creates its own from its replica.

## 4. Matter

- **`RainSensor`** → Rain Sensor `0x0044` (Matter 1.3; research/matter/09): BooleanState `StateValue` = `raining`. Controller support not known — no product found (research/matter/09). Tested in M3.13.
- **`temperature-from-almanac`, `humidity-from-almanac`** are a `TemperatureSensor` and a `HumiditySensor`: mapped as 12c-04 §4.
- **`Calendar`, `Clock`, `Sun`, `WindSensor`, `Weather`:** no Matter counterpart; 16a ignores them.

## 5. Moving and target

Nothing moves and nothing is set. Every field reports at its source's change.

## 6. Open

- **Built-in time rule kinds** (§1.2). None for now; added to 12b when needed.
- **A hardware `WindSensor` template** — an anemometer on a DI counter (12c-06 §3.4, 12d §9).
