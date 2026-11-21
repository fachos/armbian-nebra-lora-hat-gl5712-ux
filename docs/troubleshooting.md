# Troubleshooting

Any step of the main procedure that does not print its pass condition — start here.
Each entry is a failure hit during bring-up of this HAT, with the fix that worked.
The five traps that break the board before the radio is at fault are on
[failed.md](failed.md).

## `ModuleNotFoundError: No module named 'spidev'`

The packages were never installed — a fresh Armbian has no `spidev` module. Do not
reach for `pip`: install the distro package, which is what the service and the
probe both expect.

```bash
sudo bash gl5712-ux/scripts/packages.sh              # or: sudo apt install -y python3-spidev
python3 -c 'import spidev; print(spidev.__file__)'
```

Same class of failure on the power service: `from gpiod.line import Direction,
Value` fails if only libgpiod **1.x** is installed. On Debian 13 the 2.x bindings
are `gpiod` + `python3-libgpiod`.

If the import works by hand but the probe still fails: check the interpreter.
`pip install --user`, a venv, conda or pyenv all hide apt-installed modules —
`command -v python3` must be `/usr/bin/python3`.

## The first register test fails until spidev is re-bound

Symptom: the first `test_loragw_reg` after a boot fails, and the same command passes
on the next run. Re-binding the spidev driver before the test makes it pass first
time, every time.

```bash
echo spi1.0 | sudo tee /sys/bus/spi/drivers/spidev/unbind
sleep 1
echo spi1.0 | sudo tee /sys/bus/spi/drivers/spidev/bind
```

`build-hal.sh` does exactly this as its first line, which is why its first run works.
Running `test_loragw_reg` by hand needs the same two lines first.

If it still fails after the re-bind, the chip is not answering at all: check
POWER_EN, then cold boot.

## Every register reads 0x66

Symptom: `sx_probe.py` returns `0x66` (or `0x67`) for every address, identically.
MISO is not being driven — the chip is in reset, unpowered, or the SPI transaction
is malformed.

Check in this order:

1. **Is the rail actually cycling?** The reset is POWER_EN, not a GPIO. Drop line 3 for ~500 ms and raise it, then wait 2 s.
2. **POWER_EN** — `gpiochip4 line 3` must be held HIGH by a *live* process.
3. **Address byte** — read with `[addr, 0x00]` (2 bytes, value in byte 1). A
   1-byte read returns `0x66`; the 3-byte mux form returns `0x67` everywhere.
4. **SPI speed** — drop to 2 MHz. 8 MHz produces corrupt reads on this HAT.

If all four are right and it still reads `0x66`, do a **cold boot**: `poweroff`,
unplug 10 s, replug. Warm reboots can leave the GL5712 latched.

## `test_loragw_cal` prints its usage text instead of calibrating

`ERROR: missing frequency input parameter: Radio A RX: 0, Radio B RX: 0`, followed
by the option list. The binary needs both RX frequencies; it does not default
them. Not a build problem.

```bash
./test_loragw_cal -a 915.0 -b 916.0 -r 1257 -n 5     # US915 / AU915 / KR920 / AS923
```

Both frequencies must be inside 902–928 MHz, the GL5712-UX front end. The test does
not range-check them: out of band you get a poor calibration status, not an error.

`scripts/build-hal.sh` does this for you and only passes when the Rx A lines read
143 (0x8F), the Rx B lines read 151 (0x97), and there are no `WARNING` lines; the
frequencies there default to the 915 MHz band this HAT was tested on, so pass
`-a/-b` for any other band.

## Calibration returns 143 and 151, not 159

That is success. `test_loragw_cal` runs one calibration command per radio, so the
status register reports only that command's bits: Rx A gets bit 3 (0x8F = 143) and
Rx B gets bit 4 (0x97 = 151). `0x9F` (159) is the combined status of a *single*
command covering both radios — that is what `lgw_start` sends, not this test.

## Calibration returns status 0x00

`lgw_connect` succeeds but `test_loragw_cal` prints `0x00`, or the AGC firmware
load never logs. Almost always the warm-boot latch → cold boot. If it survives a
cold boot, re-check SPI speed and repeat the reset the way it actually works:
cycle POWER_EN (line 3) LOW ~500 ms, HIGH, then 2 s settle before the first read.

## "Device or resource busy" on the power line

Something else already owns POWER_EN (`gpiochip4` line 3) — typically a leftover
`gpioset` from a manual bring-up. Only one owner.

```bash
sudo pkill -x gpioset
sudo fuser -v /dev/spidev1.0      # who holds the bus
```

Only one process may hold `/dev/spidev1.0` at a time either. Note that lines 21
and 22 (the reported reset pins) are not driven by this project at all — if you
see them claimed, it is another tool, and it does not affect bring-up because
asserting them was measured to do nothing.

## "no FPGA detected or version not supported (v0)" in the log

Normal on SX1301. The HAL probes for an FPGA on SX1302 designs; SX1301 boards
always print this and then connect successfully. Ignore it.

## SPI works but nothing is ever received

First separate hardware from configuration: run the loopback test from
[hal.md](hal.md) §6. It transmits its own frame every ~4.8 s and receives it
back, so if `Rcv pkt` lines appear, the radio, the PA and the receive chain are all
fine and the problem is below. If they do not appear either, go to
[07 § Every register reads 0x66](#every-register-reads-0x66) instead.

With the loopback passing, the listening side is configuration: the IF chain listens
on the frequency and spreading factor you programmed, and nowhere else.

- wrong frequency offset ⇒ nothing, ever
- wrong spreading factor ⇒ nothing, ever
- antenna not connected ⇒ RSSI flat, nothing ever

Check what you programmed before blaming the radio. `lgw_rxif_setconf(8)` takes
the bandwidth and datarate; `lgw_rxrf_setconf()` takes the carrier.

## u.FL antenna connector

If RSSI never moves, reseat the u.FL: lift straight up, press straight down until
it clicks. Sideways pressure bends the centre pin and produces a ~20 dB loss that
looks like a broken radio.

## Still stuck

Capture these four and open an issue:

```bash
sudo python3 gl5712-ux/scripts/sx_probe.py
cd /opt/lora_gateway/libloragw && sudo ./test_loragw_cal -a 915.0 -b 916.0 -r 1257
journalctl -u nebra-lora-power -n 50 --no-pager
cat /proc/device-tree/model; echo
```
