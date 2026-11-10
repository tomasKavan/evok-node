# 06 — Client apps

**Research, not design.** How browser, shell (mobile/desktop) and wall-panel clients sign in, hold sessions and prove biometry to a node; passkeys and TLS on a LAN; many sites and nodes; enrolment. Feeds 13a (M3.6).

Framework choice is M3.7. Here only auth capabilities matter.

## 1. OAuth for native and browser apps

### 1.1. Native apps (RFC 8252, BCP)

| Rule | Source |
|---|---|
| Native apps MUST use an external user-agent (system browser) for the authorization request; MUST NOT use an embedded webview for it | [V S1 §5, §8.12] |
| Public native clients MUST use PKCE; AS SHOULD reject native requests without PKCE | [V S1 §6, §8.1] |
| A secret built into the app is not confidential; AS should not require client authentication | [V S1 §8.5] |
| AS MUST offer three redirect types: private-use scheme (reverse domain), claimed `https`, loopback | [V S1 §7] |
| Claimed `https` SHOULD be preferred: the OS guarantees which app receives it. A custom scheme can be registered by several apps. Loopback is for desktop | [V S1 §7.2, §8.1] |

- The rule is about the **sign-in page** of the IdP. A shell may still render the Home UI in a WebView; only the IdP login must go to the system browser. [I from S1 §8.12]
- iOS: `ASWebAuthenticationSession` can match an `https` callback (iOS 17.4+), but the host must be an **associated domain** of the app. [V S3]
- Associated domains are fixed in the app entitlement at build time. The `apple-app-site-association` file must be served over https with a valid certificate. Since iOS 14 it is fetched through **Apple's CDN** (so from the internet); a direct mode exists only for development. [V S33]
- Android: **Auth Tab** (Chrome 137+, `androidx.browser` 1.9.0) supports a custom scheme or https redirect; https needs Digital Asset Links. It falls back to Custom Tabs. [V S4]
- AppAuth: iOS 3.0.0 released Aug 2026 [V S6]. AppAuth-Android uses Custom Tabs, does not support WebView, supports custom schemes and App Links [V S5]. Auth Tab support is only requested in an issue [V S5b]; status [GAP — check the AppAuth-Android releases].
- Consequence: a claimed-https redirect works only on a **vendor-owned public domain**, e.g. `https://app.vendor.example/cb`. It must be registered as a redirect URI in every customer's authentik. A custom scheme needs no domain but is weaker. [I]
- authentik 2026.8.5 **checks** PKCE (`plain`/`S256`) when the client sends a challenge, but does **not require** it. The app must always send S256. [V-src S43 `views/authorize.py`, `token/authorization_code.py`]
- Desktop shell (later): loopback redirect. [V S1 §7.3]

### 1.2. Browser apps (RFC 10017, BCP, Aug 2026)

`draft-ietf-oauth-browser-based-apps` is now **RFC 10017** (BCP, August 2026). [V S2]

| Pattern | Tokens in JS? | RFC 10017 position |
|---|---|---|
| **BFF** — confidential backend keeps the tokens; browser has an HttpOnly cookie | no | "strongly recommended for business applications, sensitive applications" [V S2 §6.1.4.3] |
| **Token-mediating backend** — backend gets the tokens, gives the access token to JS | access token only | only when a BFF is not possible [V S2 §6.2.4.4] |
| **Browser-based client** — public client, JS holds all tokens | all | most exposed: malicious JS gets the access and refresh tokens [V S2 §6.3] |

- BFF cookie: `Secure`, `HttpOnly` MUST; `SameSite=Strict`, `Path=/`, no `Domain` SHOULD; `__Host-` prefix. [V S2 §6.1.3.2]
- A browser client's refresh tokens MUST be rotated or sender-constrained. [V S2 §6.3.2.3] DPoP with non-exportable browser keys raises the bar, but does not stop an attacker who starts a new flow. [V S2 §5.2.2]
- For evok-node: the node serving the Home UI can **be** the BFF. The Home API session is then a cookie on the node origin and no token is in JS. [I] Cookies on a WS upgrade need an Origin check (02).

## 2. Biometry-bound keys

### 2.1. iOS (Secure Enclave)

- SE keys: **NIST P-256 only** (sign / ECDH). They are created inside the SE and cannot be imported or exported. They are usable only on the device that created them. [V S10]
- `.privateKeyUsage` is required for signing. The protection class `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` makes the key usable only while the device is unlocked. [V S10]

| Flag | Accepts | On a new finger / face re-enrolment |
|---|---|---|
| `.biometryCurrentSet` | biometry only | **key invalidated** [V S8] |
| `.biometryAny` | biometry only | still valid [V S7] |
| `.userPresence` | biometry **or device passcode** (= `biometryAny or devicePasscode`) | still valid; biometry need not be enrolled [V S9] |
| `.devicePasscode` | device passcode | n/a [V S7] |

- The device passcode is the **phone's** secret, not an evok-node PIN. How it maps to auth levels: (03). [I]

### 2.2. Android (Keystore)

- `setUserAuthenticationRequired(true)` + `setUserAuthenticationParameters(timeout, type)`. `timeout = 0` means auth **for every use**. `type` = `AUTH_BIOMETRIC_STRONG` and/or `AUTH_DEVICE_CREDENTIAL`. [V S12]
- A per-use key needs `BiometricPrompt.authenticate(…, CryptoObject)`. CryptoObject supports `Signature`, `Cipher`, `Mac`, `KeyAgreement`. [V S11]
- Time-bound keys that allow a device credential cannot be used with a CryptoObject. [V S11]
- `BIOMETRIC_STRONG` = Class 3, `BIOMETRIC_WEAK` = Class 2. [V S11] Keystore keys accept only strong biometrics (`AUTH_BIOMETRIC_STRONG`). [V S12]
- `setInvalidatedByBiometricEnrollment` is **true by default** (API 24+): a new biometric invalidates the key. [V S11]
- `setIsStrongBoxBacked` asks for a separate secure chip; without one, key creation fails. [I] (the reference page did not render; the S12 mirror only says "protected by a StrongBox security chip")

### 2.3. Prompt only vs crypto-bound

| | Prompt only (`LAContext.evaluatePolicy`, `BiometricPrompt` without CryptoObject, `local_auth`) | Crypto-bound key |
|---|---|---|
| What the node gets | the app's word ("user passed") | a signature over the node's nonce that it can verify |
| On a rooted or hooked phone | a boolean in app memory; can be forced to true | the secure hardware refuses to sign without biometry |
| Stolen session replayed from another device | passes | fails: the key is not exportable |

OWASP MASTG calls the prompt-only case "event-bound biometric authentication" and recommends "cryptographic binding" (MASTG-TEST-0266, MASTG-BEST-0036). [V S17 — titles only; the body did not render] Rows 2–3 are [I] from S10 and S11.

### 2.4. Attestation — what it proves

| Mechanism | Proves | Needs online? |
|---|---|---|
| Apple **App Attest** | A Secure Enclave key belongs to a genuine instance of **your app**. Assertions sign `clientDataHash` = challenge + request. Keys are lost on reinstall, migration or restore. | `attestKey` calls Apple servers [V S13] |
| Android **Key Attestation** | The key is in TEE/StrongBox. The certificate lists its properties: `noAuthRequired`, `userAuthType`, `authTimeout`, `rootOfTrust` (verified boot), `attestationApplicationId`, `attestationChallenge`. | Chain checks against the Google root work locally; the revocation list is online [V S14, S15] |
| **Play Integrity** | Unmodified app recognised by Play; installed from Play; certified device | Google service; the verdict is checked on your server [V S16] |

- App Attest has no access-control parameter (`generateKey` takes none). It cannot show that **another** SE key is biometry-gated. The node trusts the attested app to have set the flags. [I from S13]
- Android attestation **does** show the user-auth requirement of the step-up key itself. [V S15]

### 2.5. Step-up pattern and DPoP

```
node → app : challenge = {nonce(≥16 B, single use, ~60 s), node, session, op:"home:door3.unlock", argsHash}
app        : biometric prompt → SE/Keystore signs SHA-256(challenge)   (ES256)
app → node : signature, keyId
node       : verify with the stored public key; nonce unused; op/args match → relay with proof
```

- The same shape as App Attest assertions (challenge + request hashed) [V S13] and WebAuthn assertions. [I]
- The node verifies with a stored public key, with no IdP call, so it works offline. The key must have been registered earlier, while the phone could reach the node (05). [I]
- **Same key as DPoP? (02)** Technically yes: SE keys are P-256/ES256, and authentik DPoP accepts EC P-256 [V-src S43 `dpop.py`]. Practically no: a per-use biometric key prompts on **every** proof, and DPoP signs every request. Use two keys: a session key with no user auth, and a biometric step-up key. [I]
- authentik can bind the ID token to the DPoP key: the `bound_key` scope + `dpop_jkt` gives an ID token of type `dpop+id_token`. [V-src S43 `views/authorize.py`, `views/token.py`] Details: (02).
- **Re-enrolment:** with `biometryCurrentSet` or the Android default, adding a finger kills the step-up key. Biometric step-up then fails until the app registers a new key. While the IdP is unreachable this needs a fallback (PIN). [I from S8, S11]

## 3. Shell frameworks — auth capabilities only

| Framework | Prompt only | Biometry-gated stored secret | Biometry-gated **signing key** |
|---|---|---|---|
| **Capacitor** (v8 current [V S19]) | `@capawesome-team/capacitor-biometrics` (`authenticate` resolves/rejects) [V S20]; `@capgo/capacitor-native-biometric` `verifyIdentity` [V S19] | capgo `getSecureCredentials` with `accessControl` `BIOMETRY_CURRENT_SET`/`BIOMETRY_ANY` [V S19]; Capawesome Secure Preferences (Keychain/Keystore-encrypted, no gating documented) [V S21] | none found. `@perfood/capacitor-crypto-api` makes SE/StrongBox P-256 signing keys, but **no biometric gating** is documented; 1.0.0-0, Jul 2024 [V S22] → custom plugin [I] |
| **Tauri 2** | `authenticate()` [V S18] | `biometricCipher` encrypt/decrypt behind the prompt (data options marked Android-only) [V S18] | **no** — no sign API [V S18]. Stronghold: [GAP — status not checked] |
| **React Native** | `simplePrompt` (react-native-biometrics) [V S23]; expo-local-authentication [I] | `expo-secure-store` `requireAuthentication` → iOS `biometryCurrentSet`, Android `setUserAuthenticationRequired`; invalidated on biometric change [V S24]; react-native-keychain [I] | `react-native-biometrics` `createKeys`/`createSignature`: **RSA-2048**, PKCS#1 v1.5. Original SelfLender; forks exist; maintenance [GAP] [V S23]. RSA cannot live in the SE → iOS key is a Keychain key [I from S10] |
| **Flutter** | `local_auth` 3.0.2 → `bool` [V S25] | `flutter_secure_storage` 11.2.0 `AndroidOptions.biometric(enforceBiometrics, strongBiometricOnly)` [V S26] | **`biometric_signature` 13.3.0**: SE (iOS/macOS) / Keystore or StrongBox P-256 or RSA, sign after biometry; invalidated on enrolment by default; device-credential option [V S27] |

- A **gated secret** is better than a prompt: the hardware releases the secret only after biometry. But the node still gets a bearer value, not a fresh signature over its nonce. [I]
- For any framework, a small native plugin (Swift `SecKeyCreateRandomKey` + Kotlin `KeyGenParameterSpec`) covers §2.5. [I]

## 4. Passkeys / WebAuthn on a LAN

WebAuthn Level 3 has been a W3C **Recommendation** since **25 Aug 2026**. [V S28]

| Rule | Source |
|---|---|
| RP ID = a **valid domain string**; it must equal the origin's effective domain or be a registrable domain suffix of it | [V S28 §4 "RP ID"] |
| If the effective domain is **not a valid domain → `SecurityError`**. "Only the domain format of host is allowed … issues with using direct IP address identification in concert with PKI" | [V S28 §5.1.3, §5.1.4] |
| The WG closed issue #1358: "IP addresses are not permitted in RP IDs". Chromium rejects RP IDs that are not hostnames | [V S32, S31] |
| Secure context only; for the web this means "TLS established **without errors**". The scheme must be `https`, except `http://localhost` | [V S28 §4, §5] |
| Related Origin Requests: `https://<rpid>/.well-known/webauthn` with an `origins` list; clients support ≥ 5 labels | [V S28 §5.11, S30] |
| Native apps: a passkey for RP `x` needs `webcredentials:x` in the entitlement + the AASA file via Apple's CDN (wildcard `*.x` allowed) | [V S33]; Android Digital Asset Links [I] |

Consequences:
- **`https://192.168.1.20`: no WebAuthn at all.** An IP address is not a valid domain. A self-signed certificate with a clicked-through warning is "TLS with errors". [V S28; I]
- `plc1.local` is a valid domain string. It needs a certificate the browser trusts, and public CAs do not issue for `.local`. So it needs a private CA. [I] Whether Android Chrome resolves `.local`: [GAP — test on a device].
- One passkey can serve all nodes of a site if the RP ID is the parent name: `site.example` covers `n1.site.example`, `n2.site.example`. [V S28 §4 example] Each node can verify an assertion offline with the stored public key (05). [I]
- A passkey assertion with UV=1 is also verifiable "biometry or PIN" proof for step-up (03). [I]

## 5. Local TLS for PLCs

| Option | Real precedent | Browser | Shell app | Passkeys | Offline |
|---|---|---|---|---|---|
| **http only** | Home Assistant default: "without SSL" [V S35]; the companion app's "Most secure" mode allows cleartext only on the home Wi-Fi SSID [V S36] | no secure context | OK if allowed | no | yes |
| **Self-signed + TOFU/pinning** | [I] common on appliances | warning every time | pin the cert/key in the app (WKWebView/WebView TLS callback) [I] | no | yes |
| **Private site CA** | enterprise | install the CA on each device: iOS profile + trust setting; Android apps ignore user CAs by default [I] | bundle/pin the CA | yes (domain name) | yes |
| **ACME DNS-01**, owned domain, split DNS | homelab [I] | trusted | trusted | yes | renewal needs internet [I] |
| **Per-device public names** (Plex `*.<hash>.plex.direct`) | DigiCert wildcard per user; `1-2-3-4.<hash>.plex.direct` resolves to the IP in the name; the private key is on the server [V S34] | trusted | trusted | yes | needs public DNS (or a cache); **router DNS-rebinding protection breaks it** [V S34] |

- Coupling with §1: with the **local IdP**, the login page is on the node. The system browser (ASWebAuthenticationSession / Custom Tabs) does not know the app's pin, so a self-signed node shows a certificate error in the sign-in flow. [I]
- Public certificate lifetimes are getting shorter (CA/B Forum schedule toward ~47 days). A site offline longer than the lifetime has an expired certificate; browsers refuse it, but a pinning shell app can carry on. [I]
- **Chrome Local Network Access** (shipped in Chrome 142, after a slip from 141): a public site needs a **permission prompt** to reach local or loopback IPs. Requests from insecure contexts are silently rejected. With the permission, `fetch(…, {targetAddressSpace:"local"})` is exempt from mixed-content blocking. [V S41]
- LNA did **not** cover WebSockets at launch; a separate intent was planned. [V S41] Whether WS is covered now: [GAP] — a secondary source (S42, Mar 2026) says yes. Safari/Firefox: [GAP].
- Mixed content: an `https` page cannot open `ws://` to a node. [I]
- iOS Local Network permission: a native app that talks to LAN hosts needs `NSLocalNetworkUsageDescription` (and `NSBonjourServices` for DNS-SD) and gets a one-time prompt. [I]; whether WKWebView loads count: [GAP] (Apple TN3179 not fetched)

## 6. Many sites, many nodes

| App | Multi-home model |
|---|---|
| Home Assistant companion | several servers: "Settings > Companion app > Add Server" (HA 2021.10+); servers on the LAN are found automatically; otherwise a URL by hand [V S36]. Each server has its own OAuth-style login (client_id = URL, IndieAuth style) [V S37] |
| Apple Home, UniFi | [GAP — not checked] |

- **Site IdP:** one IdP session (refresh token) per site in the shell. Per-node access tokens are derived from it (audience, 02). An offline refresh is valid "for this node only" → the shell keeps a per-node token map. [I]
- **Local IdP:** one session per node. A site of N local-IdP nodes = N logins, unless the nodes trust each other (02). [I]
- Discovery: DNS-SD over mDNS (RFC 6762/6763); HA does LAN autodetection [V S36], mechanism [I]. A node record can carry the node id and the cert fingerprint for pinning. [I]
- Remote access: tunnel or relay (HA → Nabu Casa tunnel [V S35]); out of scope here.

## 7. Shell ↔ hosted web app

Precedent — **HA "external auth"**: the frontend loads with `?external_auth=1`. It calls the native bridge `getExternalAuth`; the app answers `externalAuthSetToken(true,{access_token, expires_in})`. The **refresh token stays in the app**. Logout = `revokeExternalAuth`. The app must check the callback name. [V S38]

| Hand-off | Token visible to JS | Main risk |
|---|---|---|
| JS bridge returns a short-lived token (HA) | access token | any frame or origin in the WebView can call the bridge |
| Native sets an HttpOnly cookie in the WebView cookie store | no | cookie sent on WS upgrade → CSRF/CSWSH unless Origin is checked (02) [I] |
| `postMessage` into an iframe | yes | wrong `targetOrigin` / no origin check [I] |

- **CVE-2026-44698** (HA companion, CVSS 8.3): the bridge was reachable from **all frames** and the callback id was put into JS without escaping. A cross-origin iframe stole the access token. Fixed in iOS 2026.4.1 / Android 2026.4.4. [V S39]
- Rules that follow: bridge only for the main frame and allowlisted node origins; validate every message; no third-party content in the shell WebView; give out short-lived node tokens only. [I]

## 8. Kiosks and wall panels

| Mechanism | Facts |
|---|---|
| Device Authorization Grant (RFC 8628) | The panel shows a code/URL and the user approves on a phone. authentik supports `urn:ietf:params:oauth:grant-type:device_code` [V-src S43]. It needs the IdP online at enrolment [I] |
| HA `trusted_networks` | IP ranges log in **without a password**; the user is picked from a list (`trusted_users`); `allow_bypass_login` with one user skips the page; MFA does not take part [V S40] |
| HA long-lived access token | 10-year token created in the user profile [V S37] |
| Device-bound credential | a key in TPM (Edge) / Android Keystore on the panel; the panel is its own principal [I] |

- **Who is the user?** Precedents treat the panel as a principal (a fixed HA user or an IP-trusted user). Nobody is identified unless someone enters a code. [I from S40] For `proof` methods, the actor becomes the person whose PIN is typed on the panel. [I]

## 9. Enrolling a new phone

| Path | Precedent | Online IdP needed |
|---|---|---|
| OIDC login in the system browser, then the app registers its public keys with the node(s) | HA companion login [V S37] | yes (site IdP) |
| QR shown in the Inspector or on an enrolled device: node URL + cert fingerprint + one-time code | [I] (Matter setup codes, messenger "link device") | no (local IdP / replica) |
| Device grant approved by a user or admin | authentik device flow [V-src S43] | yes |
| Admin approval of a pending device | [I] | no |

- The QR fingerprint also solves TOFU: the first TLS connection is pinned to a value the user scanned. [I]
- Optional at enrolment, when online: App Attest / Key Attestation over the step-up public key (§2.4). [I]

## 10. Proposals for 13a (not binding)

- **P1 — Two hardware keys per app install per site.** A session key with no user auth (session binding / DPoP, 02) and a step-up key (`biometryCurrentSet` / `AUTH_BIOMETRIC_STRONG`, per use). The node stores both public keys; the replica copies them to the site's nodes.
- **P2 — Step-up = signed node challenge.** Nonce + node + session + method address + args hash, short TTL, single use. It is verifiable offline and gives the `proof` evidence for a driver call.
- **P3 — Native sign-in by the book.** System browser (ASWebAuthenticationSession / Auth Tab → Custom Tabs). Always PKCE S256, because authentik does not enforce it. Claimed https on a vendor domain where possible, custom scheme as fallback.
- **P4 — HA-style hand-off.** The web app asks the bridge for a short-lived node token; the refresh token and keys stay native. The bridge is for the main frame and pinned node origins only. Alternative: the node acts as BFF and uses cookies.
- **P5 — Give every node a DNS name.** IP-only + self-signed rules out passkeys and browser biometry. Offer DNS-01 with an owned domain, or a Plex-like vendor zone, and always let the shell pin the node key.
- **P6 — QR enrolment.** Node URL + fingerprint + one-time code. With a site IdP, an OIDC login comes first; offline, admin approval in the Inspector.
- **P7 — Wall panel = device principal.** Scoped role (e.g. `panel` @ flat 3), device-bound long-lived credential, enrolled by device grant or QR. `proof` methods need a person's PIN, and that person becomes `actor`.
- **P8 — Shell session model.** One session per site IdP, a per-node token map, local-IdP nodes as separate sessions; DNS-SD discovery.
- **P9 — Attestation is a bonus, not a gate.** Use it at enrolment when online; never require it for offline operation.

## 11. Sources

- S1 — RFC 8252 OAuth 2.0 for Native Apps: https://www.rfc-editor.org/rfc/rfc8252
- S2 — RFC 10017 OAuth 2.0 for Browser-Based Applications (Aug 2026): https://www.rfc-editor.org/rfc/rfc10017.html
- S3 — Apple, ASWebAuthenticationSession.Callback.https(host:path:): https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/callback/https(host:path:).md
- S4 — Chrome, Auth Tab guide: https://developer.chrome.google.cn/docs/android/custom-tabs/guide-auth-tab
- S5 — AppAuth-Android README: https://github.com/openid/appauth-android ; S5b — issue #1146: https://github.com/openid/AppAuth-Android/issues/1146
- S6 — AppAuth (iOS) on CocoaPods: https://cocoapods.org/pods/AppAuth
- S7 — Apple, SecAccessControlCreateFlags: https://developer.apple.com/documentation/security/secaccesscontrolcreateflags.md
- S8 — Apple, biometryCurrentSet: https://developer.apple.com/documentation/security/secaccesscontrolcreateflags/biometrycurrentset.md
- S9 — Apple, userPresence: https://developer.apple.com/tutorials/data/documentation/security/secaccesscontrolcreateflags/userpresence.md
- S10 — Apple, Protecting keys with the Secure Enclave: https://developer.apple.com/tutorials/data/documentation/security/protecting-keys-with-the-secure-enclave.md
- S11 — Android, Show a biometric authentication dialog: https://developer.android.com/identity/sign-in/biometric-auth
- S12 — KeyGenParameterSpec.Builder (MS Learn mirror of Android docs): https://learn.microsoft.com/en-us/dotnet/api/android.security.keystore.keygenparameterspec.builder?view=net-android-37.0 and https://learn.microsoft.com/zh-tw/dotnet/api/android.security.keystore.keygenparameterspec.builder.setuserauthenticationparameters?view=net-android-37.0
- S13 — Apple, Establishing your app's integrity (App Attest): https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity.md
- S14 — Android, Verify hardware-backed key pairs with key attestation: https://developer.android.com/privacy-and-security/security-key-attestation
- S15 — AOSP, Key and ID attestation (schema): https://source.android.com/docs/security/features/keystore/attestation
- S16 — Play Integrity API overview: https://developer.android.com/google/play/integrity/overview
- S17 — OWASP MASTG-TEST-0266 / MASTG-BEST-0036: https://mas.owasp.org/MASTG/tests/ios/MASVS-AUTH/MASTG-TEST-0266/ , https://mas.owasp.org/MASTG/best-practices/MASTG-BEST-0036/
- S18 — Tauri 2 biometric plugin JS reference: https://v2.tauri.app/reference/javascript/biometric/
- S19 — Capgo capacitor-native-biometric: https://capgo.app/es/plugins/capacitor-native-biometric
- S20 — Capawesome, Exploring the Capacitor Biometrics API: https://capawesome.io/blog/exploring-the-capacitor-biometrics-api
- S21 — Capawesome, How to securely store credentials with Capacitor: https://capawesome.io/docs/blog/how-to-securely-store-credentials-with-capacitor/
- S22 — @perfood/capacitor-crypto-api: https://socket.dev/npm/package/@perfood/capacitor-crypto-api
- S23 — react-native-biometrics (fork of SelfLender): https://github.com/Censkh/react-native-biometrics
- S24 — Expo SecureStore (SDK 58): https://docs.expo.dev/versions/latest/sdk/securestore.md
- S25 — local_auth 3.0.2: https://pub.dev/documentation/local_auth/latest/
- S26 — flutter_secure_storage 11.2.0: https://pub.dev/documentation/flutter_secure_storage/latest/
- S27 — biometric_signature 13.3.0: https://pub.dev/documentation/biometric_signature/latest/index.html
- S28 — W3C WebAuthn Level 3, Recommendation 2026-08-25 (checked in the spec text): https://www.w3.org/TR/webauthn-3/
- S30 — passkeys.dev, Related origins: https://passkeys.dev/docs/advanced/related-origins/
- S31 — Chromium webauth_request_security_checker.cc: https://chromium.googlesource.com/chromium/src/+/a7f3967921b2960c9e901b027cbefd2536715615/content/browser/webauth/webauth_request_security_checker.cc
- S32 — W3C webauthn issue #1358 (IP as RP ID): https://lists.w3.org/Archives/Public/public-webauthn/2023Sep/0057.html
- S33 — Apple, Supporting associated domains: https://developer.apple.com/documentation/xcode/supporting-associated-domains.md
- S34 — F. Valsorda, How Plex is doing HTTPS for all its users: https://words.filippo.io/how-plex-is-doing-https-for-all-its-users/
- S35 — Home Assistant, HTTP integration: https://www.home-assistant.io/integrations/http/
- S36 — HA companion, Getting started: https://companion.home-assistant.io/docs/getting_started/
- S37 — HA developers, Authentication API: https://developers.home-assistant.io/docs/auth_api
- S38 — HA frontend, External authentication: https://contributors.home-assistant.io/frontend/reference/external-auth/
- S39 — CVE-2026-44698 (HA companion bridge): https://osv.dev/vulnerability/CVE-2026-44698
- S40 — HA, Authentication providers (trusted_networks): https://www.home-assistant.io/docs/authentication/providers/
- S41 — blink-dev, Intent to Ship: Local network access restrictions: https://groups.google.com/a/chromium.org/g/blink-dev/c/cwu_RUmBpzY/m/hk8YuZDWHgAJ
- S42 — OpenReplay blog, Chrome LNA permission (secondary, Mar 2026): https://blog.openreplay.com/chrome-local-network-access-lna-permission/
- S43 — authentik source, release 2026.8.5 (commit 4ec0d19): https://github.com/goauthentik/authentik
