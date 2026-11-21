# Why most installs fail

Five things break a Nebra LoRa HAT bring-up before the radio is ever the problem.
Each one was measured on this board; the fix is in the scripts, not in the kernel.

## 1. The reset is the power rail, not a GPIO

Sources name two reset lines (`gpiochip4` line 21 / sysfs 149 and line 22 /
sysfs 150). We drove both HIGH during power-up, and the concentrator answered
`0x67` every time — before, during and after. Neither line resets this carrier.

What does reset it is **POWER_EN** (`gpiochip4` line 3): drop the rail, raise it,
wait ~2 s for the TCXO. A recipe that waits for a GPIO pulse to reset the chip
waits forever, and a chip caught mid-power-up reads like dead hardware.

Handled by `scripts/nebra_hat.py` (and `systemctl restart nebra-lora-power`).

## 2. Register reads need a second byte

The HAL reads with a **2-byte** transfer, `[address, 0x00]`, and takes the value
from byte 1. Send only the address and MISO is never driven — every register reads
`0x66`.

The 3-byte mux form `[0x00, addr, 0x00]` is worse, not better: it picks up clock
bleed and returns `0x67` at *every* address. That is a convincing-looking answer
from a chip that is not talking at all.

Handled by `scripts/sx_probe.py` and the HAL's own `loragw_spi.native.c`.

## 3. SPI must run at 2 MHz

This HAT keeps a stub trace where an SPI NOR flash used to sit. At the stock 8 MHz
(10 MHz on some builds) writes corrupt silently and calibration returns a status
with no meaning. 2 MHz is stable over thousands of transfers.

Handled by `scripts/build-hal.sh` (two `sed` lines on the HAL checkout).

## 4. POWER_EN must be held by a live process

`gpioset` one-shots exit, release the line, the TCXO rail drops, and the
concentrator dies mid-init. The symptom is "it initialised once, then never
again".

Handled by the `nebra-lora-power` service, which holds the line for its lifetime.

## 5. Cold boot matters

After a warm `reboot` the GL5712 can come up latched, especially if the rail was
never dropped. Power off, unplug for ~10 s, plug back in — this has resolved every
"worked yesterday, dead today" case on this bench.

---

None of this is a kernel problem. It is a userspace bring-up problem, which is why
the fix is two scripts, a service and one SPI patch rather than a custom kernel or
device tree.

Install steps: [README](../README.md) · failures by symptom:
[troubleshooting.md](troubleshooting.md).
