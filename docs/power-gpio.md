# Power, reset and status LED

Covers **step 2** of the main procedure: hold POWER_EN, own the status LED.

Three GPIOs matter before any SPI transaction:

| Signal | gpiochip4 line | sysfs | State | Owner |
|---|---|---|---|---|
| POWER_EN | 3 | 131 | HIGH, held | `nebra-hat` service |
| Status LED | 28 | 156 | HIGH = lit | `nebra-hat` service |
| RESET candidates | 21 / 22 | 149 / 150 | not used | nothing — measured to do nothing |

sysfs number = `gpiochip base + line`, and `gpio4` has base **128** on this SoC.

The reset is the **POWER_EN rail**, not a GPIO. Lines 21 and 22 are the two the
sources name, and asserting either during power-up left the chip answering `0x67`
every time — so nothing here drives them. For the same reason there is no "reset
pulse" to make fail: the only owner that matters is POWER_EN, and one owner per
line still applies if you decide to drive them yourself.

## Why a service, not `gpioset`

```bash
gpioset -z 3=1        # exits immediately, releases the line
```

When the line is released the TCXO rail drops and the concentrator dies
mid-init — the classic "it initialised once, then never again" symptom. A
long-running process holds the line for as long as it lives.

## Install

```bash
sudo install -d /usr/local/share/nebra
sudo install -m 0755 gl5712-ux/scripts/nebra_hat.py /usr/local/sbin/nebra-hat
sudo install -m 0644 gl5712-ux/scripts/sx_probe.py  /usr/local/share/nebra/sx_probe.py
sudo install -m 0644 gl5712-ux/scripts/nebra-lora-power.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now nebra-lora-power.service
```

```bash
systemctl is-active nebra-lora-power            # active
journalctl -u nebra-lora-power -n 20 --no-pager
# nebra-hat[812]: reset: POWER_EN line 3 LOW 0.5s
# nebra-hat[812]: reset: POWER_EN HIGH, settling 2.0s, LED line 28 on
# nebra-hat[812]: probe: /dev/spidev1.0: 00=00 01=67 02=00 03=00
# nebra-hat[812]: probe: /dev/spidev1.0: SX1301 ALIVE (VERSION=0x67 at reg 0x01)
```

`/var/log/nebra-hat.log` carries the same lines with a timestamp instead of the
pid. If the last two are missing or say `FLOATING MISO`, the rail is not up: the
service cycles POWER_EN LOW 0.5 s → HIGH → waits 2 s, and only then probes.

Logs: `journalctl -u nebra-lora-power -f` and `/var/log/nebra-hat.log`.

## The reset sequence

There is no GPIO pulse in it — this is what `nebra-hat` does at start:

```python
power_en(0)            # drop the rail         500 ms   ← this is the reset
power_en(1)            # raise it — chip boots from POR
sleep(2)               # TCXO + MCU startup before the first SPI access
```

Then read reg `0x01`: expect `0x67`. Restarting the service re-runs the cycle,
which is why `systemctl restart nebra-lora-power` is the way to recover a latched
chip without a power cut.

If a recipe tells you to pulse a GPIO to reset the chip, test it first. On our
board, asserting line 21 or line 22 during power-up changed nothing — the chip
booted from power-on reset every time. Cycling POWER_EN is the reliable reset.

## LED behaviour

```
green steady   service running, POWER_EN held
green off      service stopped  →  systemctl status nebra-lora-power
orange only    HAT in standby; the Pi itself is not powered
```

The GL5712-UX module has **no LED of its own** — no light on the module means
nothing. The green LED is driven by line 28; the board's own activity LED
blinks with disk I/O and is not a status indicator.
