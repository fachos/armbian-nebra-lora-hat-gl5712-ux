#!/usr/bin/env bash
# Enable SPI1 as /dev/spidev1.0 for the Nebra SX1301 HAT and require a reboot.
# Idempotent: safe to run twice.
set -euo pipefail
ENVFILE=/boot/armbianEnv.txt
[[ $EUID == 0 ]] || { echo "run as root" >&2; exit 1; }

cp -n "$ENVFILE" "$ENVFILE.bak.$(date +%s)"

python3 - "$ENVFILE" <<'PY'
import re, sys
from pathlib import Path
p = Path(sys.argv[1])
lines = p.read_text().splitlines()

wanted = {
    "overlay_prefix": "rockchip",
    "overlays": "rk3399-spi-spidev",
    "param_spidev_spi_bus": "1",
    "param_spidev_max_freq": "2000000",
}
out, seen = [], set()
for line in lines:
    key = line.split("=", 1)[0].strip()
    if key in wanted:
        if key in seen:            # drop duplicates, the last one wins in u-boot
            continue
        seen.add(key)
        out.append(f"{key}={wanted[key]}")
    else:
        out.append(line)
for key, val in wanted.items():
    if key not in seen:
        out.append(f"{key}={val}")
p.write_text("\n".join(out) + "\n")
print("armbianEnv.txt updated")
PY

grep -E "^(overlay_prefix|overlays|param_spidev)" "$ENVFILE"
echo
echo "Now reboot:  reboot"
echo "Then check:  ls -l /dev/spidev1.0"
