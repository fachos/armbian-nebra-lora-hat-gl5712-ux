#!/usr/bin/env bash
# Install everything the rest of this repo needs, then prove the imports work.
#
#   sudo bash gl5712-ux/scripts/packages.sh
#
# Why this exists as a script: one unknown package name aborts the whole apt
# transaction, so you get nothing at all -- not even the packages that do exist
# in your release. That is how `python3-spidev` silently never lands and the
# first probe dies with `ModuleNotFoundError: No module named 'spidev'`.
# The list is therefore checked per package before anything is installed.
set -euo pipefail

REQUIRED=(build-essential gpiod python3-libgpiod python3-spidev)
# git is deliberately not here: you needed it to clone this repo.
# only for scripts/make-pinout.py (diagram) and the JSON helpers -- never fatal
OPTIONAL=(python3-pil jq)
IMPORTS=('import spidev' 'from gpiod.line import Direction, Value')

log() { printf '\n== %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

[[ $EUID == 0 ]] || die "run as root: sudo $0"

log "0/3 this box"
# shellcheck disable=SC1091
. /etc/os-release
printf '  %s\n  kernel %s · %s · %s\n' \
	"${PRETTY_NAME:-unknown distro}" "$(uname -r)" "$(dpkg --print-architecture)" "$(uname -m)"

log "1/3 package availability"
missing=()
for p in "${REQUIRED[@]}"; do
	if apt-cache show "$p" >/dev/null 2>&1; then
		printf '  ok       %s\n' "$p"
	else
		printf '  MISSING  %s\n' "$p"
		missing+=("$p")
	fi
done
for p in "${OPTIONAL[@]}"; do
	if apt-cache show "$p" >/dev/null 2>&1; then
		printf '  ok       %s (optional)\n' "$p"
	else
		printf '  skip     %s (optional, not in this release)\n' "$p"
	fi
done
if ((${#missing[@]})); then
	die "not available in this release: ${missing[*]}
Armbian ships one release per image; if the names above are unknown you are on
an older or newer one. Check 'cat /etc/apt/sources.list.d/*.sources' points at
the release in /etc/os-release, run 'apt update', and retry."
fi

log "2/3 install"
apt-get update -qq
apt-get install -y --no-install-recommends "${REQUIRED[@]}"
for p in "${OPTIONAL[@]}"; do
	apt-get install -y --no-install-recommends "$p" >/dev/null 2>&1 || \
		printf '  note: %s not installed (optional)\n' "$p"
done

log "3/3 imports"
fail=0
for py in "${IMPORTS[@]}"; do
	if python3 -c "$py" 2>/dev/null; then
		printf '  ok       %s\n' "$py"
	else
		printf '  FAILED   %s\n' "$py"
		fail=1
	fi
done
if ((fail)); then
	die "packages are installed but the imports fail. Check which interpreter
'python3' resolves to -- '$(command -v python3)' must be /usr/bin/python3, not a
venv, conda or pyenv shim: those do not see apt-installed modules."
fi

printf '\nDone. Next: sudo bash gl5712-ux/scripts/armbian-spi.sh && sudo reboot\n'
