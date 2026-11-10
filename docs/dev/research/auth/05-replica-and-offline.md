# 05 — Replica and offline

**Research, not design.** How a node replica gets data from the site IdP, how other systems authenticate when the central authority is down, what a replica can hold for each factor, and revocation while offline. Feeds 13a (M3.6).

Checked 2026-10-30. Versions in use: authentik docs 2026.8 (API client 2026.8.5), Keycloak 26.8.x, WebAuthn Level 3 (W3C Recommendation 2026-08-25).

## 1. Syncing from the site IdP into a replica

### 1.1. SCIM 2.0: what a receiving server needs

| Item | Fact |
|---|---|
| Resources | `/Users` and `/Groups`, plus the discovery endpoints `/ServiceProviderConfig`, `/ResourceTypes` and `/Schemas` [V S1 §3.2]. Group membership lives in `Group.members`. `User.groups` is read-only, and membership changes "MUST be applied via the Group Resource" [V S2 §4.1.2, §4.2]. |
| Optional | PATCH ("an OPTIONAL server function") [V S1 §3.5.2], bulk [V S1 §3.7], filtering [V S1 §3.4.2.2], sorting [V S1 §3.4.2.3], ETags / `meta.version` [V S2 §3.1]. |
| PATCH ops | `add`, `remove`, `replace` [V S1 §3.5.2.1–3]. |
| Auth | TLS plus HTTP auth. The server announces its schemes in `WWW-Authenticate`. Bearer tokens MAY be used [V S1 §2]. |
| Password | `password` is writeOnly. "The cleartext value or the hashed value … SHALL NOT be returnable" [V S2 §4.1.1]. |
| Change feed | SCIM has none. A reader can only poll, for example with a filter on `meta.lastModified`, and filtering is optional [I]. |

**Minimum for an authentik push** [I from S3]: serve `/ServiceProviderConfig` with patch, bulk and filter all set to false; implement POST, GET by id, PUT and DELETE on `/Users` and `/Groups`; and store `externalId`, which the client sets [V S2 §3.1]. Without PATCH, authentik sends PUT for group updates [V S3].

### 1.2. authentik SCIM provider (push)

| Aspect | Behaviour |
|---|---|
| Role | A backchannel provider attached to an application. It needs a base URL and a token [V S3]. It has one `url` per provider [V S4], so N nodes need N providers [I]. |
| Objects sent | Users and groups. Membership goes as PATCH if the server supports it, otherwise as PUT [V S3]. |
| Attributes | Set by property mappings. They are deep-merged in name order and validated against the SCIM schema. Custom extension schemas are possible (the docs' example is a custom `github` attribute) [V S3]. |
| Trigger | "When a user or group is created, modified, or deleted, that change is sent to all SCIM providers" [V S3]. The sync runs in worker tasks, one task per batch of 100 objects (`sync_page_size`) [V S3, S4]. |
| Full sync | "Once an hour, all SCIM providers are fully synchronized" [V S3]. |
| Scope | Users bound to the application are synced. If nobody is bound, all users are synced. Service accounts can be excluded. `group_filters` limits groups, and changing them does not remove groups synced earlier [V S3, S4]. A user who is unassigned is deprovisioned at the next sync [V S3]. |
| Failures | A mapping error or a schema validation error stops the sync. `SkipObject` skips one object [V S3]. HTTP errors are logged as `TransientSyncException` / `BadRequestSyncException` task warnings [V-src S5]. Transient errors are retried up to `AUTHENTIK_WORKER__TASK_MAX_RETRIES` times (default 5), verified in source in 01 §6. Changes made while the receiver was down are picked up by the hourly full sync at the latest [I]. |
| Auth to receiver | A static bearer token, or (Enterprise) OAuth tokens from an OAuth source [V S3]. There is also a `dry_run` option [V S4]. |
| Credentials | Passwords are not mentioned [V S3]. A custom Python mapping might be able to read the user object's Django password hash [I]. Unverified and not advisable: [GAP]. |
| Network | authentik opens the connection to the replica, so every node must be reachable from the IdP over HTTPS [I]. |

### 1.3. Keycloak

- Keycloak has a native SCIM **server** (inbound) only. It was experimental in 26.6 behind the `scim-api` feature flag. It covers Users and Groups with PATCH, but not bulk, password management or custom schemas [V S13]. 26.8 makes the inbound SCIM API supported, per the primary release notes (01 §8).
- It has **no outbound SCIM client**: "can receive a directory push but has no outbound SCIM client to push users anywhere else" [V S14]. A Keycloak site therefore needs a polling replica, or a third-party extension [I].

### 1.4. LDAP (authentik LDAP outpost)

- Only bind and search are documented. There are two modes: *direct* (each request goes to the core API) and *cached* (the outpost fetches periodically and "can return stale data") [V S6].
- Persistent search and syncrepl (RFC 4533) are not documented, so they are probably unsupported [I]. To settle it, run `ldapsearch -E sync=rp` against an outpost [GAP].
- Exposed data: users with `memberOf` and custom attributes; groups with `member` [V S6]. No password attribute is listed [V S6].
- Bind runs the authentik flow, and TOTP, Duo or static codes are accepted as `password;code` [V S6]. A replica that relays an LDAP bind sees the cleartext password (see §3.1) [I].
- 2N Access Commander already syncs over LDAP, so an outpost probably exists on the site [I].

### 1.5. Polling the admin REST API

- This gives users, groups, membership and attributes, with a latency equal to the poll interval [I]. The replica controls the timing and the reconciliation, and it works behind NAT [I].
- authentik's WebAuthn device API returns `pk, name, created_on, device_type, aaguid, user`, with **no `public_key` and no `credential_id`** [V-src S11], although the model stores both [V-src S10].
- Keycloak's REST API does not return credential `secretData` (password hashes) [V S16]. `kc.sh export` needs a stopped server [V S15]. Whether that export holds the hashes: a user report says yes [V S17], with no official statement [GAP].

### 1.6. Webhooks (authentik notifications)

- A notification rule plus a policy (for example an event matcher) sends to a transport: local, email, generic webhook (POST JSON), or Slack/Discord [V S7, S8].
- The default body is `body, severity, user_email, user_username, event_user_email, event_user_username`, and body and header mappings can change it [V S8].
- The available `action` values (for example `model_updated`) [GAP]. Retry of failed deliveries [GAP].
- Use: a "poke" that triggers a pull, not a data channel [I].

### 1.7. Summary

| Channel | Users | Groups | Custom attrs | Credentials | Latency | Direction |
|---|---|---|---|---|---|---|
| authentik SCIM | ✓ | ✓ + members | ✓ (mappings) | ✗ | change-triggered + 1 h full [V S3] | IdP → node |
| Keycloak SCIM | — | — | — | — | not available (inbound only) [V S14] | — |
| LDAP outpost | ✓ | ✓ | ✓ [V S6] | ✗ (bind only) | poll interval [I] | node → IdP |
| REST polling | ✓ | ✓ | ✓ | ✗ (no WebAuthn public keys) [V-src S11] | poll interval [I] | node → IdP |
| Webhook | event only | event only | via mapping | ✗ | event-driven, retry [GAP] | IdP → node |

## 2. Offline authentication precedents

| System | What is cached | Created when | Offline lifetime | Lockout | Impossible offline |
|---|---|---|---|---|---|
| **SSSD** | A hash of the password, never cleartext [V S19]. It needs `cache_credentials = true` in `[domain/…]`, default false [V S18, S19]. | After a successful online login: "users who logged in successfully during the most recent online login" can log in offline [V S19]. | `[pam] offline_credentials_expiration`: days since the last online login, 0 = unlimited (default). `account_cache_expiration`: days before the entry is purged, 0 = never [V S18, S20]. | `[pam] offline_failed_login_attempts` (default 0 = unlimited), then `offline_failed_login_delay` minutes (default 5) [V S18, S20]. | First login of a user, password change [I]. |
| **Windows cached logon** | A verifier per user, in 10 slots by default (0–50, FIFO) [V S21, S22]. Format (DCC2/MSCash2) not verified [GAP]. | At logon while a DC is reachable [V S22]. | "does not expire" [V S22]. | Not documented [GAP]. | "network resources that require domain validation". A password changed in the cloud does not update the verifier, so the old password still works locally [V S21]. |
| **Kanidm unixd** | An Argon2id hash keyed by an HMAC key that the HSM/TPM layer creates (`hmac_s256_create`). The KDF target is 250 ms [V-src S23]. A software ("soft") TPM is also supported [V S24]. The config key for hardware vs. soft TPM: [GAP]. | Only after a successful online auth (`kanidm_update_cached_password`) [V-src S23]. | `cache_timeout` controls refresh. Expired items are still served while offline [V S24, S25]. Hard offline expiry not found [GAP]. | Not found in source [GAP]. | MFA and device grant: offline is password-only [V-src S23]. |
| **Entra backup auth** | Metadata and policy results from a prior authentication [V S26]. | The user used the app "in the last three days from the same device" [V S26]. | Sessions expiring during an outage are extended [V S28]. CAE tokens last up to 28 h [V S29]. | n/a | New sessions, interactive sign-in, guests, confidential clients, ROPC, fresh CRL checks [V S26, S27, S28]. |
| **AWS Greengrass CDA ≥ 2.3.0** | The client device's thing registration and certificate validation [V S30]. | First connect while the core is online. Refreshed on reconnect and once a day [V S30]. | `clientDeviceTrustDurationMinutes`: 1 to 2³¹−1, default 1, which "effectively turns off offline authentication" [V S30]. | n/a | Devices never seen online [V S30]. |
| **Azure IoT Edge 1.6** | Identities of modules and child devices [V S31]. | Initial sync while online. Children must be declared in IoT Hub beforehand [V S31]. | "indefinitely" [V S31]. | n/a | New children. Status reporting [V S31]. |
| **Duo Windows Logon** | One offline-activated device per user (Duo Mobile or a U2F key) [V S32]. | After a successful online 2FA [V S32]. | Max N logins, or max days ≤ 365. The counter resets at the next online auth [V S32]. | Not documented [GAP]. | More than 5 users per machine by default (`OfflineMaxUsers` 1–50) [V S32]. |
| **Akamai MFA Windows** | A TOTP seed [V S33]. | n/a | Max days / max logins, default no limit. When reached, the user must "authenticate online" [V S33]. | 1–30 attempts (default 3). Lockout default "Never Unlock" [V S33]. | Any factor other than TOTP [V S33]. |
| Home Assistant | No replica: the instance is its own IdP. Access token 1800 s, refresh token expires after 90 days unused [V S34]. | | | | |
| Matter | Each node holds its fabric credentials (NOC). CASE sessions are set up peer to peer. The docs mention no cloud for operation [V S35]. | | | | |

**Pattern** [I]: every system creates an offline credential only after an online success on *that* machine, bounds it by a count and/or days since the last online authentication, and gives it local scope only.

## 3. What a replica can hold, per factor

### 3.1. Password

- No IdP checked here exports hashes over its API. SCIM forbids returning them [V S2 §4.1.1]. Keycloak REST omits `secretData` [V S16]. authentik's API and LDAP list no hash [V S6].
- A replica can capture a verifier only if the cleartext passes through it:
  - an LDAP bind relayed to the outpost [V S6, I];
  - the replica running the authentik flow itself, as the LDAP outpost does [V S6, I];
  - ROPC: RFC 9700 §2.4 says it "MUST NOT be used" [V S36]. authentik treats `grant_type=password` as `client_credentials` with app passwords, not user passwords [V S9].
- With OIDC redirect login (03, 06) the password never reaches the replica, so **offline password login is impossible**. This matches the requirement "biometry or PIN only" [I].

### 3.2. PIN verifier

**Brute force** [I]: 10⁶ PINs against a fast hash take well under a second. With Argon2id tuned to 250 ms on the PLC, an attacker (assumed ~50 ms per guess per core, 16 cores) needs about 50 minutes for 6 digits and about 30 seconds for 4 digits. Without hardware, the verifier file *is* the PIN.

**How real systems protect short secrets:**

| System | Mechanism |
|---|---|
| Windows Hello | The PIN is local and never sent anywhere. The TPM does anti-hammering [V S37]. Windows sets TPM 2.0 to lock after 32 failures and forget one failure every 10 minutes. **The lockout is global** for the TPM [V S38]. |
| Android Gatekeeper | HMAC with a key held in the TEE. The failure counter is written *before* verify, so cutting power cannot skip the penalty. RPMB storage is recommended [V S39]. |
| Android Weaver | Slots in secure hardware release their value only for the matching key. The secure app enforces rate limits [V S40]. |
| Apple | The passcode is entangled with the device UID, about 80 ms per try. Delays after the 4th–9th failure are 1 min, 5 min, 15 min, 1 h, 3 h and 8 h; the 10th locks the device. The Secure Enclave enforces this, and the delays survive reboot [V S41]. |
| Kanidm design | A soft TPM must "aggressively increase the KDF rounds" for PINs. "We must not allow SSH auth with PIN to a TPM as this can easily become a remote DOS" [V S24]. |
| TPM 2.0 DA | Parameters `max-tries`, `recovery-time` and `lockout-recovery-time` [V S42]. The reference code heals failures every `recoveryTime` and counts an unorderly shutdown as a failure [V-src S43]. Keys without an authValue still work while the TPM is locked [V S38]. |

On a PLC [I]:
- **No secure element (Patron? Neuron):** only a software limiter is possible. Use a persistent per-user failure counter, written before verifying (Gatekeeper pattern), with escalating delays. This protects against online guessing only. Anyone who reads the 0600 file can brute-force offline (numbers above). A pepper stored on the same eMMC adds nothing against that attacker.
- **TPM 2.0 (Edge):**
  - (a) Kanidm pattern: the verifier is HMAC_TPM(Argon2id(PIN)). A stolen eMMC or backup is useless, but root on the device can still guess at TPM speed. TPM HMAC throughput: [GAP].
  - (b) The PIN as the authValue of a sealed TPM object: hardware DA limits even root, but the global lockout lets one network attacker block all PIN logins on the node (the Kanidm DoS warning) [V S24, S38].
- Patron TPM presence: [GAP] (brief).

### 3.3. Device keys (biometry)

- To verify a signed challenge offline, the replica needs only the public key, a fresh nonce from the replica, and optionally the signature counter [I].
- **WebAuthn credentials registered at authentik**:
  - authentik stores `rp_id`, `public_key`, `credential_id` and `sign_count` [V-src S10], but its API does not expose the key [V-src S11].
  - "The RP ID must be equal to the origin's effective domain, or a registrable domain suffix" of it [V S44 §4]. A replica can use such a credential only on an origin under that domain, and only if it has the key [I].
  - authentik takes the RP ID from the request hostname, which is not configurable. This is a user report [V S12], confirmed in source in 01 §6.
  - Related Origin Requests list extra origins at `https://{RP ID}/.well-known/webauthn`, with up to 5 eTLD+1 labels [V S45]. The browser must fetch that file during the ceremony, so it fails when the RP ID host is off-site and the internet is down [I].
- **Own device key** (shell app, a non-WebAuthn key gated by biometry): register its public key with the replica after an online login. It could be spread to other nodes as a custom authentik attribute through SCIM mappings [V S3 custom attrs, I]. → 06.

## 4. Revocation and change while offline

| Case | What bounds exposure |
|---|---|
| A change at the IdP while the node is reachable | SCIM push within seconds (worker queue), or the 1 h full sync [V S3]; with polling, the poll interval [I]. |
| A change at the IdP while the node is partitioned | The node cannot know. The bound is the lifetime of local sessions and offline credentials [I]. Precedent: Entra cannot do fresh revocation checks and says to "explicitly revoke the session" [V S26]. |
| The IdP itself is down | Nothing can be changed at the IdP. The only lever is local admin on the node [I]. |
| A password or credential changed at the IdP | Windows keeps the old verifier working locally [V S21]. In Kanidm, an online denial with an old password does not clear the cached verifier (code comment vs. code) [V-src S23]. |

- **Freshness knobs elsewhere:** SSSD `account_cache_expiration` [V S18]. Kanidm warns that a long `cache_timeout` "can delay account lockouts or group changes" [V S25]. Greengrass refreshes daily and on reconnect [V S30]. Entra CAE events propagate in up to 15 minutes [V S29].
- **Reconciliation:** IoT Edge replays stored messages in order and then reconciles properties [V S31]. A replica would do a full pull on reconnect and close local sessions of users who are now inactive or removed [I]. A pushed SCIM sync is started only by authentik (hourly or on change) [V S3].
- **Event replay to the IdP:** whether authentik accepts externally written events (login audit) through its API [GAP]. Without that, the replica keeps a local audit log [I].

## 5. Clock

Offline validation of expiry, delays and day counters needs trusted time. The Edge has an RTC; Patron's is unknown (brief). → 02.

## 6. "Node-limited" degraded sessions

- Every offline precedent is node-limited by construction. An SSSD, Windows, Kanidm, Duo or Greengrass offline credential is valid only on the machine that cached it [V S19, S21, S23, S30, S32].
- **Reduced scope:** a Windows cached logon gives the local desktop but no "network resources that require domain validation" [V S21]. This is the closest precedent to "valid for this node only".
- **Degraded policy:** Entra resilience defaults choose, per policy, between *block* and *use the evaluation from session start* for conditions it cannot evaluate. Those conditions include group and role membership, risk and location [V S28].
- No system was found that issues an explicitly reduced-*permission* token during an outage [GAP]. Treat it as [I] design space.

## 7. Proposals for 13a (not binding)

- **P1 — Pull is authoritative, push is the fast path.** The replica reconciles by polling the IdP admin API: on start, on reconnect, and every N minutes. It also takes an optional SCIM receiver (no PATCH, bulk or filter) for authentik push. This covers Keycloak (no outbound SCIM) and nodes the IdP cannot reach.
- **P2 — What the replica syncs:** user id, username, display name, active flag; groups and membership; role and parameter attributes (04); device public keys as a custom attribute. No passwords.
- **P3 — Offline credentials only after an online success on this node.** A PIN verifier or device key becomes usable offline only after an online login on that node, as in SSSD, Windows, Kanidm, Duo and Greengrass.
- **P4 — PIN protection:** an Argon2id verifier; a per-user failure counter written before verifying; delays like Apple's (after the 4th failure: 1, 5, 15, 60 min…). On TPM nodes, an HMAC_TPM key (Kanidm pattern). Never use the PIN as a TPM authValue on a network-facing login (global DA lockout).
- **P5 — "One-time local session" in numbers:** audience = this node only. Lifetime ≤ 12 h, not renewable offline (a new PIN or biometry each time). Allowed only if the last online auth on this node was ≤ 14 days ago (SSSD/Duo style). At most 5 PIN failures, then delays.
- **P6 — Local deny list:** a node-local "disabled" flag that wins over synced state until an admin clears it. On reconnect: full pull, close sessions of users who are now inactive, upload or keep the audit of offline logins.
- **P7 — Don't depend on authentik WebAuthn credentials for offline use.** RP ID binding and an API without public keys make them unusable from a replica. Use shell-app device keys registered at the replica (06).

## 8. Sources

- S1 — RFC 7644 SCIM Protocol: https://rfc-editor.org/rfc/rfc7644.html
- S2 — RFC 7643 SCIM Core Schema: https://datatracker.ietf.org/doc/html/rfc7643.html
- S3 — authentik docs 2026.8, SCIM provider: https://docs.goauthentik.io/add-secure-apps/providers/scim/
- S4 — authentik API, SCIMProviderRequest (2026.2.5): https://www.rubydoc.info/gems/authentik-api/2026.2.5/Authentik/Api/SCIMProviderRequest
- S5 — authentik commit 114eb79 (outgoing sync errors): https://github.com/goauthentik/authentik/commit/114eb79
- S6 — authentik docs, LDAP provider: https://docs.goauthentik.io/docs/providers/ldap
- S7 — authentik docs, notifications: https://docs.goauthentik.io/sys-mgmt/events/notifications/
- S8 — authentik docs, notification transports: https://docs.goauthentik.io/docs/sys-mgmt/events/transports
- S9 — authentik docs, M2M authentication: https://docs.goauthentik.io/add-secure-apps/providers/oauth2/machine_to_machine/
- S10 — authentik source, WebAuthnDevice model (mirror of main): https://git.sudo.is/mirrors/authentik/src/branch/main/authentik/stages/authenticator_webauthn/models.py
- S11 — authentik-client 2026.8.5, WebAuthnDevice: https://docs.rs/authentik-client/latest/src/authentik_client/models/web_authn_device.rs.html
- S12 — authentik discussion #26683 (RP ID): https://github.com/goauthentik/authentik/discussions/26683
- S13 — Keycloak blog, SCIM as experimental feature (2026-04): https://www.keycloak.org/2026/04/scim-as-experimental-feature
- S14 — Skycloak, Keycloak native SCIM 26.7 (secondary): https://skycloak.io/blog/keycloak-native-scim-api-preview-26-7/
- S15 — Keycloak, importing and exporting realms: https://www.keycloak.org/server/importExport
- S16 — Keycloak forum, secretData missing: https://keycloak.discourse.group/t/keycloak-rest-api-secretdata-missing/10530
- S17 — Keycloak discussion #25052 (export with credentials): https://www.github.com/keycloak/keycloak/discussions/25052
- S18 — sssd.conf(5) (Debian 2013; defaults matched against current Arch page https://man.archlinux.org/man/sssd.conf.5.uk.txt): https://unix.com/man-page/debian/5/sssd.conf/
- S19 — RHEL 7, SSSD provider options: https://docs.redhat.com/en/documentation/Red_Hat_Enterprise_Linux/7/html/System-Level_Authentication_Guide/sssd-configure-additional-provider-options
- S20 — Oracle Linux 10, Customizing SSSD: https://docs.oracle.com/en/operating-systems/oracle-linux/10/userauth/userauth-CustomizingSSSD.html
- S21 — Microsoft, Cached domain logon information: https://learn.microsoft.com/en-us/troubleshoot/windows-server/user-profiles-and-logon/cached-domain-logon-information
- S22 — Microsoft, Number of previous logons to cache: https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/security-policy-settings/interactive-logon-number-of-previous-logons-to-cache-in-case-domain-controller-is-not-available
- S23 — Kanidm source, unix resolver `idprovider/kanidm.rs`: https://kanidm.github.io/kanidm/stable/rustdoc/src/kanidm_unix_resolver/idprovider/kanidm.rs.html
- S24 — Kanidm design, unixd multi-resolver 2024: https://kanidm.github.io/kanidm/stable/developers/designs/unixd_multi_resolver_2024.html
- S25 — Kanidm book, PAM/NSS troubleshooting: https://kanidm.github.io/kanidm/stable/integrations/pam_and_nsswitch/troubleshooting.html
- S26 — Microsoft Entra backup authentication system: https://learn.microsoft.com/en-us/entra/architecture/backup-authentication-system
- S27 — Entra backup authentication, application support: https://learn.microsoft.com/de-de/entra/architecture/backup-authentication-system-apps
- S28 — Entra Conditional Access resilience defaults: https://docs.azure.cn/en-us/entra/identity/conditional-access/resilience-defaults
- S29 — Entra continuous access evaluation: https://docs.azure.cn/en-us/entra/identity/conditional-access/concept-continuous-access-evaluation
- S30 — AWS IoT Greengrass v2, offline authentication: https://docs.aws.amazon.com/greengrass/v2/developerguide/offline-authentication.md
- S31 — Azure IoT Edge 1.6, offline capabilities: https://learn.microsoft.com/azure/iot-edge/offline-capabilities
- S32 — Duo Authentication for Windows Logon (Offline Access): https://duo.com/docs/rdp
- S33 — Akamai MFA, offline authentication policy: https://techdocs.akamai.com/mfa/docs/offline-authentication-policy
- S34 — Home Assistant, auth API: https://contributors.home-assistant.io/core/internals/auth-api/
- S35 — Espressif, Matter security model: https://developer.espressif.com/blog/matter-security-model/
- S36 — RFC 9700 OAuth 2.0 Security BCP (BCP 240): https://www.rfc-editor.org/rfc/rfc9700.html
- S37 — Windows Hello for Business FAQ: https://learn.microsoft.com/en-us/windows/security/identity-protection/hello-for-business/faq
- S38 — Microsoft, TPM fundamentals: https://learn.microsoft.com/en-us/windows/security/hardware-security/tpm/tpm-fundamentals
- S39 — AOSP, Gatekeeper (doc source): https://android.googlesource.com/platform/docs/source.android.com/+/d206f4d/src/security/authentication/gatekeeper.jd
- S40 — AOSP, Weaver: https://source.android.com/docs/security/features/authentication/weaver
- S41 — Apple Platform Security, passcodes: https://support.apple.com/en-hk/guide/security/sec20230a10d/web
- S42 — tpm2_dictionarylockout(1): https://www.mankier.com/1/tpm2_dictionarylockout
- S43 — TPM 2.0 reference code DA.c (AOSP): https://android.googlesource.com/platform/external/tpm2/+/android-8.1.0_r11/DA.c
- S44 — W3C Web Authentication Level 3 (REC 2026-08-25): https://w3.org/TR/webauthn-3
- S45 — W3C WebAuthn, Related Origin Requests explainer: https://github.com/w3c/webauthn/wiki/Explainer:-Related-origin-requests/24bf9cc402bf9f21a57b9f87af3dc4a38b93f8f5
