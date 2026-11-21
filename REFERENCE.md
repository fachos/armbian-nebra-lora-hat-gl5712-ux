# Reference

Sources used for the pin map, the power and reset behaviour, and the SPI
interface. Each entry says what it contributed.

## The HAT and the module

**MAXIIOT GL5712-UX** — SX1301 concentrator with two SX1257 radios, 902–928 MHz
front end. The band names on top of it are US915 / AU915 / KR920 / AS923-1..4.
No status LED on the module. Board-level power and reset do **not** follow the
Semtech reference design — that is the root of most failed bring-ups.

**`NebraLtd/helium-miner-software`** — <https://github.com/NebraLtd/helium-miner-software>
The vendor's Balena-based miner stack. Its `hm-pyhelper` and `hm-pktfwd`
submodules contain the GPIO definitions and the power/reset sequence for this
exact HAT. The service in this repo is a clean-room reimplementation of what
those scripts do, without Balena and without the miner stack.

**`NebraLtd/Helium-Guides`** — <https://github.com/NebraLtd/Helium-Guides>
Hardware documentation for the HNT hotspot range: board revisions, connectors,
antenna options.

**`mowaxuk` Nebra hardware definitions** (community) — the pin map that made it
possible to identify POWER_EN and the LED on `gpiochip4` before any of it was
verified on a scope. Its reset-line numbers did not hold up here: the lines that
map calls reset were driven during power-up and the chip answered `0x67` anyway,
so treat that one entry as unverified and reset by cycling POWER_EN.

## Silicon and driver

**Semtech SX1301 datasheet** — register map, IF chain layout, AGC firmware, and the
calibration procedure; its status byte is the one the HAL reports (`0x8F` / `0x97`
per radio from `test_loragw_cal`, the combined `0x9F` from `lgw_start`).

**Semtech SX1257 datasheet** — radio interface, RSSI offsets, the 32 MHz TCXO
requirement, and why one radio can supply the clock for both.

**`Lora-net/lora_gateway`** — <https://github.com/Lora-net/lora_gateway>
The reference HAL. Everything in [docs/hal.md](docs/hal.md) is built from this:
`lgw_board_setconf`, `lgw_rxrf_setconf`, `lgw_rxif_setconf`, `lgw_start`, and the
`test_loragw_reg` / `test_loragw_cal` binaries used to prove the hardware.

## What this repo changed

| Change | Where | Reason |
|---|---|---|
| `SPI_DEV_PATH` → `/dev/spidev1.0` | `loragw_spi.native.c` | SPI1 is the bus wired to this HAT on a Rock Pi |
| `SPI_SPEED` 8 MHz → 2 MHz | same | stub trace from a removed SPI NOR flash corrupts fast transfers |
| sysfs GPIO reset path | `scripts/` | `pinctrl` does not exist on Armbian/RK3399 |

Nothing else is modified. No kernel patch, no vendor image, no device-tree
changes.
