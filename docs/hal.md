# Build the Semtech HAL, calibrate, receive

Covers **steps 4 and 5** of the main procedure: register test, calibration, then the
loopback proof that the radios receive.

The HAL is the reference implementation of the SX1301 interface: register access,
RF chain configuration, AGC firmware download, and calibration. Building it gives
you `test_loragw_reg`, `test_loragw_cal` and `test_loragw_hal` — the three commands
that prove the hardware works, in that order.

Nothing here is specific to any application on top — it is the radio layer.
Everything in sections 1–5 is one command:

```bash
sudo bash gl5712-ux/scripts/build-hal.sh /opt/lora_gateway
```

The sections exist so you know what that command did and what its numbers mean.

## 1. Get the source

```bash
git clone https://github.com/Lora-net/lora_gateway.git /opt/lora_gateway
```

The script resets an existing checkout to `origin/master` instead of cloning twice.

## 2. Patch SPI for this board

Two defines in `libloragw/src/loragw_spi.native.c`:

```c
#define SPI_SPEED       2000000
#define SPI_DEV_PATH    "/dev/spidev1.0"
```

`build-hal.sh` sets both defines with two `sed` calls right after it refreshes the
checkout. By hand:

```bash
sed -i 's|#define SPI_SPEED       8000000|#define SPI_SPEED       2000000|' \
	/opt/lora_gateway/libloragw/src/loragw_spi.native.c
sed -i 's|#define SPI_DEV_PATH    "/dev/spidev0.0"|#define SPI_DEV_PATH    "/dev/spidev1.0"|' \
	/opt/lora_gateway/libloragw/src/loragw_spi.native.c
```

Why 2 MHz: the HAT keeps a stub trace where an SPI NOR flash used to be. At the
default 8 MHz, writes corrupt silently and calibration reports a status that
looks like a hardware fault. 2 MHz is slower and correct.

## 3. Build

```bash
make -C /opt/lora_gateway/libloragw -B DEBUG_HAL=1 DEBUG_REG=1 \
	CFLAGS='-O2 -Wall -Wextra -std=c99 -fPIC -Iinc -I.'
```

## 4. Register test

```bash
cd /opt/lora_gateway/libloragw
sudo ./test_loragw_reg
```

Five known-value checks, each printing what it read and what it expected — the two
numbers must be equal on every line, and the run ends with `End of test for
loragw_reg.c`:

```
IMPLICIT_PAYLOAD_LENGHT = 197 (should be 197)
FRAME_SYNCH_PEAK2_POS = 11 (should be 11)
PREAMBLE_SYMB1_NB = 49253 (should be 49253)
ADJUST_MODEM_START_OFFSET_SF12_RDX4 = 3173 (should be 3173)
IF_FREQ_1 = -1947 (should be -1947)
End of test for loragw_reg.c
```

If every register returns the same value (`0x66`, or `0x67` everywhere) the chip is
in reset or unpowered — go to
[troubleshooting.md](troubleshooting.md#every-register-reads-0x66). The last
part of the test writes a 256-byte LFSR burst into the TX buffer and reads the RX
buffer back; those are different registers, so that step cannot be checked in
software — the source says to use a logic analyser. Treat the five lines above as
the pass condition.

`build-hal.sh` re-binds the spidev driver before it touches the bus; without that,
the first register test after a boot fails and only the second run passes. By hand,
the same two lines come first:

```bash
sudo sh -c 'echo spi1.0 > /sys/bus/spi/drivers/spidev/unbind; sleep 1; echo spi1.0 > /sys/bus/spi/drivers/spidev/bind'
```

## 5. Calibration

`test_loragw_cal` **requires both RX frequencies**. Run bare, it exits with
`ERROR: missing frequency input parameter` and dumps its help text — which reads
like a broken build but is only a missing argument. The script passes them:

```bash
sudo bash gl5712-ux/scripts/build-hal.sh /opt/lora_gateway                     # 915 unit: -a 915.0 -b 916.0
sudo bash gl5712-ux/scripts/build-hal.sh /opt/lora_gateway -a 923.2 -b 923.4   # AS923-1 unit
```

By hand, same thing:

```bash
cd /opt/lora_gateway/libloragw
./test_loragw_cal -a 915.0 -b 916.0 -r 1257 -n 5
```

**Which frequencies?** Any frequency inside the 902–928 MHz front end of the
GL5712-UX. That is why the defaults are 915/916 and why US915, AU915, KR920 and
AS923 all fit. The two numbers only tune SX1257 #0 to `-a` and #1 to `-b` before the
AGC firmware measures IQ mismatch at that LO; they do not set a channel plan, and
nothing downstream inherits them. If you want the figure to represent the sub-band
each radio actually serves, calibrate at its middle (radio A on 902.3–914.9 and
radio B on 915.5–927.5 → `-a 908 -b 921`). Otherwise any in-band pair is a valid
health check.

The values are not sanity-checked: `test_loragw_cal` ignores the return of
`lgw_setup_sx125x`, so a frequency the radio cannot tune shows up as a poor status
rather than an error. Stay in band.

The calibration your gateway actually runs is separate: `lgw_start` tunes each
chain to the frequency in your config and reports its own combined status.

Success is a status of **143 (`0x8F`) on the Rx A lines and 151 (`0x97`) on the
Rx B lines**, with no `WARNING:` lines. The two numbers differ because
`test_loragw_cal` sends **one calibration command per radio**, and the status
register only reports the bits of the command just run — an Rx A pass cannot set
bit 4 (radio B image rejection) and vice versa:

```
Rx A IQ mismatch: Amp:  -8 Phi:   9 Rej: 52 dB Status: 143 | Debug: ...
Rx B IQ mismatch: Amp: -11 Phi:   7 Rej: 63 dB Status: 151 | Debug: ...
```

```
  0x8F = 1000 1111        0x97 = 1001 0111
     bit0 SX1301 registers reachable
     bit1 radio A registers reachable
     bit2 radio B registers reachable
     bit3 radio A image rejection converged    <- set in 0x8F
     bit4 radio B image rejection converged    <- set in 0x97
     bit7 calibration finished
     bit5/6 TX imbalance, only with -t
```

`0x9F` (159) is the *combined* status — both image-rejection bits at once. You see
it only in `lgw_start`, which calibrates both radios in a single command. If a
`test_loragw_cal` line ever shows `0x9F`, that is not the calibration working
better; it is a status read from the wrong command.

A status of `0` with the SPI working usually means the 32 MHz TCXO has not
settled (cold boot), or the SPI speed is still too high.

## 6. What you can do next

With calibration passing, the board is a working SX1301 concentrator: `lgw_start`
arms the IF chain and `lgw_receive` returns packets with RSSI and SNR. Anything
built on top of that is your choice of application.

To prove the receive path before installing a gateway, run the HAL test — it sets
up eight LoRa channels around the two radio frequencies, starts the concentrator
and prints every packet it hears:

```bash
cd /opt/lora_gateway/libloragw
sudo ./test_loragw_hal -a 915.0 -b 916.0 -t 916.0 -r 1257
```

All three frequencies are mandatory: the argument check rejects `ft == 0` with
`ERROR: missing frequency input parameter`. `-t` is stored at startup and used by the
test's own transmit loop further down, so it cannot be dropped. Give it any in-band
frequency.

Note the two binaries: `test_loragw_cal` (step 4) only calibrates and never transmits;
`test_loragw_hal` (this step) transmits periodically and prints what it hears back.

The checkpoint is right at the start — the first line only appears because the HAL
was built with `DEBUG_HAL=1`, as `build-hal.sh` does:

```
Note: calibration finished (status = 159)     <- or 191 (0xBF); see below
*** Concentrator started ***
```

This test enables TX on radio A, so the calibration word also covers the TX
DC-offset path: `159` (0x9F) is RX only, `191` (0xBF) means that TX calibration ran
too. Both are healthy — `lgw_start` only rejects a status missing bit0 or bit7.

After that it runs a **closed loop**: every 16th receive poll — about 4.8 s — it
transmits `TX.TEST.LORA.GW.` plus a 32-bit counter (20 bytes, SF9, 125 kHz, CR 4/5)
on radio A at `-t`, then prints the frame it hears back:

```
+++
Sending packet #0, rf path 0, return 0
status -> 4:2:
TX finished
Rcv pkt #1 >> if_chain: 2 tstamp:0007583812 size: 20 LoRa SF9 CR1(4/5)
 RSSI: +52.0 SNR: +4.2 (min: +0.2, max: +6.8) payload:
 54 58 2E 54 45 53 54 2E 4C 4F 52 41 2E 47 57 2E 00 00 00 00 #
```

The payload is `TX.TEST.LORA.GW.` followed by the counter (`00 00 00 01`, `…02`), so
the incrementing sequence proves these are its own frames, not a neighbour's. RSSI
around +52 dBm is that self-reception at point-blank, not a far node. One packet per
~4.8 s means about 12-13 in a 60 s window — so silence here *is* a failure, unlike a
bare listen. What this proves is the whole chain: TX scheduling, the PA, the receive
path, demodulation and CRC. What it cannot prove is antenna gain or weak-signal
sensitivity — that needs a real node across the room, or the gateway itself.

`*** Impossible to start concentrator ***` is the error to chase, and only one
process may hold `/dev/spidev1.0`, so a gateway service and this test cannot run at
the same time.

The loop never stops on its own and prints one block per packet, so give it a fixed
window and count afterwards:

```bash
sudo timeout 60 ./test_loragw_hal -a 915.0 -b 916.0 -t 916.0 -r 1257 \
	> /tmp/nebra-rx.log 2>&1          # exit 124 = the timeout, not a failure
grep -c 'Rcv pkt' /tmp/nebra-rx.log   # >0: the radios hear LoRa traffic
grep -A5 'Rcv pkt' /tmp/nebra-rx.log | head -30   # RSSI/SNR + payload hex
```

A packet block ends with `RSSI:` / `SNR:` and the payload in hex, so a non-zero
count proves the whole receive path — SPI, IF chain, demodulator, CRC — in one
number. Damaged frames show up as `CRC error, damaged packet`; they still prove the
radio is hearing something.

