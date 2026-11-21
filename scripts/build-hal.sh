#!/usr/bin/env bash
# Build the Semtech SX1301 HAL for this board and run the calibration test.
#
#   sudo bash gl5712-ux/scripts/build-hal.sh [HAL_DIR] [-a FREQ_A] [-b FREQ_B] [-r 1257] [-n ITER]
#
#   HAL_DIR   default /opt/lora_gateway
#   FREQ_A/B  default 915.0 / 920.0 MHz, inside the 902-928 MHz front end of the
#             GL5712-UX module this repo covers. Any in-band pair works.
#   -r        radio type: 1257 (this HAT) or 1255
#   -n        calibration iterations, default 5
#
# Why the frequencies are not optional: `test_loragw_cal` exits with
# "ERROR: missing frequency input parameter" and prints its help text when -a/-b
# are absent, which reads like a broken build instead of a missing argument.
set -euo pipefail

HAL_DIR=
FREQ_A=915.0
FREQ_B=916.0
RADIO=1257
ITER=5
CAL_LOG=/tmp/nebra-test_loragw_cal.log

log() { printf '\n== %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
usage() {
	cat <<'EOF'
usage: sudo bash gl5712-ux/scripts/build-hal.sh [HAL_DIR] [-a FREQ_A] [-b FREQ_B] [-r 1257|1255] [-n ITER]

  HAL_DIR    HAL checkout, default /opt/lora_gateway
  -a FREQ_A  radio A calibration frequency in MHz (default 915.0)
  -b FREQ_B  radio B calibration frequency in MHz (default 916.0)
             both must sit inside 902-928 MHz, the GL5712-UX front end:
             US915 / AU915 / KR920 / AS923 all fit
  -r 1257    radio type: 1257 (this HAT) or 1255
  -n ITER    calibration iterations, default 5
EOF
}

while (($#)); do
	case $1 in
		-a|--freq-a)     [[ -n ${2:-} ]] || die "$1 needs a value (try -h)"; FREQ_A=$2; shift 2 ;;
		-b|--freq-b)     [[ -n ${2:-} ]] || die "$1 needs a value (try -h)"; FREQ_B=$2; shift 2 ;;
		-r|--radio)      [[ -n ${2:-} ]] || die "$1 needs a value (try -h)"; RADIO=$2;  shift 2 ;;
		-n|--iterations) [[ -n ${2:-} ]] || die "$1 needs a value (try -h)"; ITER=$2;   shift 2 ;;
		-h|--help)       usage; exit 0 ;;
		-*)              die "unknown option: $1 (try -h)" ;;
		*)               HAL_DIR=$1; shift ;;
	esac
done
HAL_DIR=${HAL_DIR:-/opt/lora_gateway}

[[ $EUID == 0 ]] || die "run as root (sudo $0)"
[[ $RADIO == 1255 || $RADIO == 1257 ]] || die "-r must be 1255 or 1257 (got $RADIO)"
[[ $FREQ_A =~ ^[0-9]+(\.[0-9]+)?$ ]] || die "-a must be a frequency in MHz (got $FREQ_A)"
[[ $FREQ_B =~ ^[0-9]+(\.[0-9]+)?$ ]] || die "-b must be a frequency in MHz (got $FREQ_B)"

# 902-928 MHz is the front end of the GL5712-UX this repo was tested on.
check_band() {
	awk -v f="$1" 'BEGIN{exit !(f >= 902 && f <= 928)}' && return 0
	printf 'warning: %s MHz is outside 902-928 MHz, the GL5712-UX front end.\n' "$1" >&2
	printf '         test_loragw_cal does not range-check the frequency: you get a poor\n' >&2
	printf '         calibration status, not an error.\n' >&2
}
check_band "$FREQ_A"
check_band "$FREQ_B"

log "1/5 source"
if [[ -d $HAL_DIR/.git ]]; then
	git -C "$HAL_DIR" fetch --quiet origin
	git -C "$HAL_DIR" reset --quiet --hard origin/master
else
	git clone --quiet https://github.com/Lora-net/lora_gateway.git "$HAL_DIR"
fi
git -C "$HAL_DIR" log --oneline -1

log "2/5 SPI device and speed for this HAT"
SPI_C="$HAL_DIR/libloragw/src/loragw_spi.native.c"
if grep -q '#define SPI_DEV_PATH    "/dev/spidev1.0"' "$SPI_C" &&
	grep -q '#define SPI_SPEED       2000000' "$SPI_C"; then
	printf '  already set for this HAT\n'
else
	sed -i 's|#define SPI_SPEED       8000000|#define SPI_SPEED       2000000|' "$SPI_C"
	sed -i 's|#define SPI_DEV_PATH    "/dev/spidev0.0"|#define SPI_DEV_PATH    "/dev/spidev1.0"|' "$SPI_C"
fi
grep -E '^#define SPI_(SPEED|DEV_PATH)' "$SPI_C"

log "3/5 build"
make -C "$HAL_DIR/libloragw" -B DEBUG_HAL=1 DEBUG_REG=1 \
	CFLAGS='-O2 -Wall -Wextra -std=c99 -fPIC -Iinc -I.'

log "4/5 register test"
cd "$HAL_DIR/libloragw"

./test_loragw_reg || die "register test failed — is POWER_EN held? The reset is a POWER_EN cycle, not a GPIO (docs/troubleshooting.md)"

log "5/5 calibration — radio A ${FREQ_A} MHz, radio B ${FREQ_B} MHz, SX${RADIO}, ${ITER} iterations"
./test_loragw_cal -a "$FREQ_A" -b "$FREQ_B" -r "$RADIO" -n "$ITER" 2>&1 | tee "$CAL_LOG"
cal_rc=${PIPESTATUS[0]}
printf '\n'

((cal_rc == 0)) || die "test_loragw_cal exited $cal_rc (log: $CAL_LOG)"

bit_names=("SX1301 registers reachable" "radio A registers reachable" \
	"radio B registers reachable" "radio A image rejection" \
	"radio B image rejection" "radio A TX imbalance" "radio B TX imbalance" \
	"calibration finished")

missing_bits() {	# status_mask
	local i out=
	for i in 0 1 2 3 4 5 6 7; do
		(((($2 >> i) & 1))) || continue
		((((1 << i) & $1))) || out+="${bit_names[i]}, "
	done
	out=${out%, }
	printf '%s' "${out:-none}"
}

# test_loragw_cal calibrates one radio per command, so each status line carries
# only that radio's bits: Rx A = 0x8F (143), Rx B = 0x97 (151). Both image
# rejection bits at once -- 0x9F (159) -- only happens inside lgw_start, which
# sends one calibration command for both radios.
RXA_MASK=$((0x80 | 0x01 | 0x02 | 0x04 | 0x08))	# 143
RXB_MASK=$((0x80 | 0x01 | 0x02 | 0x04 | 0x10))	# 151
rc=0

check_radio() {	# label mask
	local label=$1 mask=$2 n=0 bad=0 status rej minrej=999
	while read -r status rej; do
		n=$((n + 1))
		(((status & mask) == mask)) || {
			bad=$((bad + 1))
			printf 'FAIL: %s status %d (0x%02X) — missing: %s\n' \
				"$label" "$status" "$status" "$(missing_bits "$status" "$mask")"
		}
		((rej < minrej)) && minrej=$rej
	done < <(sed -n "s/^$label IQ mismatch:.*Rej: *\(-\?[0-9]*\) dB Status: *\([0-9]*\).*/\2 \1/p" "$CAL_LOG")
	if ((n == 0)); then
		printf 'FAIL: no "%s IQ mismatch" line in %s\n' "$label" "$CAL_LOG"
		rc=1
	elif ((bad)); then
		printf 'FAIL: %s had %d/%d calibration iterations below status 0x%02X\n' \
			"$label" "$bad" "$n" "$mask"
		rc=1
	else
		printf '  %s: %d/%d iterations at status 0x%02X, image rejection >= %d dB\n' \
			"$label" "$n" "$n" "$mask" "$minrej"
	fi
}

check_radio "Rx A" "$RXA_MASK"
check_radio "Rx B" "$RXB_MASK"
grep -q '^WARNING' "$CAL_LOG" && {
	printf 'FAIL: the calibration firmware raised warnings (see above)\n'; rc=1; }

if ((rc)); then
	printf '\nDocs: docs/troubleshooting.md — cold boot first, a warm reboot can latch the GL5712\n'
	exit 1
fi

cat <<EOF

Calibration OK — Rx A 143 (0x8F) and Rx B 151 (0x97), log: $CAL_LOG

  0x8F = 1000 1111  radio A pass   0x97 = 1001 0111  radio B pass
     bit0 SX1301 registers reachable    bit3 image rejection, radio A
     bit1 radio A registers reachable   bit4 image rejection, radio B
     bit2 radio B registers reachable   bit7 calibration finished
     bit5/6 TX imbalance (only with -t)

  0x9F (159) is the combined status lgw_start reads: it calibrates both radios
  in one command. test_loragw_cal cannot show it, one radio per command.


Next: lgw_start arms the IF chain; anything above that is your application.
EOF
