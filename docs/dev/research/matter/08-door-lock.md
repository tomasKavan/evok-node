# 08 — Door lock

**Research, not design.** What Matter defines for a door lock, what controllers do with it, how relay-driven locks (electric strike, motor lock) behave, and how a 2N Access Unit 2.0 / IP Verso 2.0 is controlled and observed over its HTTP API — including its user directory, for the deferred user management. Feeds 12c's `DoorLock` section and 13a (M3.6).

Input from Tomas (2026-10-25):

- Two lock kinds from the start: (a) opened by a relay output, in two variants — **unlock** and **latch release**; (b) opened through the HTTP API of a **2N Access Unit 2.0 / IP Verso 2.0**.
- User management is deferred, but how evok-node will cooperate with the 2N access API on users must be known now.
- Tomas's locks behave the same in both relay variants: a pulse releases the lock for a time set in the lock; the handle then opens it; closing the door locks it. Two states — `locked` / `unlocked` — are enough.
- Every door has a door contact on a DI.
- Identity and access (for 13a, M3.6):
  - one central identity provider; users get roles; a role grants access to devices, usually by the home hierarchy — role "tenant flat 1" controls every device in flat 1's rooms;
  - no user is created or edited from any Matter fabric;
  - the Home UI may ask for biometrics or a PIN before a lock operates; the PIN lives in the identity provider;
  - 2N devices, through Access Commander, use the identity provider's users and roles, PIN included;
  - a flat's devices are always exposed in one bridge, to the flat's own network;
  - from any Matter fabric, a user enters a PIN to identify themselves before a lock operates.

Spec data from connectedhomeip `data_model/1.0/`–`1.6/` (S1); spec prose from matter.js's copy of the spec text, Matter 1.6.1 numbering §5.2.x (S2).

## 1. Matter

### 1.1. Device type

| Item | Fact |
|---|---|
| Door Lock `0x000A` | Identify and Door Lock `0x0101` servers mandatory, all versions. Groups and Scenes: optional in 1.0–1.2, disallowed from 1.3 [V-src S1] |
| Revision | 2 (1.0–1.2), 3 (1.3–1.5), 4 (1.5.1, "Removed Zigbee related elements") [V-src S1] |
| User feature | the device type makes `USR` mandatory with `PIN`, `RID`, `FGP` or `FACE` in every version; from 1.5.1 the cluster says so itself [V-src S1] |
| Root node | from 1.5 a node with a Door Lock endpoint needs the Access Control `Extension` attribute (`ACLExtensionCond`) [V-src S1]. matter.js builds `AccessControlServer` with `Extension` [V-src S3]; present at runtime on a bridge: [GAP] |
| Door Lock Controller `0x000B` | a client — a keypad or remote that controls locks; not a lock [V-src S1] |
| Closure `0x0230` (1.5) | tag `Door` exists, but it is a moving barrier, not a lock — [07 §1](07-garage-door.md) [V] |

### 1.2. Features

| Bit | Code | Name | Since / until |
|---|---|---|---|
| 0 | `PIN` | PIN credential | 1.0 |
| 1 | `RID` | RFID credential | 1.0 |
| 2 | `FGP` | finger credentials | 1.0 |
| 3 | `LOG` | logging | removed 1.4 |
| 4 | `WDSCH` | week-day schedules | 1.0 |
| 5 | `DPS` | door position sensor | 1.0 |
| 6 | `FACE` | face credentials | 1.0 |
| 7 | `COTA` | credential over the air (PIN in remote commands); requires `PIN` | 1.0 |
| 8 | `USR` | users | 1.0 |
| 9 | `NOT` | notification | removed 1.4 |
| 10 | `YDSCH` | year-day schedules | 1.0 |
| 11 | `HDSCH` | holiday schedules | 1.0 |
| 12 | `UBOLT` | unbolting ("European door locks") | 1.2 |
| 13, 14 | `ALIRO`, `ALBU` | Aliro provisioning, Aliro BLE UWB | 1.4 |

All [V-src S1]. In 1.5.1 the legacy PIN/RFID commands without users (`M(!USR & …)`) are removed [V-src S1].

### 1.3. Attributes that matter here

| Attribute | Conformance | Note |
|---|---|---|
| `LockState` | M, nullable | null = unknown, e.g. after power-up [V-src S2 §5.2.9.1] |
| `LockType` | M | §1.4 |
| `ActuatorEnabled` | M | "Indicates if the lock is currently able to (Enabled) or not able to (Disabled) process remote Lock, Unlock, or Unlock with Timeout commands." [V S2] |
| `DoorState` | M(DPS) | §1.4; events `DoorOpenEvents`, `DoorClosedEvents`, `OpenPeriod` O(DPS) |
| `OperatingMode`, `SupportedOperatingModes` | M | modes §1.4. `SupportedOperatingModes` is inverted: bit 0 = supported [V-src S2 §5.2.9.25] |
| `AutoRelockTime` | O, uint32 s | "number of seconds to wait after unlocking a lock before it automatically locks again. 0=disabled. If set, unlock operations from any source will be timed." [V S2 §5.2.9.22] |
| `NumberOfTotalUsersSupported`, `CredentialRulesSupport`, `NumberOfCredentialsSupportedPerUser` | M(USR) | |
| `NumberOfPINUsersSupported`, `Min/MaxPINCodeLength` | M(PIN) | |
| `WrongCodeEntryLimit`, `UserCodeTemporaryDisableTime` | M(PIN \| RID), Admin write | lockout after wrong codes, remote PINs included [V S2 §5.2.9.32] |
| `RequirePINforRemoteOperation` | M(COTA & PIN), Admin write | §1.6 |
| `SendPINOverTheAir` | O(!USR & PIN) since 1.2 | so absent on any lock with users [I] |

All conformance [V-src S1, 1.5.1].

### 1.4. Enums

| Enum | Values |
|---|---|
| `LockState` | `NotFullyLocked`, `Locked`, `Unlocked`, `Unlatched` — "fully unlocked and the latch is pulled". `Unlatched` added 1.2, optional from 1.3 [V-src S1] |
| `LockType` | `DeadBolt`, `Magnetic`, `Other`, `Mortise`, `Rim`, `LatchBolt`, `CylindricalLock`, `TubularLock`, `InterconnectedLock`, `DeadLatch`, `DoorFurniture`, `Eurocylinder` (1.2). No electric strike [V-src S1] |
| `DoorState` | `DoorOpen`, `DoorClosed` (M); `DoorJammed`, `DoorForcedOpen`, `DoorUnspecifiedError`, `DoorAjar` (O) [V-src S1] |
| `OperatingMode` | `Normal`, `NoRemoteLockUnlock` (M); `Vacation`, `Privacy`, `Passage` (O). Modes that disable the remote interface answer Lock/Unlock with Failure [V S2 §5.2.6.15] |
| `LockOperationType` | `Lock`, `Unlock`, `NonAccessUserEvent`, `ForcedUserEvent`, `Unlatch` (1.2) [V-src S1] |
| `OperationSource` | `Unspecified`, `Manual`, `ProprietaryRemote`, `Keypad`, `Auto`, `Button`, `Schedule`, `Remote` (M), `RFID`, `Biometric`, `Aliro` (1.4) [V-src S1] |
| `OperationError` | `Unspecified`, `InvalidCredential`, `DisabledUserDenied`, `Restricted`, `InsufficientBattery` [V-src S1] |
| `AlarmCode` | `LockJammed` (M), `LockFactoryReset`, `LockRadioPowerCycled`, `WrongCodeEntryLimit`, `FrontEsceutcheonRemoved`, `DoorForcedOpen`, `DoorAjar`, `ForcedUser` [V-src S1] |

`LockType` for our hardware: maglock → `Magnetic`; strike → `Other` or `LatchBolt`; motor lock → `Mortise` / `DeadBolt` [I].

### 1.5. Commands — unlock vs unbolt

| Command | Conformance | Access |
|---|---|---|
| `LockDoor` | M | Operate, **timed** |
| `UnlockDoor` | M | Operate, timed |
| `UnlockWithTimeout(Timeout)` | O | Operate, timed |
| `UnboltDoor` | M(UBOLT), 1.2 | Operate, timed |
| `Toggle` | disallowed | — |

All [V-src S1]; each takes an optional `PINCode` O(COTA & PIN).

**Naming trap.** With `UBOLT`, Matter's *unlock* is our *latch release*, and Matter's *unbolt* is our *unlock*:

> "The Unbolt Door command retracts the bolt without pulling the latch. The Unlock Door command fully unlocks the door by retracting the bolt and briefly pulling the latch. While the latch is pulled, the lock state changes to Unlatched. Locks without unbolting support don't differentiate between unbolting and unlocking and perform the same operation for both commands." [V S2 §5.2.4.11]

| Ours | Lock with `UBOLT` | Lock without `UBOLT` |
|---|---|---|
| unlock (bolt back, latch stays) | `UnboltDoor` → `Unlocked` | `UnlockDoor` — physical effect left to the device [V S2] [I] |
| latch release | `UnlockDoor` → `Unlatched` → `Unlocked` | `UnlockDoor` |

- `UnlockDoor`, `UnboltDoor`: with `AutoRelockTime` the lock relocks when it expires [V S2 §5.2.10.2, §5.2.10.25].
- `UnlockWithTimeout`: relocks after `Timeout` s; a lock that cannot "SHOULD NOT support this optional command" [V S2 §5.2.10.3].

### 1.6. PIN on remote commands

- "If the RequirePINforRemoteOperation attribute is True then PINCode field shall be provided and the door lock shall NOT grant access if it is not provided." A PIN that is given is always checked [V S2 §5.2.10.1.1].
- A wrong PIN counts towards `WrongCodeEntryLimit`; past it, the lock ignores lock/unlock for `UserCodeTemporaryDisableTime` [V S2].
- Failure → status `Failure` + `LockOperationError(InvalidCredential)`; at the limit also `DoorLockAlarm(WrongCodeEntryLimit)`; during lockout `Failure` with no event — CHIP reference and matter.js alike [V-src S3, S4].
- A PIN must belong to a user when `USR` is supported [V S2] — so remote PIN means `PIN` + `COTA` + `USR`.

### 1.7. Events

| Event | Conformance | Fields |
|---|---|---|
| `DoorLockAlarm` | M, critical | `AlarmCode` |
| `DoorStateChange` | M(DPS) | `DoorState` |
| `LockOperation` | M | `LockOperationType`, `OperationSource`, `UserIndex`?, `FabricIndex`?, `SourceNode`?, `Credentials`? O(USR) |
| `LockOperationError` | M | + `OperationError` |
| `LockUserChange` | M(USR) | data type, operation, source, indices |

All [V-src S1]. `FabricIndex` and `SourceNode` "shall NOT be null if the operation source is 'Remote'"; `UserIndex` is set when a valid credential was used [V S2 §5.2.11.3]. With `UBOLT`, `UnlockDoor` emits `LockOperation(Unlatch)` when the latch is pulled, then `LockOperation(Unlock)`; `UnboltDoor` emits `Unlock` [V S2 §5.2.11.3].

### 1.8. Users and credentials (`USR`) — shape only

| Element | Note |
|---|---|
| `SetUser`, `GetUser`, `ClearUser` | Administer, timed (Get not timed). User: index, name, unique ID, status (`Available`/`OccupiedEnabled`/`OccupiedDisabled`), type, credential rule |
| `SetCredential`, `GetCredentialStatus`, `ClearCredential` | Administer, timed. Credential types: `ProgrammingPIN`, `PIN`, `RFID`, `Fingerprint`, `FingerVein`, `Face`, Aliro keys |
| User types | `UnrestrictedUser`, `YearDayScheduleUser`, `WeekDayScheduleUser`, `ProgrammingUser`, `NonAccessUser`, `ForcedUser`, `DisposableUser`, `ExpiringUser`, `ScheduleRestrictedUser`, `RemoteOnlyUser` (`USR & COTA & PIN`: "useful for regular delivery services or voice assistant unlocking") |
| Schedules | week-day, year-day, holiday — Administer, not timed |
| Read-back | `GetCredentialStatus` says whether a credential exists — the PIN itself is not returned (only Aliro data) [V-src S1] |

All [V-src S1] unless marked; quote [V S2].

### 1.9. Auto-relock and momentary locks

- No spec text, matter.js or CHIP example models a lock that relocks right after a pulse (an electric strike) [GAP].
- CHIP lock-app with `UBOLT`: `UnlockDoor` → `Unlatched` → `Unlocked` → `Locked` after `AutoRelockTime`; auto-relock is scheduled after `Unlock`, never after `Unlatch` [V-src S4].
- Spec-consistent mappings for a strike [I]: (a) no `UBOLT` — `Unlocked` during the pulse, `Locked` at its end with `LockOperation(Lock, Auto)`, `AutoRelockTime` = pulse length; (b) `UBOLT` — `Unlatched` during the pulse; `UnboltDoor` has no meaning for a strike.

### 1.10. matter.js (0.18.0, 2026-10-20)

| Aspect | Behaviour |
|---|---|
| Features | `DoorLockServer` selects none; pick with `.with("User", "PinCredential", "CredentialOverTheAirAccess", "Unbolting", "DoorPositionSensor")` |
| Hardware hook | override `handleLockOperation({actuation: "lock" \| "unlock" \| "unbolt", source, userIndex})`; called after authorization, never concurrently; throw `LockOperationFailedError(OperationError.X)` to fail |
| `unlockDoor` | sets `Unlocked`, emits `LockOperation(Unlock)`, schedules relock. With `UBOLT` it does **not** pass `Unlatched` nor emit `Unlatch`, which §1.7 requires — left to the implementer [I] |
| Auto-relock | timer → `handleLockOperation({actuation: "lock", source: Auto})`; on failure `LockOperationError`, no retry |
| Authorization | needs a fabric; enforces operating modes, wrong-code lockout, PIN lookup, user status, schedules, user types. Does **not** check `ActuatorEnabled` |
| DPS | a `doorState` change emits `DoorStateChange` and counts open/closed events |
| Credentials | stored non-volatile, AES-128-CCM; override `cipher` or `auth` (`LockAuth.Store`) for external storage. Reversible on purpose: the legacy commands "must return plaintext credential data" |
| PIN check | private `#identifyPin`: for each stored PIN credential, `auth.decrypt(data)` equals the given PIN → its user; a PIN no user holds counts as wrong. Synchronous. So the store must hold every PIN in a recoverable form; a hash-only store or an async call to an identity provider does not fit this path. The other path: override `unlockDoor`/`lockDoor` (async) and redo authorization and lockout [I] |
| `setUser`, `setCredential`, `clearUser`, `clearCredential` | ordinary command handlers; `setCredential` answers `Duplicate` for a PIN already stored. An override can refuse them [I] |
| Examples | none for a bridged lock [GAP]; tests override `handleLockOperation` |

All [V-src S3] unless marked.

## 2. Controllers

| Controller | Door Lock | Unlatch / `UBOLT` | PIN for remote unlock | Bridged |
|---|---|---|---|---|
| Apple Home | yes [V S5]. After commissioning it "may show a one-time access code prompt"; that code is then used for the bridge's PIN check, and Apple "has the best PIN code support" [V S8]. Whether Apple sends that stored code itself or asks the person each time: [GAP] | no unlatch control: "Apple Home has no Unlatch button for Matter locks, it only knows lock and unlock" (HAMH maintainer) [V S8]; Nuki: "Apple Home has no option to unlatch" [V S9]. Command sent to a `UBOLT` lock: [GAP] | may prompt once "Set Up an Access Code" [V S8]. Face ID / confirmation for unlock and unlocking automations: [GAP] | users report bridged locks working [V S8]; no Apple rule against it found [GAP] |
| Google Home | yes [V S6] | has "open door when unlocking"; sends both `unboltDoor` and `unlockDoor` (HAMH logs) [V S8] | "remote unlock is disabled on all surfaces for Matter door locks in the Google ecosystem that don't mandate a PIN code … Likewise, voice unlock for door locks is disabled." [V S6] → needs `PIN` + `COTA` + `USR`, `RequirePINforRemoteOperation = true` [I] | "All devices behind a Matter bridge appear as normal" [V S6] |
| Home Assistant | yes | with `UBOLT`: HA `unlock` → `UnboltDoor`, HA `open` → `UnlockDoor`; without: `unlock` → `UnlockDoor`. `Unlatched` → `is_open` [V-src S7] | `code_format` only if `RequirePINforRemoteOperation`; timed request 10 s [V-src S7] | as any node |
| Amazon Alexa | yes [V S10] | unsupported (HAMH table) [V S8] | partial (HAMH table) [V S8] | [GAP] |
| Nuki (vendor) | — | Matter "Open door" vs "Unlock" works only with Home Assistant; other hubs perform the unlock action set in the Nuki app [V S9] | — | — |

Home Assistant's own lock entity: states `locked`, `locking`, `unlocked`, `unlocking`, `open`, `opening`, `jammed`; feature `OPEN` adds `open()`. "A released latch while the lock is still secured is not the open state." [V S11]

## 3. Relay-driven locks

### 3.1. Kinds

| Kind | Power applied | Power lost | Typical drive | Feedback |
|---|---|---|---|---|
| Electric strike, fail-secure (DE *Arbeitsstrom*) | releases the latch keeper; door can be pushed open [V S12] | stays locked; door opens from inside mechanically [V S12] | pulse, a few seconds [I] | optional monitor contact (effeff *Rückmeldekontakt* RR, 24 V / 1 A microswitch; what it reports: [GAP]) [V S14] |
| Electric strike, fail-safe (*Ruhestrom*) | locked | released — "the door opens merely by being pushed or pulled" [V S12]; for life safety [V S13] | continuous, inverted | as above; some models also an armature contact [V S14] |
| Magnetic lock | locked | released | continuous, inverted | [GAP] — not researched |
| Motor lock with opener input (GU Automatic A-opener) | a potential-free pulse retracts the latch bolts for ≈ 2 s, then they extend; a held contact keeps them retracted "until the contact is open again"; relocks automatically once the door is shut [V S16] | — | pulse (latch release) or held (stays open) | audible only, no electrical status [V S16] |
| Motor multi-point lock (Siegenia GENIUS 2.2) | "As soon as the multi-point lock receives an opening signal, the door unlocks for 7 seconds"; relocks after 7 s if the door stays shut; pulse t = 1 s set in its app [V S17] | key release | pulse | LEDs; day mode (closes without locking) vs night mode (locks automatically) [V S17] |

- Strikes: AC drive buzzes, DC clicks [V S12]; continuous power heats a strike [V S13]; continuous-duty models are rated "100 % ED" [V S15]; dual-voltage and site-reversible fail-secure/fail-safe models exist [V S14]. A built-in suppression diode is a model option (effeff `05`) [V S14].
- Strike "release memory" (stays released until the door is opened once): [GAP] — not found in the datasheets read.

### 3.2. Unlock vs latch release on a relay

| Variant | Relay | Door afterwards | Matter fit |
|---|---|---|---|
| Latch release | pulse (strike, motor lock pulse input) | locked again when the pulse ends (strike) or when the door shuts (motor lock) [V S12, S16, S17] | `UnlockDoor` + auto-relock, or `Unlatched` (§1.9) [I] |
| Unlock | held on (motor lock held input; fail-secure strike held) or off (fail-safe, maglock) | stays unlocked until the relay changes back [V S16] [I] | `UnlockDoor`/`UnboltDoor` → `Unlocked`; `LockDoor` → `Locked` [I] |

- Without a feedback contact, the state is what the relay was told — the door itself is not known. A door contact on a DI is the `DPS` source [I].
- Fail-safe and maglock invert the relay: the safe default after a daemon crash is the opposite of a fail-secure strike's (§6 P9) [I].

### 3.3. Prior art

| System | What |
|---|---|
| Home Assistant lock entity | `lock`, `unlock`, `open` (= unlatch, feature `OPEN`) [V S11] |
| ESPHome `output` lock | "allows you to use any output component as a lock" — one output, no open/latch action documented [V S18] |
| helios2n-hass (2N, custom) | monostable switch → **button** (press = `on`); bistable switch → **lock** (`is_locked = not active`) [V-src S27] |
| Matter (Nuki, European locks) | `UBOLT` exists for exactly this split (§1.5) [V S2] |

## 4. 2N Access Unit 2.0 / IP Verso 2.0

### 4.1. Devices, firmware, licences

| Item | Fact |
|---|---|
| Firmware | current 3.3.1 on both (2026-08-31); 2.50 LTS also documented [V S25, S19] |
| Access Unit 2.0 I/O | one relay (NO/NC, 30 V DC / 1 A), one active output (8–12 V DC, ≤ 600 mA), two inputs, built-in tamper; PoE; BLE, NFC [V S26]. Port names `relay1`, `output1`, `input1`, `input2`, `tamper` [V S22] |
| Verso main unit | relay (NO, 30 V / 1 A), active output; `relay1`, `output1`, `input1`; modules addressed `module5.relay1` [V S22]. Tamper: separate accessory [V S32] |
| Licence | HTTP API included on Verso 2.0; Automation and HTTP commands on switches need Gold; Access Unit 2.0: "the entire feature set is enabled by default" [V S20 §3, S23]. Firmware < 2.35 needed a licence for the API [V S23] |
| Other protocols | SIP, ONVIF (Verso), Wiegand and OSDP modules (2N as a reader) [V S26, S20 §3]. MQTT, Matter, BACnet: no mention found [GAP] |

### 4.2. API access

| Topic | Fact |
|---|---|
| Base | `http(s)://<ip>/api/...`, GET/POST; `dir/*` PUT/POST with JSON [V S19 §5] |
| Transport, auth | per service: HTTP or HTTPS ("Any requests sent via the unsecured HTTP are rejected"); None / Basic / Digest — Digest "the default and most secure"; 2N recommends HTTPS + Digest [V S19 §3] |
| Accounts | up to five API accounts, privileges per service, Monitoring vs Control [V S19 §4] |
| Privileges | Switch Monitoring / Control; I/O Monitoring; Access Control Monitoring / Control; **System Control for all `dir/*`**; Access to Automation [V S19 §5] |
| Envelope | `{"success":true,"result":{…}}` or `{"success":false,"error":{"code":N,"param":…,"description":…}}`; HTTP 401 for auth [V S19 §5] |
| Errors | 9 authorisation required, 10 insufficient privileges, 12 invalid value, 14 processing failed, 18 rejected by device, 19 firmware too old … [V S19 §5] |
| Limits | rate and session limits not documented; stateless [GAP]. `LoginBlocked` is raised after repeated wrong web logins; whether API logins count: [GAP] [V S19 §5.10.4] |

### 4.3. Switches — the lock

| Call | Result |
|---|---|
| `GET /api/switch/caps` | per switch: `enabled`, `mode` `monostable`/`bistable`, `switchOnDuration` (s), `type` `normal`/`security` [V S19 §5.4.1] |
| `GET /api/switch/status` | `active`, `locked` ("locked in the deactivated position"), `held`; "Locking takes priority over holding" [V S19 §5.4.2] |
| `GET /api/switch/ctrl?switch=1&action=…` | `on`, `off`, `trigger` ("activate monostable switch, toggle the state of bistable switch"), `lock` ("locked switch is deactivated and cannot be operated"), `unlock`, `hold` (+ `timeout` 1–86400 s), `release`; `message` ≤ 63 chars to the event log (API 3.3); error 14 when the state can't be reached, e.g. `on` while locked [V S19 §5.4.3] |

- Switch config: mode, Switch-On Duration (ignored when bistable), controlled output (relay, active output, extender, or none), output type Normal / Inverse / Security, up to 10 switch codes, hold by time profile [V S20 §5.5.1].
- Up to 4 switches; which output a switch drives is not readable over the API [V S19 §5.4.3] [GAP].
- 2N Security Relay: between active output and lock, switches only on a learned code; switch type must be Security [V S24].
- 2N `lock` is a lock-out of the switch, not "strike off" [V S19 §5.4.3].
- `on` on a monostable switch: auto-off after the duration — not stated [GAP].

### 4.4. Door and I/O

- Door section (FW ≥ 2.22): assigned switch, assigned door-sensor input (Inverted for NC), unauthorized door open detection ("the assigned switch was not activated"), door open too long with max time, exit button (activates the door switch) [V S20 §5.5.8, S21].
- Tamper can block all switches for 30 min, kept across a restart [V S21].
- A monostable switch turns off when its duration ends [V S20 §5.5.1]. "Switch off when the door opens": not found [GAP].
- `io/caps`, `io/status`, `io/ctrl` read and drive ports directly; driving a switch's output directly desynchronises the switch state [V S19 §5.5, S27].

### 4.5. Events

| Call | Parameters |
|---|---|
| `/api/log/subscribe` | `include` `new` / `all` / `-t` (last t s); `filter` (event list); `duration` 90 s default, ≤ 3600 — channel closes if not pulled in time; returns `id` [V S19 §5.10.2] |
| `/api/log/pull` | `id`, `timeout` s — long poll, ≤ 128 events per answer [V S19 §5.10.4] |
| `/api/log/unsubscribe`, `/api/log/caps` | close; list supported events [V S19 §5.10] |

- The device keeps the last 10 000 events; event `id` restarts at 1 after a reboot, first event `DeviceState{state: "startup"}` [V S19 §5.10.2, §5.10.4].
- "Unprivileged user events shall not be included in the channel queue" — an event the account may not see is dropped silently [V S19 §5.10.2].

| Event | Params | Privilege |
|---|---|---|
| `SwitchStateChanged` | `switch`, `state`, `originator` (`profile`, `api`, `ap`, `rex`, `idt`, `dtmf`, `auth`, `uni`, `zone`, `automation`); `ap`, `session` when from an access point | I/O Monitoring |
| `DoorStateChanged` | `state` `opened`/`closed` | none |
| `DoorOpenTooLong`, `UnauthorizedDoorOpen` | `state` `in`/`out` | none |
| `TamperSwitchActivated`, `SwitchesBlocked`, `ApLockStateChanged` | `state` (`ap`) | none |
| `UserAuthenticated` | `ap`, `session`, `name`, `uuid`, `apbBroken` | UID Monitoring |
| `UserRejected` | + `reason` (`accessBlocked`, `switchLocked`, `invalidTime`, `invalidCredential`, …) | UID Monitoring |
| `CardEntered`, `CodeEntered`, `FingerEntered`, `MobKeyEntered` | `ap`, `session`, `direction`, `uuid`, `valid` | UID / Keypad Monitoring |
| `RexActivated` | `ap`, `session` | none |
| `InputChanged`, `OutputChanged` | `port`, `state` | I/O Monitoring |

All [V S19 §5.10.4]. `ap`: 0 = entry, 1 = exit. Who opened: `UserAuthenticated.session` = the following `SwitchStateChanged.session` [I].

Push alternatives:

- Automation `SendHttpRequest` on events (switch, user authorized, card, code, input, door) to a URL, Basic or Digest — needs Gold on Verso 2.0 [V S22, S20 §3].
- `GET /api/automation/trigger?triggerId=<name>` fires an Automation `HttpTrigger` on the 2N [V S19 §5.19.1].
- Legacy WS-BaseNotification event logging: old interface, not in the current manual [V S19] [I].

### 4.6. Access points

| Call | Result |
|---|---|
| `/api/accesspoint/grantaccess?id=0&user=<uuid>` | grants access for that user "whose access settings are considered"; `{accessGranted, reason}` — `invalidAp`, `invalidCredential`, `accessBlocked`; since 2.49 it activates the configured door switch [V S19 §5.17.3, §1.1] |
| `/api/accesspoint/blocking/ctrl?id=0&action=on\|off`, `/blocking/status` | block an access point (entry 0, exit 1) [V S19 §5.17.1–2] |

`switch/ctrl` logs `originator: "api"`; `grantaccess` acts for a named user. Which events `grantaccess` writes: [GAP].

### 4.7. Users — the directory

| Call | Fact |
|---|---|
| `dir/template` | full user object with defaults and the directory `series` [V S19 §5.14.1] |
| `dir/create[?force=1]` | PUT `{users: [...]}`; existing uuid → `EDIR_UUID_ALREADY_EXISTS` unless `force`; missing uuid → random; per-entry `errors[]`, others still processed [V S19 §5.14.2] |
| `dir/update` | partial update by uuid [V S19 §5] |
| `dir/delete` | by uuid, or `{owner: "X"}` — "All entries in the directory with the specified owner are deleted." [V S19 §5.14.4] |
| `dir/get` | by uuid, chosen `fields` [V S19 §5.14.5] |
| `dir/query` | incremental: `{series, fields, iterator: {timestamp}}` returns only newer entries; series mismatch → resync; history of 10 000 uuids [V S19 §5.14.6] |

- Fields: `uuid`, `owner`, `name` (≤ 63), `email`, `treepath`, `timestamp`; `access.validFrom`/`validTo` (Unix time), `access.accessPoints[2]{enabled, profiles}`, `access.pin` ("2–15 digits"), `access.code[]` (per-switch codes), `access.card[2]` (6–32 hex), `access.mobkey`, `access.fpt`, `access.apbException`, `access.licensePlates` [V S19 §5.14.1].
- `owner`: whether an entry "is remotely managed by" My2N, Access Commander "or another remote system" [V S19 §5.14.1].
- All `dir/*` need System Control — the highest privilege [V S19 §5].
- PIN uniqueness: [GAP]. Whether `dir/get`/`query` return `access.pin` in clear, masked or not at all: [GAP] — decides whether evok-node could check a Matter PIN against 2N users.
- No API call validates a PIN without opening: `grantaccess` takes a uuid, not a credential [V S19 §5.17.3] [I].

**2N Access Commander** — central server, REST API at `https://<ac>/api/v3/`, cookie login or "Authentication: Bearer $access_key", no extra licence [V S29, S33]. API 3.1 has access rules (`/api/v3/AccessRules`, `bulk` per group × role) and logs (`/api/v3/CamLogs`); user and PIN endpoints: not checked [V S33] [GAP].

LDAP sync into Access Commander: one-way, scheduled or on demand; user name, ID, card, **PIN**, e-mail, phone, licence plate, plus custom schema mappings; group *membership* only — groups must already exist in Access Commander, names case-sensitive; option to disable users disabled in AD [V S34, S35]. 2N's FAQ example keeps the PIN in an ordinary LDAP attribute (`facsimileTelephoneNumber`) [V S35].

authentik's LDAP provider exposes users with `memberOf`, and "Any custom attributes you set are also returned as LDAP attributes" [V S36] — a path authentik → LDAP → Access Commander → 2N, PIN as a custom attribute [I]. The PIN is then readable by any LDAP account allowed to read that attribute [I]. Adding a device imports its users; with an access rule defined first, "users are deleted from the device" [V S29]. Once it manages a device, it treats the directory as its own [I]; overwrite rules: [GAP].

### 4.8. Integrations and pitfalls

- Home Assistant core has no 2N integration [V S30]. Custom `helios2n-hass` (py2n 0.4.0): polls every 10 s, platforms button / lock / switch / binary_sensor, no events; README asks for HTTP + Basic, tested on FW 2.39 [V-src S27]. `py2n` 0.6.0 has `log/subscribe`/`pull`, `dir/query`/`update`, Digest, HTTPS verify option [V-src S28].
- Some clients fail on Digest ("Unknown error" at login) [V S31]; HTTPS uses a device certificate, default self-signed: [GAP].

## 5. evok-node today

| Where | What |
|---|---|
| 12a §2.2 | `DoorLock`: `state` `locked`/`unlocked`/`jammed`/`unknown`, `lock`, `unlock` — no unlatch, no door state |
| 12c memo | `DoorLock`: "PIN and assurance level → 13a (M3.6)" |
| 16a | `DoorLock` → Door Lock `0x000A` |
| M3.6 (13a) | assurance levels, "PIN for a lock"; users, roles, devices; local DB driver |
| research/02 §4.8 | master watchdog: on expiry the section reboots into its saved default configuration |
| research/matter/07 §5.2 | open needs more than close; Door Lock's `RequirePINforRemoteOperation` noted for 13a |

## 6. Proposals for 12c (not binding)

- **P1 — fields, two states.** `state` `locked`/`unlocked`/`jammed`/`unknown` (as 12a today); methods `lock`, `unlock`; `door` reading `open`/`closed`/`unknown` from the door contact. No `unlatched`, no `unlatch`: Tomas's locks don't separate unbolt from unlatch (Input). A lock that does can add `unlatch` later as an optional field — 12a's "no stub fields" rule.
- **P2 — Matter projection.** No `UBOLT` — "Locks without unbolting support … perform the same operation for both commands" (§1.5). `UnlockDoor` → `unlock`; `LockDoor` → `lock`; `DPS` from `door`, `DoorStateChange` on each change. `AutoRelockTime` = the release time. Fits Apple (lock / unlock only, §2); avoids the matter.js `Unlatched` gap (§1.10).
- **P2a — `locked` means secured.** With a lock that locks on door close, the release time can end while the door is still open. So `state` = `unlocked` from the pulse until the release time has passed **and** `door` = `closed`; then `locked`, with `LockOperation(Lock, Auto)`. Opened with `state` = `locked` (no pulse, no 2N grant) → `DoorForcedOpen` (Matter `DoorState`, `DoorLockAlarm`) [I].
- **P3 — template `lock-from-relay`.** Roles: `release` (`unipi.ro`/`unipi.do`), `door` (DI, required). Settings: `pulseMs` (relay on), `releaseMs` (the lock's own release time), `inverted` (fail-safe strike, maglock). `lock` while `unlocked`: switches the relay off; the lock's own release cycle cannot be cut short, so the reply is success and `state` follows P2a [I]. `hold` mode (permanently unlocked) not needed now.
- **P4 — 2N as a source.** A network driver for 2N (its own endpoints: switches, door, tamper, auth events over `log/pull`), and a home template mapping one switch to a `DoorLock` — keeps the one-owner rule (12a, 01 §2). `unlock` → `switch/ctrl action=trigger` (or `grantaccess` for a named user); lock → `off`; 2N `lock`/`unlock` (lock-out) → a separate setting or `OperatingMode NoRemoteLockUnlock` [I]; `SwitchesBlocked`/tamper → `DoorLockAlarm` candidates.
- **P5 — event link.** Long-poll `log/pull` with `timeout` ≈ 30 s; on failure re-subscribe with `include=-<s since last seen>`, dedupe on (`utcTime`, `id`, `event`), then re-read `switch/status` (§4.5). `door` from the 2N's `DoorStateChanged` when the contact is on the 2N input, else from a `unipi.di` [I]. One API account, Digest over HTTPS, minimal privileges; `System Control` only once users are synced.
- **P6 — PIN and Google.** *(See P11–P15 for Tomas's identity input.)* Without `PIN` + `COTA` + `USR`, Google Home will not unlock remotely; Apple and HA will (§2). Start without PIN, or with PINs checked by evok-node (matter.js stores them, §1.10) — a 2N cannot check a PIN for us (§4.7). Decision for 13a.
- **P7 — user cooperation with 2N (13a).** (a) evok-node owns users and pushes them with `dir/create`, `owner: "evok-node"`, cleanup by `dir/delete {owner}`; (b) 2N / Access Commander owns them, evok-node mirrors with `dir/query` and maps 2N users to Matter `UserIndex` for `LockOperation`; (c) disjoint — 2N authenticates its own users, evok-node only reports `UserAuthenticated` names. (a) conflicts with Access Commander (§4.7).
- **P8 — who opened.** `LockOperation.OperationSource`: 2N keypad → `Keypad`, card → `RFID`, finger → `Biometric`, exit button → `Button`, evok-node rule → `Auto`, Matter → `Remote`. `UserIndex` only with `USR` [I].
- **P9 — failure state.** Fail-secure on `unipi.ro`: watchdog default off = locked. Fail-safe / maglock (inverted): watchdog default off = **open**; the section's saved default must be on, or the template refuses an inverted role without it [I] (research/02 §4.8).
- **P10 — open vs close** as in 07 §5.2: `unlock` needs the higher assurance level, `lock` the lower one; rules that unlock need explicit consent (13a).
- **P11 — Matter user DB is a mirror.** Per bridge (per flat), evok-node fills the Door Lock user DB from the identity provider: one Matter user per person whose roles grant this lock, one PIN credential each; `SetUser`, `SetCredential`, `ClearUser`, `ClearCredential` from any fabric answer `Failure` (or `UnsupportedAccess` [GAP]). How Apple's access-code prompt (§2) reacts to a refused `SetCredential`: [GAP].
- **P12 — PIN check path.** Either (a) a `LockAuth.Store` override holding the flat's PINs from the identity provider in recoverable form (§1.10); or (b) override `unlockDoor`/`lockDoor`, ask 13a to verify the PIN (async, hash-only possible), and redo lockout and events. (b) keeps PINs out of evok-node's Matter storage [I].
- **P13 — the PIN must identify one person.** PINs unique per lock (Matter `Duplicate`, §1.10); the identity provider enforces uniqueness over everyone who can reach the same lock, e.g. a shared entrance in several flats' bridges [I]. A PIN that identifies a user without a role for this lock → `Failure` + `LockOperationError(InvalidCredential)`.
- **P14 — Apple may not identify a person.** If Apple keeps the one-time access code and sends it itself (§2, GAP), every Apple user of that home unlocks as the same PIN owner. Requirement "user enters PIN to identify themselves" then holds for Google and HA, not for Apple [I]. To verify on a device.
- **P15 — bridge per flat.** "A flat's devices in one bridge" means one Matter node per flat; 16a says "One bridge, always" — to resolve in 16a. A shared lock (entrance) is then in several bridges, each with its own user DB and its own wrong-code lockout (`WrongCodeEntryLimit` is per lock, not per user) [I].
- **P16 — 2N users from the identity provider.** P7 (b) via LDAP: authentik LDAP provider → Access Commander LDAP sync (roles → AC groups by name, PIN as a custom attribute) → 2N. evok-node never writes the 2N directory; it maps 2N `UserAuthenticated.uuid` back to the identity-provider user for events [I]. ID mapping across the chain: [GAP].

## 7. Sources

- S1 — connectedhomeip `data_model/{1.0,1.2,1.3,1.4,1.5,1.5.1}/clusters/DoorLock.xml`, `device_types/DoorLock.xml`, `DoorLockController.xml`, `1.5/device_types/RootNodeDeviceType.xml`: https://github.com/project-chip/connectedhomeip/blob/master/data_model/1.5.1/clusters/DoorLock.xml
- S2 — matter.js spec text (Matter 1.6.1), `packages/model/src/standard/resources/door-lock-cluster.resource.ts`, v0.18.0: https://github.com/project-chip/matter.js/blob/v0.18.0/packages/model/src/standard/resources/door-lock-cluster.resource.ts
- S3 — matter.js `DoorLockServer.ts`, `AccessControlServer.ts`, `CHANGELOG.md`, v0.18.0: https://github.com/project-chip/matter.js/blob/v0.18.0/packages/node/src/behaviors/door-lock/DoorLockServer.ts
- S4 — connectedhomeip `src/app/clusters/door-lock-server/CodegenIntegration.cpp`; `examples/lock-app/lock-common/src/LockEndpoint.cpp`: https://github.com/project-chip/connectedhomeip/blob/master/examples/lock-app/lock-common/src/LockEndpoint.cpp
- S5 — connectedhomeip `docs/guides/darwin.md`: https://github.com/project-chip/connectedhomeip/blob/master/docs/guides/darwin.md
- S6 — Google Home Developers, Matter supported devices: https://developers.home.google.com/matter/supported-devices
- S7 — Home Assistant core, `components/matter/lock.py` (dev): https://github.com/home-assistant/core/blob/dev/homeassistant/components/matter/lock.py
- S8 — Home Assistant Matter Hub: issues #514, #397; lock docs: https://github.com/RiDDiX/home-assistant-matter-hub/issues/514 · https://riddix.github.io/home-assistant-matter-hub/devices/lock
- S9 — Nuki, "What lock actions does Matter support": https://help.nuki.io/hc/en-001/articles/18155255436945-What-lock-actions-does-Matter-support · forum: https://developer.nuki.io/t/smart-lock-pro-5-not-unlatching-via-apple-home-matter/39189
- S10 — Amazon Alexa, supported Matter device categories: https://developer.amazon.com/en-US/docs/alexa/smarthome/supported-matter-device-categories.html
- S11 — Home Assistant developer docs, lock entity: https://developers.home-assistant.io/docs/core/entity/lock
- S12 — Wikipedia, Electric strike: https://en.wikipedia.org/wiki/Electric_strike
- S13 — Beacon, Practical guide: electric strikes: https://beaconcdl.com/electric-strikes/
- S14 — effeff 332 door opener datasheet (eurofer): https://www.eurofer.de/eurofer-portal/media/downloads/dokumente/effeff/eurofer_effeff_332_80------f91.pdf · effeff 76 series (lockandkey): https://www.lockandkey.co.uk/product/eff-eff-76-series-penta-mortice-release-monitored/datasheet.pdf
- S15 — effeff 118E datasheet (Siblik): https://siblik.com/fileadmin/mam/medias/docus/109/Artikel_EFF118E.D11_Datenblatt.pdf
- S16 — GU Automatic with A-opener fitting: https://www.specifiedby.com/gb-locking-systems/gu-motorised-secure-multipoint-lock/automatic-with-a-opener-fitting_86740105.pdf
- S17 — Siegenia GENIUS 2.2: https://www.specifiedby.com/siegenia-group/genius-multi-point-lock-for-electromechanical-locking-and-unlocking/tdoh47eleks013en00001_e2dc9100.PDF
- S18 — ESPHome, Output lock: https://esphome.io/components/lock/output/
- S19 — 2N IP HTTP API manual 3.3 (sections as numbered there): https://wiki.2n.com/hip/hapi/latest/en · PDF: https://wiki.2n.com/download/attachments/123498082/2N_IP_HTTP_API_manual_EN_3.3.pdf
- S20 — 2N IP intercoms configuration manual, §3 model differences and licensing, §5.4.5 HTTP API, §5.5.1 switches, §5.5.8 digital inputs: https://wiki.2n.com/hip/conf/latest/en/3-rozdily-mezi-modely-a-licencovani-funkci
- S21 — 2N Access Unit configuration manual §5.3.7 digital inputs: https://wiki.2n.com/acuc/latest/en/5-konfigurace-pomoci-weboveho-rozhrani/5-3-hardware/5-3-7-digitalni-vstupy
- S22 — 2N IP Automation manual 3.3: https://wiki.2n.com/download/attachments/123496966/2N_IP_Automation_Manual_EN_3.3.pdf
- S23 — 2N licences: https://www.2n.com/en-GB/licenses/ · new licensing (2022): https://www.2n.com/en-AU/newsroom/simple-and-understandable-the-new-2n-intercom-licensing/
- S24 — 2N FAQ, Security Relay: https://wiki.2n.com/faqint/en/2n-security-relay-what-it-is-and-how-to-use-it-with-2n-ip-intercom-100572233.html
- S25 — 2N support, IP Verso 2.0 and Access Unit 2.0 firmware: https://www.2n.com/en-AU/support/intercoms/2n-ip-verso-2/ · https://www.2n.com/en-GB/support/access-control/2n-access-unit-2/
- S26 — 2N Access Unit 2.0 datasheet: https://ipphone-warehouse.com/content/pdf/2n/2N-Access-Unit-2-0-Datasheet.pdf · Verso 2.0 technical parameters: https://www.2n.com/en-AU/manuals/42715/3_3/technical-parameters/
- S27 — helios2n-hass (custom HA integration): https://github.com/SVD-NL/helios2n-hass · README fork: https://github.com/Neffez/helios2n-hass
- S28 — py2n 0.6.0: https://pypi.org/project/py2n · https://github.com/linusgke/py2n
- S29 — 2N Access Commander FAQ, user import and REST API: https://wiki.2n.com/faqac/en/import-uzivatelu-ze-zarizeni-do-access-commanderu-100571792.html · https://wiki.2n.com/faqac/en/http-rest-api-zakladni-informace-a-priklad-komunikace-s-api-2n-access-commanderu-100571739.html
- S30 — Home Assistant core `generated/integrations.json` (dev): https://github.com/home-assistant/core/blob/dev/homeassistant/generated/integrations.json
- S31 — Home Assistant community, "2n / Helios Integration": https://community.home-assistant.io/t/2n-helios-integration/823428
- S32 — provu, 2N IP Verso 2.0: https://www.provu.co.uk/2n-ip-verso-2.0.html
- S33 — 2N Access Commander, HTTP API for version 3.1: https://wiki.2n.com/acc/latest/en/http-api-pro-verzi-3-1
- S34 — 2N Access Commander 2.7 manual, §4.1.1 LDAP: https://wiki.2n.com/acc/2.7/en/4-sprava-systemu/4-1-spolecnosti/4-1-1-ldap
- S35 — 2N FAQ, "LDAP - Users synchronisation from a remote directory": https://www.2n.com/nl-NL/faqs/ldap-users-synchronisation-from-a-remote-directory-kA0Rn000000u5D8KAI
- S36 — authentik docs, LDAP provider: https://docs.goauthentik.io/add-secure-apps/providers/ldap/
