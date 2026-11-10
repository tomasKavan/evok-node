# 03 — Auth levels and step-up

**Research, not design.** Assurance levels (NIST, eIDAS), OIDC `acr`/`amr`/step-up, what WebAuthn and phone biometry tell a server, session elevation vs per-operation proof, consumer precedents for locks and garage doors, and the rules for PINs and biometry. Feeds 13a (M3.6).

Already in the repo, not repeated here: Matter `RequirePINforRemoteOperation`, `WrongCodeEntryLimit`, Google Home refusing remote unlock of a Matter lock without a PIN, the Apple Home one-time access code prompt (research/matter/08). Tomas's decision, taken as input: in the Home UI an authenticated user only confirms, a person who is not authenticated gives a PIN, and unlock needs biometry or a PIN.

## 1. Assurance-level standards

### 1.1. NIST SP 800-63B-4

The current revision is **final**. It was published on **31 July 2025** and replaces 800-63B (2017/2020). No errata are listed [V S1].

| | AAL1 | AAL2 | AAL3 |
|---|---|---|---|
| Authenticators | any single factor [V S2] | one multi-factor authenticator, or two single-factor ones (one physical + password or biometric) [V S2] | multi-factor cryptographic, or single-factor cryptographic + password/biometric [V S2] |
| Phishing resistance | no | the verifier SHALL **offer** a phishing-resistant option [V S2] | required [V S2] |
| Key | exportable OK | exportable OK; synced passkeys not forbidden (only AAL3 forbids them) [V S2] | non-exportable, hardware-isolated; synced passkeys SHALL NOT be used [V S2] |
| Reauth: overall | SHOULD ≤ 30 days [V S2] | SHOULD ≤ **24 h** [V S2] | SHALL ≤ **12 h** [V S2] |
| Reauth: inactivity | MAY [V S2] | SHOULD ≤ **1 h**; after an inactivity timeout, a password **or** a biometric + the session secret is enough [V S2] | SHOULD ≤ **15 min**; full reauth [V S2] |
| Authentication intent | — | SHOULD [V S2] | required for every auth and reauth [V S2] |

*Intent* means the claimant must respond explicitly to each authentication request. It makes silent use of an authenticator harder [V S3 §3.2.8].

**Memorized secrets vs activation secrets.** NIST treats these as two separate things:

| | Password (memorized secret, checked by the **verifier**) §3.1.1 | Activation secret (unlocks a key **on the device**) §3.2.10 |
|---|---|---|
| Min length | 15 if it is the only factor; 8 if part of MFA [V S3] | **4**, 6 recommended; may be all digits (a "PIN") [V S3] |
| Composition / expiry | no composition rules; no periodic change; blocklist check [V S3] | block common values like `123456` [V S3] |
| Failed attempts | ≤ **100** consecutive, then disable the authenticator [V S3 §3.2.2] | ≤ **10** consecutive, then disable; another authenticator is needed [V S3] |
| Where checked | server; salted hash (salt ≥ 32 bit) + SHOULD keyed hash with a separately stored key (HSM) [V S3] | AAL3: secure element / TPM / TEE; AAL2 without hardware: the secret derives the key that decrypts the authentication key [V S3] |

**Biometrics** [V S3 §3.2.3]:
- SHALL only be used as part of MFA **with a physical authenticator**. A biometric is never an authenticator by itself [V S2, S3].
- A non-biometric alternative SHALL always be offered.
- FMR 1 in 10,000 or better. After 5 failures (10 with PAD), wait ≥ 30 s. After 50 failures (100 with PAD), disable biometrics.
- Voice comparison SHALL NOT be used.

### 1.2. Other level schemes

- **eIDAS LoA** (Impl. Reg. 2015/1502): *low* = at least one factor; *substantial* = two factors from different categories + dynamic authentication; *high* = substantial + protection against duplication, tampering and attackers with high attack potential [V S4].
- **ISO/IEC 29115:2013**: four entity-authentication assurance levels, LoA1–LoA4. In OIDC, `acr: "0"` means "below ISO 29115 level 1" [V S5, S6].

## 2. OIDC / OAuth vocabulary

### 2.1. Claims and request parameters

| Name | Where | Meaning |
|---|---|---|
| `auth_time` | ID token | when the user actively authenticated. REQUIRED if `max_age` was requested [V S6 §2] |
| `acr` | ID token, JWT access token, introspection | which authentication context class (the policy) was met [V S6, S11 §6] |
| `amr` | ID token | array of the methods used [V S6] |
| `acr_values` | authorization request | the classes wanted, in order of preference. `acr` is requested as a *voluntary* claim [V S6 §3.1.2.1] |
| `max_age` | authorization request | if more time than this has passed since `auth_time`, the OP MUST actively reauthenticate. `max_age=0` ≡ `prompt=login` [V S6] |
| `prompt=login` | authorization request | reauthenticate even if a session exists; if the OP cannot, it returns `login_required` [V S6] |
| `claims` with essential `acr` | authorization request | `{"id_token":{"acr":{"essential":true,"values":["evok:l2"]}}}`: the OP MUST return one of these values; if it cannot, it MUST treat the result as a failed authentication [V S7] |

The RP SHOULD check that the returned `acr` is appropriate [V S6 §3.1.3.7]. RFC 8176 calls relying on `amr` "more brittle" than relying on `acr`, because which methods count as good changes over time [V S8 §3].

### 2.2. `amr` values (RFC 8176 + IANA registry, last updated 2024-10-04)

| Value | Meaning [V S8 §2, S9] |
|---|---|
| `pwd` | password |
| `pin` | PIN or pattern **"that a user enters to unlock a key on the device"**; should deter repeated guessing |
| `otp` / `sms` / `tel` | one-time password / confirmation by SMS / confirmation by phone call |
| `hwk` / `swk` | proof of possession of a hardware-secured / software-secured key |
| `pop` | proof of possession of a key, hardware or software not stated (OpenID EAP ACR Values 1.0) [V S9, S10] |
| `sc` | smart card |
| `user` | user presence test ("UP" in WebAuthn) |
| `mfa` / `mca` | multiple factors / multiple channels |
| `face` / `fpt` / `iris` / `retina` / `vbm` | biometric: face / fingerprint / iris / retina / voiceprint |
| `kba` / `rba` / `geo` / `wia` | knowledge-based / risk-based / geolocation / Windows integrated |

OpenID **EAP ACR Values 1.0** was approved as final in June 2025. It defines `acr` values `phr` (phishing-resistant) and `phrh` (phishing-resistant, hardware-protected) [V S10].

Note: RFC 8176 `pin` is an **activation secret** (§1.1), not a PIN that a server checks [V S8]. RFC 8176 has no value for "a PIN checked by the server" [I].

### 2.3. RFC 9470 — Step-up Authentication Challenge (Sept 2023, Standards Track)

```
HTTP/1.1 401 Unauthorized
WWW-Authenticate: Bearer error="insufficient_user_authentication",
  error_description="A different authentication level is required",
  acr_values="myACR"
```
The parameters are `acr_values` (space-separated, in order of preference) and `max_age` (seconds allowed since the last active authentication). Either one or both may be sent. Figure 3 uses `max_age="5"` [V S11 §3].

Flow [V S11 §2, §4–6]:
1. The client calls the resource server with an access token.
2. The token is too weak or too old, so the RS returns the challenge above.
3. The client sends the user to the AS with the same `acr_values` / `max_age`.
4. The AS authenticates the user and issues a new token that carries `acr` + `auth_time`.
5. The client repeats the call.

If the AS cannot meet the `acr`, it SHOULD fail with `unmet_authentication_requirements`. This stops the client from looping [V S11 §5]. The RFC says that "step up" and "levels" are metaphors: there is no interoperable hierarchy of methods [V S11]. RFC 9470 is HTTP-only. Nothing equivalent exists for WebSocket messages [I].

### 2.4. Example access-token payload (evok values invented)

```json
{ "iss": "https://idp.site.lan/application/o/evok/", "sub": "u-7f3a", "aud": "node-basement",
  "iat": 1793372400, "exp": 1793373300, "auth_time": 1793372390,
  "acr": "evok:l2", "amr": ["pop", "mfa"] }
```

### 2.5. authentik today

authentik **does** honour `max_age` and `prompt=login`: both re-run the authentication flow [V-src S12 `views/authorize.py`]. It advertises **one** `acr`, `goauthentik.io/providers/oauth2/default`, and always emits that value [V-src S12 `common/oauth/constants.py`, `views/provider.py`]. It sets `amr` from the login event: `pwd` for a password, `user` for passwordless WebAuthn, `sc` for a certificate, `mfa` when MFA devices were used [V-src S12 `id_token.py`]. Therefore `acr_values` cannot select a level in authentik. The replica would have to derive the level from `amr` + `auth_time` [I]. Details: (01).

## 3. WebAuthn / passkeys — what the server learns

WebAuthn Level 3 has been a **W3C Recommendation since 25 Aug 2026** [V S13, S14].

| | UP (flags bit 0) | UV (flags bit 2) |
|---|---|---|
| Means | a simple gesture (touch). It "does not constitute user verification" [V S13 §4] | the authenticator **locally** authorizes the operation, by PIN, password or biometric [V-src S13 §4] |
| Server learns | the flag inside the signed authenticator data | the flag only. Biometric data "is not revealed"; recognition is done locally and reported by setting UV [V-src S13 "Authenticator-local Biometric Recognition"] |

- Flags bit 3 = BE (backup eligible: the credential can be synced) and bit 4 = BS (backed up now) [V-src S13]. These tell a synced passkey from a device-bound key (AAL3 rejects synced keys, §1.1).
- `userVerification: "required"` means an authenticator that cannot do UV is skipped, and the RP MUST check that UV = 1. The default is `"preferred"`, which may return UV = 0 [V S13, S15].
- **Can a server require "biometric"? No.** The RP is meant to accept any UV method ("PIN, biometrics and/or future methods") [V-src S13]. The `uvm` extension, which reported the method, is **"no longer included"** in Level 3: no browser implemented it [V-src S13 changes; V S16]. Attestation (the authenticator model via AAGUID) can at most hint at which UV methods a model supports, not which one was used this time [I].
- **Native phone biometry is the same.** The app's key is released by the OS after biometry or the device passcode, and the server sees only a valid signature. Whether the key was created biometric-only is visible to the server only through key attestation, if the platform offers it [GAP → 06].

## 4. Per-session level vs per-operation proof

### 4.1. Precedents

| Kind | Example | Rule |
|---|---|---|
| Session elevation | GitHub sudo mode | password / passkey / security key / TOTP → **2 h** window; **each sensitive action resets the timer** [V S19] |
| Session elevation | NIST reauth | 12 h–30 days overall; 15 min–1 h inactivity (§1.1) [V S2] |
| Freshness | OIDC / RFC 9470 `max_age` | "authenticated within N seconds" [V S6, S11] |
| Scoped short token | Loxone | a token carries permission bits; `USER_EDIT` is "very short lived" [V-src S27] |
| Per-operation | Google smart home | the challenge is repeated for each EXECUTE (§5) [V S21] |
| Transaction-bound | PSD2 SCA dynamic linking | the payer sees the amount + payee; the code is **specific to amount and payee**; any change invalidates it [V S20 Art. 5]. At most 5 failed attempts, 5 min inactivity [V S20 Art. 4] |
| Transaction-bound | WebAuthn | lists "authorize a single transaction" as a use case; the server's challenge carries the binding [V-src S13 use cases; binding via challenge: I] |
| Explicitly *not* per-request | Apple HAP Additional Authorization Data | a manufacturer-specific blob per controller; "must not be unique per write request"; may change monthly [V-src S25] |

Apple Pay is per-payment Face ID / Touch ID / passcode [GAP: Apple Platform Security guide not fetched]. AWS and Google console re-auth: [GAP] (search budget exhausted).

### 4.2. For evok-node targets [I]

| | Session elevation (level + window) | Per-operation proof bound to `driverId:tail` + method + nonce |
|---|---|---|
| Phone stolen while unlocked | the window is open to the thief | each unlock needs a fresh UV or PIN |
| Proof reused by another call or tab | possible inside the window | impossible: the proof names the operation |
| Automations / scenes | could ride on an elevated session | cannot produce a proof. Good for `unlock`, a problem if a scene should open the gate |
| Offline (IdP down) | the node must track the window itself | the node checks a signature or a PIN hash locally, with no IdP round trip |
| Audit | "elevated at t" | "X proved *unlock front door* at t" |
| Daily garage-door use | one prompt per window | a prompt every time. Google accepts this (`pinNeeded` for GARAGE) [V S21] |

What the user sees: PSD2 requires the payer to *see* what they approve [V S20]. A platform biometric prompt shows the app's text, not an operation the server has signed. Binding prevents reuse, but it does not prove that the user saw "front door" [I].

## 5. Consumer precedents for secure devices

| Product | Operation | Proof asked | Who verifies | Remembered |
|---|---|---|---|---|
| Google smart home (cloud-to-cloud) | `LockUnlock` unlock; `OpenClose` on DOOR/GARAGE/GATE/WINDOW; `ArmDisarm` disarm; camera `OnOff`; router reboot | `pinNeeded` is **required** for these. `ackNeeded` (yes/no) "not recommended" for security devices [V S21] | **partner cloud**: the PIN arrives in the retried EXECUTE as `"challenge":{"pin":"333444"}` [V S21] | per request in all examples; caching not stated [V S21 / GAP] |
| Alexa | `Unlock` (LockController) | unlocking is **off by default**. The user enables it and creates a code in the Alexa app [V S22, S24] | Alexa: the `Unlock` directive "doesn't define any payload", so the skill never sees the code [V S22 → I] | [GAP] |
| Alexa | open garage door (ModeController) | "Alexa asks before opening" [V S23] | Alexa [I] | [GAP] |
| Apple HAP (protocol) | Lock Target State, Target Door State | **timed write** ("security class characteristics"). Optional Additional Authorization Data [V-src S25] | the accessory checks the AAD [V-src S25] | AAD per controller, not per request [V-src S25] |
| Apple Home (iOS UI) | unlocking or opening secure accessories; Siri, Watch, CarPlay | needs an unlocked device / authentication [GAP: support.apple.com not reachable]; one-time access code prompt (research/matter/08) | the device OS [I] | [GAP] |
| Home Assistant | `lock.lock/unlock/open`; alarm arm/disarm | `code` must match the entity's `code_format` regex; the user may store a **default code** in entity options; alarm `code_arm_required` (default true), `CodeFormat` text/number [V-src S26] | core checks **only the format**; the integration/device checks the value. The `manual` alarm compares in plain text (`code == alarm_code`), fires `manual_alarm_bad_code_attempt` and has no lockout [V-src S26] | with a default code: for ever; otherwise every call [V-src S26] |
| Loxone | secured blocks (alarm, access) | the user's **visualisation password**. The client fetches a one-time key + salt via `jdev/sys/getvisusalt/{user}`, then sends `jdev/sps/ios/{HMAC(key, SHA(pw:salt))}/{uuid}/{value}` [V-src S28] | the Miniserver [I]. The HMAC does not cover uuid or value, so it resists replay but is not bound to the transaction [V-src S28 → I] | [GAP: app caching; official doc not fetched] |
| SmartThings, Nuki | — | [GAP: not verified, search budget exhausted] | | |

Pattern: every product with a remote unlock asks for a **per-operation** PIN or code, checked by the party that owns the device (partner cloud, lock, Miniserver). The assistant platform does not check it, except Alexa [V S21, S22 → I].

## 6. PIN — two different uses [I unless tagged]

| | (a) PIN **identifies** a person | (b) PIN **confirms** a known user |
|---|---|---|
| evok-node cases | shared keypad, Matter remote PIN, 2N codes (from the IdP), PIN-only local login when the IdP is down | second factor or `proof` inside a session (Home UI unlock) |
| Uniqueness | must be unique among **everyone who can reach the device**. Rejecting a chosen PIN as "taken" tells the user someone else's credential → prefer system-assigned PINs | none needed |
| Guessing | each try matches *any* user: p = N / 10^d. 20 users, 4 digits: 1/500 per try; 6 digits: 1/50,000 | p = 1 / 10^d for one account |
| Lockout | the account is unknown before a match, so throttle **per source/device**. A global lockout locks everyone out (DoS) | per account: e.g. PSD2 ≤ 5 [V S20], activation secret ≤ 10 [V S3], NIST password ≤ 100 [V S3] |
| Storage | needs a lookup by PIN. A per-user salt + slow KDF costs N × KDF per try (50 users × 50 ms ≈ 2.5 s on an A53). Option: a keyed hash (HMAC with a secret key) as the index, constant time | one salted slow hash per user (NIST §3.1.1.2 [V S3]) |
| What really protects a stolen DB | 10^4–10^6 values: brute force takes minutes to hours even with a slow KDF. Only a **secret key kept apart** from the DB helps (0600 file; TPM where present) — NIST SHOULD [V S3] | the same weakness for short PINs; per-account lockout protects online only |
| NIST class | a memorized secret used alone: below the 15-char single-factor rule [V S3 → I] | server-checked = a password in MFA, min 8 chars [V S3]. A device-checked PIN = activation secret, min 4 [V S3] |

Consequence: a 2N keypad code is case (a). If the same code also confirms in the Home UI (case b), the stronger rules of case (a) apply to it.

## 7. Biometry as a level

- At the server, "biometry" = the device released a key after local UV, and that key signed the server's challenge. The server cannot tell a fingerprint from the device passcode (§3) [V-src S13].
- So biometry is **only as strong as the device enrolment**: anyone enrolled on the phone passes, for example a partner's face [I].
- iOS keychain access control [V S17]:
  - `biometryCurrentSet`: the item is **invalidated when fingers are added or removed or Face ID is re-enrolled**.
  - `biometryAny`: survives enrolment changes.
  - `userPresence`: biometry **or** passcode, so the device passcode is the fallback.
  - `devicePasscode`: passcode only.
- Android [V S18]:
  - `BIOMETRIC_STRONG` = Class 3, `BIOMETRIC_WEAK` = Class 2, `DEVICE_CREDENTIAL` = PIN/pattern/password.
  - A per-use key: `setUserAuthenticationParameters(0, AUTH_BIOMETRIC_STRONG)` (biometric only). Adding `AUTH_DEVICE_CREDENTIAL` allows the fallback.
  - `setInvalidatedByBiometricEnrollment` defaults to true.
  - A time-bound key (duration > 0) cannot use `CryptoObject` and must allow the device-credential fallback.
- NIST always requires a non-biometric alternative [V S3]. In practice that is the device passcode, so "biometry or PIN" is what the platforms deliver anyway [I].
- Which flags the app used is invisible to the server without key attestation [GAP → 06].

## 8. Proposals for 13a (not binding)

- **P1 — Few levels, named by meaning.** `l1` = password or a refreshed session (≈ AAL1). `l2` = a device-bound key with UV, or password + second factor (≈ AAL2). Keep freshness apart, as `auth_time` + `max_age`, not as more levels.
- **P2 — Levels as `acr`, methods as `amr`.** Resources require an `acr` (+ `max_age`), never a specific `amr` (RFC 8176 §3). With authentik, the replica derives `acr` from `amr` + its own proofs (§2.5).
- **P3 — `proof` = per-operation proof.** It is bound to `{address, method, argsHash, nonce, exp}`. Kinds: `ack`, `uv` (a key assertion over the challenge), `pin`. It is checked by the node, so it works when the IdP is down.
- **P4 — Step-up over WS, modelled on Google SUV + RFC 9470.** The error carries `proofNeeded {kinds, nonce, exp}` or `insufficientAuth {acr_values, max_age}`. The client retries the same message with `proof`. Further errors: `proofFailed`, `tooManyAttempts`. Use RFC 9470 names unchanged on the HTTP auth api.
- **P5 — Reconcile "authenticated user only confirms".** Allow `ack` only when the session is `l2` and `auth_time` is within N minutes; otherwise ask for `uv`/`pin`. Note that Google forbids ack-only for unlock (§5).
- **P6 — Two PIN types in the model.** An *identifying PIN* (site-unique, keyed-hash index, per-source throttle) and a *confirming PIN* (per user, salted KDF, per-account lockout, e.g. 5 tries then a block). Decide which type 2N codes are.
- **P7 — Offline login levels.** A one-time local session by PIN = `l1`. By a device key + UV = `l2`. Unlock while offline goes through P3 proofs only.
- **P8 — App key policy.** iOS `biometryCurrentSet` + `privateKeyUsage`. Android `AUTH_BIOMETRIC_STRONG` with invalidation on enrolment. Decide whether the device-passcode fallback counts as "biometry" (→ 06).

## 9. Sources

- S1 — NIST SP 800-63B-4 (final, 2025-07-31), CSRC: https://csrc.nist.gov/pubs/sp/800/63/B/4/final
- S2 — NIST SP 800-63B-4 §2 Authentication Assurance Levels: https://pages.nist.gov/800-63-4/sp800-63b/aal
- S3 — NIST SP 800-63B-4 §3 Authenticator and Verifier Requirements: https://pages.nist.gov/800-63-4/sp800-63b/authenticators
- S4 — Commission Implementing Regulation (EU) 2015/1502, Annex 2.2.1 and 2.3.1: https://lawplayer.com/eu/act/32015R1502 (EUR-Lex: https://eur-lex.europa.eu/eli/reg_impl/2015/1502/oj/eng)
- S5 — ISO/IEC 29115:2013 abstract (IEC webstore): https://webstore.iec.ch/publication/11351
- S6 — OpenID Connect Core 1.0 (errata set 2): https://openid.net/specs/openid-connect-core-1_0.html
- S7 — OIDC Core §5.5.1.1 text as quoted in OpenID issue 1143 and Keycloak issue 8724: https://bitbucket.org/openid/connect/issues/1143/clarify-text-value-vs-values-in-5511 · https://github.com/keycloak/keycloak/issues/8724
- S8 — RFC 8176 Authentication Method Reference Values: https://www.rfc-editor.org/rfc/rfc8176
- S9 — IANA Authentication Method Reference Values registry: https://www.iana.org/assignments/authentication-method-reference-values/authentication-method-reference-values.xhtml
- S10 — OpenID Connect EAP ACR Values 1.0 approved as final (M. Jones, 2025-06-17): https://self-issued.info/?m=202506
- S11 — RFC 9470 OAuth 2.0 Step Up Authentication Challenge Protocol: https://www.rfc-editor.org/rfc/rfc9470.html
- S12 — authentik source @4ec0d19 (2026-10-21): `authentik/providers/oauth2/id_token.py`, `views/authorize.py`, `views/provider.py`, `authentik/common/oauth/constants.py`: https://github.com/goauthentik/authentik
- S13 — W3C Web Authentication Level 3, Recommendation 2026-08-25 (and its source `index.bs`, w3c/webauthn): https://www.w3.org/TR/webauthn-3/
- S14 — FIDO Alliance, "WebAuthn Level 3 is now a W3C Recommendation": https://fidoalliance.org/webauthn-level-3-is-now-a-w3c-recommendation/
- S15 — web.dev, "userVerification deep dive": https://web.dev/articles/webauthn-user-verification
- S16 — w3c/webauthn issue 2069, remove `uvm` extension: https://github.com/w3c/webauthn/issues/2069
- S17 — Apple, SecAccessControlCreateFlags and biometryCurrentSet: https://developer.apple.com/documentation/security/secaccesscontrolcreateflags · https://developer.apple.com/documentation/security/secaccesscontrolcreateflags/biometrycurrentset
- S18 — Android, "Show a biometric authentication dialog": https://developer.android.com/identity/sign-in/biometric-auth
- S19 — GitHub Docs, Sudo mode (GHES 3.19): https://docs.github.com/en/enterprise-server@3.19/authentication/keeping-your-account-and-data-secure/sudo-mode
- S20 — Commission Delegated Regulation (EU) 2018/389 (PSD2 RTS), Art. 4–5: https://lawplayer.com/eu/act/32018R0389
- S21 — Google Home Developers, Secondary user verification: https://developers.home.google.com/cloud-to-cloud/enhancements/secondary-user-verification
- S22 — Alexa.LockController Interface 3: https://developer.amazon.com/docs/device-apis/alexa-lockcontroller.html
- S23 — Alexa.ModeController Interface: https://developer.amazon.com/en-US/docs/alexa/device-apis/alexa-modecontroller.html
- S24 — TP-Link Tapo FAQ 4068, smart lock with Alexa (unlock code in the Alexa app): https://www.tp-link.com/support/faq/4068/
- S25 — Apple HomeKit ADK @fb201f9, `HAP/HAP.h` (requiresTimedWrite, supportsAuthorizationData), `Applications/Lock/DB.c`: https://github.com/apple/HomeKitADK
- S26 — Home Assistant core @1ff201c (2026-10-30): `components/lock/entity.py`, `components/alarm_control_panel/entity.py`, `const.py`, `components/manual/alarm_control_panel.py`: https://github.com/home-assistant/core
- S27 — Loxone LxCommunicator (official) @8cba727, `modules/WebSocketConfig.js` token permissions: https://github.com/Loxone/lxcommunicator
- S28 — PyLoxone (third-party HA integration) @7c12c38, `pyloxone_api/connection.py` secured command: https://github.com/JoDehli/PyLoxone
