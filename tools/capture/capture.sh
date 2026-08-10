#!/usr/bin/env bash
# Golden capture from a stock EVOK 3.0.6 unit. Run as root, ON the unit, BEFORE
# anything replaces or removes EVOK. See docs/plan/capture-trip.md.
#
#   scp tools/capture/capture.sh root@<unit>:/tmp/
#   ssh root@<unit> 'bash /tmp/capture.sh'
#   scp root@<unit>:/tmp/evok-capture-*.tar.gz ./
#
# Read-only, with one opt-in exception: CAPTURE_WRITES=1 adds section 6e, two deliberate
# writes (a ULED set, and an out-of-range value) that capture the write-side success and
# error envelopes. Those envelopes are part of the compatibility contract and are as
# unrecoverable as the read transcripts, but a write is a write — so it is opt-in.
#
# It never touches /etc, never restarts a service, and never writes to an RS-485 bus.

set -uo pipefail   # deliberately not -e: a missing tool must not abort the run

BASE="${EVOK_BASE:-http://127.0.0.1:8080}"
NGINX_BASE="${NGINX_BASE:-http://127.0.0.1:80}"
CAPTURE_WRITES="${CAPTURE_WRITES:-0}"
HOST="$(hostname)"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="/tmp/evok-capture-${HOST}-${STAMP}"
LOG="${OUT}/capture.log"

mkdir -p "$OUT"/{inventory,packaging,config,firmware,api,baseline}
exec > >(tee -a "$LOG") 2>&1

say()  { printf '\n=== %s\n' "$*"; }
note() { printf '  · %s\n' "$*"; }
run()  { # run <outfile> <cmd...> — record stdout+stderr+exit code, never abort
  local f="$1"; shift
  { printf '$ %s\n' "$*"; "$@" 2>&1; printf '\n[exit %s]\n' "$?"; } >"$f"
}
copy() { # copy <src> <destdir> — preserve, tolerate absence
  if [ -e "$1" ]; then cp -a "$1" "$2/" && note "copied $1"
  else note "MISSING $1"; echo "$1" >>"${OUT}/missing.txt"; fi
}

printf 'evok-node golden capture\nhost=%s\nutc=%s\nbase=%s\n' "$HOST" "$STAMP" "$BASE"

# ---------------------------------------------------------------- 1. guard rails
say "1. Guard check — is this still a stock EVOK unit?"
STOCK=yes
dpkg -l evok >/dev/null 2>&1 || { note "WARNING: evok is not installed"; STOCK=no; }
[ -d /etc/evok ]                || { note "WARNING: /etc/evok is gone";     STOCK=no; }
[ -f /var/lib/evok/alias.yaml ] || note "note: /var/lib/evok/alias.yaml absent (no aliases ever set?)"
if [ "$STOCK" = no ]; then
  note "This unit is NOT stock. Capture what is left, but flag it in the PR body."
fi
run "${OUT}/inventory/evok-version.txt" curl -sS --max-time 5 "${BASE}/version"
grep -q 'v3\.0\.6' "${OUT}/inventory/evok-version.txt" \
  || note "WARNING: /version is not v3.0.6 — record the actual string in the PR body"

# ---------------------------------------------------------------- 2. identity
say "2. Unit identity and OS"
run "${OUT}/inventory/os-release.txt"   cat /etc/os-release
run "${OUT}/inventory/uname.txt"        uname -a
run "${OUT}/inventory/hostname.txt"     hostnamectl
run "${OUT}/inventory/unipiid.txt"      unipiid
# `unipiid -d` is what populates /run/unipi-plc/unipi-id/. Only run it if the tree is
# absent — it is the documented invocation, but we are here to observe, not to provision.
if [ ! -d /run/unipi-plc/unipi-id ]; then
  note "/run/unipi-plc/unipi-id absent — running documented 'unipiid -d' to populate it"
  run "${OUT}/inventory/unipiid-d.txt" unipiid -d
fi
# Debian 12 fallback chain (ADR/research 05 §8.1) — capture both paths on every unit so
# the provider chain can be tested against real data even where unipiid exists.
run "${OUT}/inventory/run-unipi-plc.txt" find /run/unipi-plc -maxdepth 4 -printf '%y %p\n'
for f in /run/unipi-plc/unipi-id/*; do
  [ -f "$f" ] && printf -- '--- %s\n%s\n' "$f" "$(cat "$f" 2>&1)" \
    >>"${OUT}/inventory/unipi-id-files.txt"
done
for g in /run/unipi-plc/by-sys/iogroup*; do
  [ -d "$g" ] || continue
  for k in sys_board_name sys_board_serial firmware_version \
           master_watchdog_enable master_watchdog_timeout was_watchdog ow_power_off; do
    [ -r "$g/$k" ] && printf '%s/%s = %s\n' "$g" "$k" "$(cat "$g/$k" 2>&1)" \
      >>"${OUT}/inventory/sysfs-boards.txt"
  done
done
# ow_power_off is Debian ≤12 only; its absence on 13 is itself the fact worth recording.
[ -e /run/unipi-plc/by-sys/iogroup1/ow_power_off ] \
  || note "no iogroup*/ow_power_off (expected on Debian 13 — 1-Wire disable is coil-only)"
run "${OUT}/inventory/sysfs-by-sys.txt"  find /run/unipi-plc/by-sys -maxdepth 3 -printf '%y %p\n'
run "${OUT}/inventory/tty.txt"           bash -c 'ls -l /dev/ttyNS* /dev/extcomm/* 2>&1'
run "${OUT}/inventory/i2c.txt"           bash -c 'ls -l /sys/bus/i2c/devices/ 2>&1'
run "${OUT}/inventory/w1.txt"            bash -c 'ls -l /sys/bus/w1/devices/ 2>&1'
run "${OUT}/inventory/lsmod.txt"         lsmod

# ---------------------------------------------------------------- 3. packaging
say "3. Packaging metadata — the ADR-0002 Conflicts:/Depends: input"
run "${OUT}/packaging/apt-cache-show-evok.txt"   apt-cache show evok
run "${OUT}/packaging/apt-cache-policy-evok.txt" apt-cache policy evok
run "${OUT}/packaging/apt-cache-depends.txt"     apt-cache depends --recurse --no-recommends \
                                                   --no-suggests --no-conflicts --no-breaks \
                                                   --no-replaces --no-enhances evok
run "${OUT}/packaging/dpkg-L-evok.txt"           dpkg -L evok
run "${OUT}/packaging/dpkg-s-evok.txt"           dpkg -s evok
run "${OUT}/packaging/dpkg-l-unipi.txt"          bash -c "dpkg -l | grep -Ei 'unipi|evok'"
run "${OUT}/packaging/apt-mark-manual.txt"       apt-mark showmanual
run "${OUT}/packaging/dpkg-conffiles.txt"        bash -c "dpkg-query -W -f='\${Conffiles}\n' evok"
run "${OUT}/packaging/systemd-units.txt"         bash -c \
  "systemctl list-unit-files | grep -Ei 'evok|unipi'"
run "${OUT}/packaging/systemd-status.txt"        bash -c \
  "systemctl status --no-pager evok unipitcp nginx 2>&1"
for u in evok unipitcp; do
  run "${OUT}/packaging/systemd-cat-${u}.txt"    systemctl cat "$u"
done
run "${OUT}/packaging/ports.txt"                 bash -c "ss -lntp 2>&1 || netstat -lntp 2>&1"
# nginx: the :80 site conflict in ADR-0002
copy /etc/nginx/sites-available/evok "${OUT}/packaging"
run "${OUT}/packaging/nginx-sites-enabled.txt"   ls -l /etc/nginx/sites-enabled/
run "${OUT}/packaging/nginx-T.txt"               nginx -T
run "${OUT}/packaging/nginx-version.txt"         nginx -v

# ---------------------------------------------------------------- 4. config + state
say "4. Stock config and alias file — the migration tool's golden fixtures (ADR-0003)"
copy /etc/evok/config.yaml                  "${OUT}/config"
copy /etc/evok/autogen.yaml                 "${OUT}/config"
copy /etc/evok/hw_definitions               "${OUT}/config"
copy /var/lib/evok/alias.yaml               "${OUT}/config"
copy /etc/default/unipitcp                  "${OUT}/config"
copy /etc/unipi-one-modbus.d                "${OUT}/config"
run "${OUT}/config/etc-evok-tree.txt"       find /etc/evok -printf '%M %n %u %g %10s %TY-%Tm-%Td %p\n'
run "${OUT}/config/var-lib-evok-tree.txt"   find /var/lib/evok -printf '%M %n %u %g %10s %TY-%Tm-%Td %p\n'
# alias.yaml `version:` decides whether the file is parsed at all: 1.0 (list shape) and 2.0
# (map shape) both load, quoted or not, but ANY other or missing value yields {} silently.
# Record the raw bytes, not a re-serialised copy — quoting is part of the evidence.
[ -f /var/lib/evok/alias.yaml ] && \
  run "${OUT}/config/alias-yaml-raw.txt" bash -c "head -c 4096 /var/lib/evok/alias.yaml | od -c | head -40"

# ---------------------------------------------------------------- 5. firmware
say "5. Board firmware per section (FW 5.x may not match the register maps at all)"
FWSPI=/opt/unipi/tools/fwspi
[ -x "$FWSPI" ] || FWSPI="$(command -v fwspi 2>/dev/null)"
if [ -n "${FWSPI:-}" ] && [ -x "$FWSPI" ]; then
  for u in 1 2 3; do   # -u is the board Modbus address == section number
    run "${OUT}/firmware/fwspi-u${u}.txt" "$FWSPI" -u "$u"
  done
else
  note "MISSING fwspi (/opt/unipi/tools/fwspi, package unipi-firmware6)"
  echo "fwspi" >>"${OUT}/missing.txt"
fi
run "${OUT}/firmware/tools-dir.txt" bash -c 'ls -l /opt/unipi/tools/ 2>&1'
run "${OUT}/firmware/rs485-ttys.txt" bash -c 'ls -l /run/unipi-plc/by-sys/rs485-*/tty 2>&1'
# DELIBERATELY NOT RUN: fwserial against an extension. It requires exclusive use of the
# port and uninterrupted power, and violating either bricks the extension — and EVOK holds
# the tty while it runs. Extension firmware is read by hand in runbook phase 6, with evok
# stopped. Do not "just try it" here.
#
# Cross-check the identity registers through the API where they are cached: 1000 Firmware
# Version, 1003 Firmware ID, 1004 Hardware ID, 1001/1002 the I/O census, 1005/1006 serial.
# NOTE: /rest/register only serves addresses a definition actually declares and the scan
# loop has already read — anything else raises ENoCacheRegister. Misses are expected and
# are themselves worth recording, since they map EVOK's real register bands.
for u in 1 2 3; do
  run "${OUT}/firmware/registers-u${u}.txt" bash -c \
    "for r in 1000 1001 1002 1003 1004 1005 1006 1007; do
       printf '%s: ' \"\$r\"
       curl -sS --max-time 5 '${BASE}/rest/register/${u}_'\"\$r\"
       echo
     done"
done

# ---------------------------------------------------------------- 6. API transcripts
say "6. Golden API transcripts"
TYPES="di ro do ai ao sensor led watchdog modbus_slave owpower register data_point owbus device_info"
# Types deliberately excluded from /rest/all — capture them anyway, they are reachable
# directly and the exclusion itself is part of the contract.
EXTRA_TYPES="nv_save run board tcp_bus serial_bus ds2408"

get() { # get <path> <name>  — body + response headers, both are contract
  local path="$1" name="$2"
  curl -sS --max-time 20 -D "${OUT}/api/${name}.headers" \
       -o "${OUT}/api/${name}.json" "${BASE}${path}"
  printf 'GET %s -> %s\n' "$path" "${name}.json" >>"${OUT}/api/index.txt"
}

get /version               version
get /rest/all              rest_all
get /json/all              json_all
for t in $TYPES $EXTRA_TYPES; do
  get "/rest/${t}/all"     "rest_${t}_all"
  get "/json/${t}/all"     "json_${t}_all"
done
# Single-circuit and single-prop GETs, on the first real circuit of each type.
python3 - "$OUT" "$BASE" <<'PY' >>"${OUT}/api/index.txt" 2>&1
import json, os, subprocess, sys, urllib.request
out, base = sys.argv[1], sys.argv[2]
for t in "di ro do ai ao sensor led watchdog register data_point device_info".split():
    p = os.path.join(out, "api", f"rest_{t}_all.json")
    try:
        items = json.load(open(p))
    except Exception:
        continue
    if not isinstance(items, list) or not items:
        continue
    circuit = items[0].get("circuit")
    if circuit is None:
        continue
    for path, name in (
        (f"/rest/{t}/{circuit}", f"rest_{t}_one"),
        (f"/json/{t}/{circuit}", f"json_{t}_one"),
        (f"/rest/{t}/{circuit}/value", f"rest_{t}_one_value"),
        # research/07 req 17: /json/<dev>/<circuit>/value is the only path one real client
        # uses. Capture the /json variant separately — do not assume it mirrors /rest.
        (f"/json/{t}/{circuit}/value", f"json_{t}_one_value"),
        (f"/rest/{t}/all/value", f"rest_{t}_all_value"),
    ):
        try:
            with urllib.request.urlopen(base + path, timeout=20) as r:
                body, hdrs = r.read(), str(r.headers)
        except Exception as e:
            body, hdrs = f"ERROR {e}".encode(), ""
        open(os.path.join(out, "api", name + ".json"), "wb").write(body)
        if hdrs:
            open(os.path.join(out, "api", name + ".headers"), "w").write(hdrs)
        print(f"GET {path} -> {name}.json")
PY

# Error and CORS shapes — real clients depend on these.
say "6b. Error, OPTIONS and CORS shapes"
err() { # err <name> <path> — full response including status line and headers
  curl -sS --max-time 10 -i "${BASE}$2" >"${OUT}/api/err_$1.txt" 2>&1
}
err not_found_circuit /rest/di/nope
err not_found_type    /rest/nosuchtype/all
err prop_underscore   /rest/di/1_01/_private
err rest_bare         /rest/
err rest_type_only    /rest/di          # there is no /rest/di route — 404, not "all circuits"
err trailing_slash    /rest/all/

# Alt-names: accepted in URLs, but payloads always carry the canonical `dev` — except
# 1-Wire, which emits `dev: "temp"`. research/07 reqs 15 and 20 make the whole table
# load-bearing, so capture every alias, not a sample.
for a in digitalinput input digitaloutput output relay analoginput analogoutput temp; do
  get "/rest/${a}/all" "altname_rest_${a}_all"
  get "/json/${a}/all" "altname_json_${a}_all"
done
curl -sS --max-time 10 -i -X OPTIONS "${BASE}/rest/all" >"${OUT}/api/options_rest_all.txt" 2>&1
curl -sS --max-time 10 -i -H 'Origin: http://example.invalid' "${BASE}/rest/all" \
  >"${OUT}/api/cors_rest_all.txt" 2>&1

# Same requests through nginx on :80 — the only path ha-unipi-neuron and evok-ws-client
# can use, so the proxy's behaviour is part of the contract too.
say "6c. Through nginx on :80"
for p in /version /rest/all /json/all; do
  n="nginx$(echo "$p" | tr '/' '_')"
  curl -sS --max-time 20 -i "${NGINX_BASE}${p}" >"${OUT}/api/${n}.txt" 2>&1
done

# Bulk and JSON-RPC. Read-only calls only — no writes on the trip.
say "6d. Bulk and JSON-RPC"
python3 - "$OUT" "$BASE" <<'PY'
import json, os, sys, urllib.request
out, base = sys.argv[1], sys.argv[2]
def post(path, payload, name, ctype="application/json"):
    body = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
    req = urllib.request.Request(base + path, data=body,
                                 headers={"Content-Type": ctype})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            data, code, hdrs = r.read(), r.status, str(r.headers)
    except urllib.error.HTTPError as e:
        data, code, hdrs = e.read(), e.code, str(e.headers)
    except Exception as e:
        data, code, hdrs = f"ERROR {e}".encode(), 0, ""
    open(os.path.join(out, "api", name + ".txt"), "wb").write(
        f"POST {path} HTTP {code}\n{hdrs}\n".encode() + data)
    print(name, code)

di = None
try:
    items = json.load(open(os.path.join(out, "api", "rest_di_all.json")))
    di = items[0]["circuit"]
except Exception:
    pass

# group_queries / group_assignments are expected to fail in 3.0.6 (map not JSON
# serialisable). Capture the failure envelope verbatim — we need to know what it says.
if di:
    post("/bulk", {"group_queries": [{"device_types": ["di"], "group": 1,
                                      "device_circuits": [di]}]}, "bulk_group_queries")
    post("/rpc", {"jsonrpc": "2.0", "id": 1, "method": "input_get",
                  "params": [di]}, "rpc_input_get")
    post("/rpc", {"jsonrpc": "2.0", "id": 2, "method": "input_get_value",
                  "params": {"circuit": di}}, "rpc_input_get_value_named")
# Wrong names the published docs demonstrate but 3.0.6 does not define.
post("/rpc", {"jsonrpc": "2.0", "id": 3, "method": "di_get", "params": ["1_01"]},
     "rpc_di_get_undefined")
post("/rpc", {"jsonrpc": "2.0", "id": 4, "method": "input_get", "params": ["nope"]},
     "rpc_device_not_found")
post("/bulk", {}, "bulk_empty")
PY

# ------------------------------------------------------- 6e. write envelopes (opt-in)
# The success shape AND the error shape {"success":false,"errors":{"<PyExceptionClass>":…}}
# are both part of the contract — the exception *class name* leaks into the payload, and
# research/07 req 16 has clients keying off both the `success` field and the HTTP status.
# Neither is recoverable once EVOK is gone, and neither can be captured without writing.
#
# The two writes chosen are the least invasive available: a ULED (a status light) and a
# deliberately out-of-range value that must be rejected. No relay, no analog output.
if [ "$CAPTURE_WRITES" = 1 ]; then
  say "6e. Write envelopes — WRITING (CAPTURE_WRITES=1)"
  python3 - "$OUT" "$BASE" <<'PY'
import json, os, sys, urllib.parse, urllib.request
out, base = sys.argv[1], sys.argv[2]

def send(path, data, name, ctype):
    req = urllib.request.Request(base + path, data=data, method="POST",
                                 headers={"Content-Type": ctype})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            body, code, hdrs = r.read(), r.status, str(r.headers)
    except urllib.error.HTTPError as e:
        body, code, hdrs = e.read(), e.code, str(e.headers)
    except Exception as e:
        body, code, hdrs = f"ERROR {e}".encode(), 0, ""
    open(os.path.join(out, "api", name + ".txt"), "wb").write(
        f"POST {path} HTTP {code}\n{hdrs}\n".encode() + body)
    print(name, code)

def first(t):
    try:
        items = json.load(open(os.path.join(out, "api", f"rest_{t}_all.json")))
        return items[0]["circuit"]
    except Exception:
        return None

led = first("led")
if led:
    # /rest POST bodies are form-encoded; /json POST bodies are JSON. Both shapes matter.
    for value in ("1", "0"):
        send(f"/rest/led/{led}", urllib.parse.urlencode({"value": value}).encode(),
             f"write_rest_led_{value}", "application/x-www-form-urlencoded")
    send(f"/json/led/{led}", json.dumps({"value": 0}).encode(),
         "write_json_led_0", "application/json")
    # Rejected write — this is the envelope we actually cannot get any other way.
    send(f"/rest/led/{led}", urllib.parse.urlencode({"value": "banana"}).encode(),
         "write_rest_led_invalid", "application/x-www-form-urlencoded")
else:
    print("no led circuit found — write envelopes not captured")

# Non-existent circuit: the 404 error envelope, no hardware touched at all.
send("/rest/led/nope", urllib.parse.urlencode({"value": "1"}).encode(),
     "write_rest_not_found", "application/x-www-form-urlencoded")
# Bulk individual_assignments is the only bulk key that works in 3.0.6.
if led:
    send("/bulk", json.dumps({"individual_assignments": [
             {"device_type": "led", "device_circuit": led,
              "assigned_values": {"value": 0}}]}).encode(),
         "write_bulk_individual", "application/json")
PY
else
  note "write envelopes skipped — re-run with CAPTURE_WRITES=1 to capture them"
  note "(they need a write, they are contract, and they are unrecoverable later)"
fi

# ---------------------------------------------------------------- 7. baseline
say "7. Baseline measurements of stock EVOK"
run "${OUT}/baseline/uptime.txt"    uptime
run "${OUT}/baseline/meminfo.txt"   cat /proc/meminfo
run "${OUT}/baseline/cpuinfo.txt"   cat /proc/cpuinfo
note "idle CPU over 60 s (leave the unit alone now)"
run "${OUT}/baseline/top-60s.txt"   bash -c \
  "top -b -n 12 -d 5 | grep -E 'Cpu|evok|python|unipitcp' "
run "${OUT}/baseline/pidstat.txt"   bash -c \
  "pidstat -p \$(systemctl show -p MainPID --value evok) 5 12 2>&1"
note "p99 latency of GET /rest/all, 200 samples"
run "${OUT}/baseline/latency-rest-all.txt" bash -c "
  for i in \$(seq 1 200); do
    curl -sS -o /dev/null -w '%{time_total}\n' --max-time 10 '${BASE}/rest/all'
  done | sort -n | awk '{a[NR]=\$1} END {
    printf \"n=%d min=%.4f p50=%.4f p95=%.4f p99=%.4f max=%.4f\n\",
      NR, a[1], a[int(NR*0.50)], a[int(NR*0.95)], a[int(NR*0.99)], a[NR]}'"
note "p99 latency of a single-circuit GET, 200 samples"
run "${OUT}/baseline/latency-one.txt" bash -c "
  C=\$(python3 -c \"import json;print(json.load(open('${OUT}/api/rest_di_all.json'))[0]['circuit'])\" 2>/dev/null)
  [ -z \"\$C\" ] && exit 0
  for i in \$(seq 1 200); do
    curl -sS -o /dev/null -w '%{time_total}\n' --max-time 10 '${BASE}/rest/di/'\"\$C\"
  done | sort -n | awk '{a[NR]=\$1} END {
    printf \"n=%d p50=%.4f p95=%.4f p99=%.4f max=%.4f\n\",
      NR, a[int(NR*0.50)], a[int(NR*0.95)], a[int(NR*0.99)], a[NR]}'"
run "${OUT}/baseline/journal-evok.txt" bash -c \
  "journalctl -u evok --no-pager -n 2000"
run "${OUT}/baseline/journal-boot.txt" bash -c \
  "journalctl -b --no-pager | tail -2000"

# ---------------------------------------------------------------- 8. storage wear
# The documented host-side counters live in /run/unipi_stats/, not in a Modbus register the
# API exposes — EVOK's register bands stop well short of 4000. Informational: the eMMC is
# not replaceable, and CI write churn is what wears it.
say "8. Storage wear counters — informational"
run "${OUT}/baseline/unipi-stats.txt" bash -c \
  'for f in /run/unipi_stats/*; do
     [ -f "$f" ] && printf "%s = %s\n" "$f" "$(cat "$f" 2>&1)"
   done'
run "${OUT}/baseline/blockdev.txt" bash -c 'lsblk -o NAME,SIZE,TYPE,MOUNTPOINT 2>&1; df -h 2>&1'

# ---------------------------------------------------------------- pack
say "Packing"
printf 'host=%s\nutc=%s\nstock=%s\nbase=%s\n' "$HOST" "$STAMP" "$STOCK" "$BASE" \
  >"${OUT}/MANIFEST.txt"
find "$OUT" -type f -printf '%10s %P\n' | sort -k2 >>"${OUT}/MANIFEST.txt"
[ -f "${OUT}/missing.txt" ] && { echo; echo "MISSING:"; cat "${OUT}/missing.txt"; }
tar czf "${OUT}.tar.gz" -C /tmp "$(basename "$OUT")"
echo
echo "Done. Copy this off the unit:"
ls -l "${OUT}.tar.gz"
echo
echo "Still to do by hand on this unit (see docs/plan/capture-trip.md):"
echo "  · WS transcripts            → phase 3, tools/capture/capture-events.py"
echo "  · webhook capture           → phase 4, edits config.yaml, restores it"
echo "  · cold-start null payloads  → phase 4, one curl in the first second after restart"
echo "  · start_index baseline      → phase 5, L527 only, section 3"
echo "  · extension + register reads → phase 6, needs evok stopped"
[ "$CAPTURE_WRITES" = 1 ] || \
  echo "  · write envelopes          → re-run this script with CAPTURE_WRITES=1"
