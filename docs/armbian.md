# Fresh Armbian install and SPI enable

Covers the **packages** and **SPI** steps of the main procedure (README steps 0–1),
and the bus sanity check (step 3).

Target: **Armbian 26.11 “trixie” minimal** for `rk3399` (Rock Pi 4B+).
Any recent Armbian works; the overlay name is what matters.

## 1. Flash and boot

```bash
# on your workstation — write the image to SD or eMMC
xz -dc Armbian_26.11_*.img.xz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

First boot: login `root` / `1234`, complete the forced password change, then:

```bash
sudo apt update && sudo apt -y install git && sudo apt -y upgrade
git clone https://github.com/fachos/armbian-nebra-lora-hat-gl5712-ux.git gl5712-ux
sudo bash gl5712-ux/scripts/packages.sh          # or by hand, same list:
# apt -y install build-essential gpiod python3-libgpiod python3-spidev
reboot
```

`python3-spidev` (the `spidev` module) and `python3-libgpiod` (the `gpiod.line`
API used by `nebra_hat.py`) are not optional — without them the first probe dies
with `ModuleNotFoundError: No module named 'spidev'`, or the power service dies
at `from gpiod.line import Direction, Value`.

**One unknown package name aborts the whole `apt install`.** On Debian 13 the
libgpiod 2.x stack is `gpiod` + `python3-libgpiod`; the 1.x name `libgpiod2` no
longer exists, and leaving it in the line means *nothing* gets installed —
including `python3-spidev`. That is exactly how a "complete" instruction still
lands the reader on `ModuleNotFoundError`. If an apt line of your own mentions
`libgpiod2`, drop it, and confirm the result instead of trusting the exit code:

```bash
python3 -c 'import spidev; from gpiod.line import Direction, Value; print("imports ok")'
```

If you install to eMMC instead of SD, run `armbian-install` and pick the eMMC
target; everything below is identical.

## 2. Enable SPI (SPI1 → `/dev/spidev1.0`)

```bash
cp /boot/armbianEnv.txt /boot/armbianEnv.txt.bak
```

Edit `/boot/armbianEnv.txt` and make sure these lines exist (add or replace the
`overlays=` line — do not add a second one):

```
overlay_prefix=rockchip
overlays=rk3399-spi-spidev
param_spidev_spi_bus=1
param_spidev_max_freq=2000000
```

Helper script (idempotent):

```bash
sudo bash gl5712-ux/scripts/armbian-spi.sh
```

> **Do not build a custom `.dtbo` for this HAT.** The stock
> `rk3399-spi-spidev` overlay is enough; the SX1301 needs no special
> compatible string, only a spidev node on bus 1. Custom `overlay-user/*.dtbo`
> files were a dead end during bring-up — the device tree was never the problem.

## 3. Reboot and verify

```bash
reboot
```

```bash
ls -l /dev/spidev*                     # expect /dev/spidev1.0
dmesg | grep -i spidev
ls /proc/device-tree/spi@ff1d0000/     # SPI1 controller node (RK3399)
```

If `/dev/spidev1.0` is missing:

```bash
cat /boot/armbianEnv.txt               # exactly one overlays= line?
armbianmonitor -u                      # dumps boot info for review
```

Common causes: two `overlays=` lines (the last one wins), a typo in
`param_spidev_spi_bus`, or booting the wrong device tree.

## If you came looking for `armbian-add-overlay`

You do not need it for this HAT. That tool compiles a **custom** `.dts` into
`/boot/overlay-user/<name>.dtbo` and adds a `user_overlays=` line — useful when
you add device-tree nodes that Armbian does not ship.

`rk3399-spi-spidev` is already shipped, and it is all this board needs: SPI1 on
bus 1 at 2 MHz. A hand-written overlay was tried during bring-up and changed
nothing; the stock one worked as soon as the SPI speed was lowered.

Use `armbian-add-overlay` only if you are adding something new (a GPIO hog, a
second spidev with a different chip-select, disabling a conflicting node). If you
do add a `gpio-hog` for POWER_EN, do not also run `nebra-hat` — two owners on the
same line, and the service loses.

## 4. Cold boot matters

The GL5712 can come up in an indeterminate state after a **warm** reboot
(`reboot`), especially if the rail was never dropped. If the chip looks dead
after a reboot, power off completely, unplug for ~10 s, plug back in:

```bash
poweroff
# unplug, wait 10 s, plug in
```

A cold boot has fixed this every time.

## 5. Quick sanity check of the bus

With the HAT installed and `nebra-hat` running (next doc), the probe reads four
registers and names the chip:

```bash
sudo python3 gl5712-ux/scripts/sx_probe.py
```

```
/dev/spidev1.0: 00=00 01=67 02=00 03=00
/dev/spidev1.0: SX1301 ALIVE (VERSION=0x67 at reg 0x01)
```

`0x66` on every register, or the same value everywhere, means MISO is not driven:
POWER_EN low or never raised, the missing dummy byte in the SPI transaction, or SPI
speed too high. All three are covered in [power-gpio.md](power-gpio.md) and
[troubleshooting.md](troubleshooting.md).

This probe is a 4-register answer to "is anything alive". The full register sweep —
five known-value checks plus a 256-byte burst — is `test_loragw_reg`, built in
[hal.md](hal.md).
