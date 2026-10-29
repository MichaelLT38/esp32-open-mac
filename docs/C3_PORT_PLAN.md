# ESP32-C3 Open Wi-Fi MAC in C: Port Plan

**Fork:** `MichaelLT38/esp32-open-mac` · **Working branch:** `c3-port` (created 2026-10-29 from `main` @ `20ce43d`)
**Target:** ESP32-C3 only, on the **M5Stack M5Stamp C3U** · **SDK:** ESP-IDF **v5.0.1** · **Language:** C11
**Scope:** your own fork. No upstream contributions.

---

## 0. Decisions

| Decision | Consequence |
|---|---|
| Port the **latest Rust** stack to C | The main sources are the C3 branches of esp-wifi-hal and FoA (§2), not the old `lib.rs` in this repo. |
| **ESP32-C3 only**, no ESP32/S2/S3 | The repo's hardware code (`main/hardware.c`, `hwinit.c`, `proprietary.h`) is ESP32-only (Xtensa, `0x3ff73000` addresses) and gets **rewritten**. Non-C3 blobs and code paths are deleted. |
| **Own fork**, no upstream | `main` stays as a read-only snapshot of upstream. All work goes on `c3-port` and its feature branches. The `upstream` remote is kept only to read history. |
| **ESP-IDF v5.0.1** | Installed. Check the chip revision first (§3.2): v1.1 silicon needs v5.0.5+. |

---

## 1. Where things stand

- **This C repo:** ESP32 (Xtensa) only. Upstream stopped working on it in Feb 2026 ([issue #28](https://github.com/esp32-open-mac/esp32-open-mac/issues/28)).
- **Upstream Rust** ([esp-wifi-hal](https://github.com/esp32-open-mac/esp-wifi-hal), [FoA](https://github.com/esp32-open-mac/FoA)): ESP32 and ESP32-S2 only.
- **A working ESP32-C3 Rust port exists but isn't merged upstream.** okhsunrog's branches ([esp-wifi-hal@esp32c3](https://github.com/okhsunrog/esp-wifi-hal/tree/esp32c3), [FoA@esp32c3](https://github.com/okhsunrog/FoA/tree/esp32c3)) add +849 lines on top of upstream (Sept 10, 2026). Their register map was merged into esp-pacs on 2026-09-11 as [esp-rs/esp-pacs#510](https://github.com/esp-rs/esp-pacs/pull/510).
  - **Tested on real C3 hardware:** frame RX/TX, hardware auto-ACK, hardware CCMP, TX result decoding, TSF timers, TBTT events, and **a full WPA2 station connection with DHCP through FoA**.
  - **Caveats:** one author, about 7 weeks old, experimental. Many register meanings are inferred.
- **The C3 shares its Wi-Fi 4 MAC with the S2/S3.** Its register offsets were found by diffing the same-named `hal_*` blob functions against the S2. So the **S2 code paths in esp-wifi-hal are the closest template for the C3**, even though S2 isn't a target. Port the `esp32s2`/`esp32c3` branches and ignore the `esp32` ones.
- **Mesh reference exists:** upstream FoA branch [`foa_mesh`](https://github.com/esp32-open-mac/FoA/tree/foa_mesh) (~1,300 lines of Rust, WIP, Apr 2026) has mesh beacons and Mesh Peering Management open/confirm.
- **Licensing:** FoA and esp-wifi-hal are MIT/Apache-2.0, and this repo is MIT. Keep their copyright notice at the top of every C file ported from them.

### Pinned reference commits

Port against these exact versions so behaviour can be compared.

| Source | Commit | Date | Use |
|---|---|---|---|
| okhsunrog/esp-wifi-hal `esp32c3` | `e65264a` | 2026-09-10 | **Primary:** C3 low-level driver |
| okhsunrog/FoA `esp32c3` | `4327a73` | 2026-09-10 | C3 build wiring for FoA |
| esp32-open-mac/FoA `main` | `2b7ec13` | 2026-08-14 | LMAC, STA, WPA2 logic |
| esp32-open-mac/FoA `foa_mesh` | `151bc09` | 2026-04-05 | 802.11s mesh |
| esp-rs/esp-pacs `main` | `176f985` | 2026-10-29 | `esp32c3/svd/patches/wifi.yaml` + `common_patches/wifi/mac/*.yaml` |

Local reference clones are in the session scratchpad. Re-clone them at these commits into a folder **outside** the repo, for example `HCK\reference\`.

---

## 2. What to port, and from where

| Source | Port? | Notes |
|---|---|---|
| **esp-wifi-hal@esp32c3 `ll.rs`** (C3/S2 paths) | **Yes, core of the new HAL** | Init sequence, MAC CTRL, interrupts, RX DMA, TX slots, PLCP/HT-SIG, filter banks, crypto key slots, TSF/TBTT, channel, power control |
| `dma_list.rs`, `crypto.rs`, `edca.rs`, `rates.rs`, `esp-wifi-rates` (+tests) | **Yes** | All chip-independent logic. The rate tests port straight to host-side C tests. |
| `async_driver.rs` | **Partial** | Port TX slot lifecycle, TX result handling, and the C3 RX frame validation (48-byte RX header, `sig_len` check). Map the async parts to FreeRTOS. |
| `ffi.rs` (C3) | **Reference** | Lists the C3 blob/ROM calls: `hal_init`, `chip_v7_set_chan[_nomac]`, `tx_pwctrl_background`, `rom_enable/disable_wifi_agc`, `g_osi_funcs_p`, `coex_pti_get`. In C, most of this comes from ESP-IDF directly (see §4). |
| esp-wifi-hal examples: `acktest`, `sniffer`, `txresult`, `tsf_timer_test`, `beacon`, `dup_test`, `crypto_tx/rx`, `ack_timeout_test_*` | **Yes, as C test apps** | These are the **acceptance tests** for the HAL. |
| FoA `foa/` (LMAC, tx_queue, rx_arc_pool, rx_router) | **Partial** | Copy the design (one LMAC, several virtual interfaces, refcounted RX buffers) and write it with FreeRTOS. |
| FoA `foa_sta/` (connect, rsn, bss, scan) | **Yes** | WPA2-PSK. Already proven on the C3 in Rust. |
| FoA `foa_mesh` branch | **Yes, later** | Starting point for 802.11s. |
| FoA `foa_awdl/` | **No** | Apple AWDL. Out of scope. |
| This repo `lib.rs` | **Yes, as MAC structure** | Chip-independent STA/AP state machines. Port it with the bug fixes in §6. |
| This repo `main/mac.c` (esp-netif glue) | **Keep** | Chip-independent. Works as-is. |
| This repo `hardware.c`, `hwinit.c`, `proprietary.h`, `80211_mac_interface.h` RX struct | **Rewrite** | ESP32-only. The C3 RX control header is 48 bytes with a different layout. |
| `sync.rs`, `borrowed_buffer.rs`, embassy/async, ESP32-only paths (DPORT, Xtensa interrupts, MAC-time callback) | **No** | |

**Language: C11 throughout.** ESP-IDF is C, and the Rust code relies on the borrow checker rather than RAII. The only real reason for C++ is RAII buffer wrappers. If you want them, limit C++17 to the MAC layer behind `extern "C"` headers.

---

## 3. Phase 0: Toolchain and board bring-up

### 3.1 ESP-IDF v5.0.1 (done 2026-10-29)

| Item | Location |
|---|---|
| IDF | `C:\Espressif\esp-idf-v5.0.1` (tag `v5.0.1`) |
| Tools (RISC-V gcc, cmake, ninja, openocd, esptool 4.7) | `C:\Espressif\tools-v5.0.1` (kept separate from your v5.4.2 tools) |
| Python env | `C:\Espressif\tools-v5.0.1\python_env\idf5.0_py3.9_env` (Python 3.9 from Visual Studio; v5.0.1 predates 3.12) |

To open a v5.0.1 shell in PowerShell, from the repo root:

```powershell
. .\tools\idf501.ps1
```

**Verified 2026-10-29:** `hello_world` builds for `esp32c3`. Setup notes:
- **Python pins** in the v5.0.1 env (already applied): `setuptools<70`, `ruamel.yaml<0.18`, `ruamel.yaml.clib==0.2.8`. The newest versions break v5.0.1's dependency checker.
- **Path length:** Windows' 260-character limit breaks deep build trees, and this repo's path is long and has a space (`BitSwizzler LLC`). Build out of tree with `idf.py -B C:\Espressif\b\openmac …`, or enable Windows long-path support yourself.

### 3.2 Chip revision: checked 2026-10-29, v0.3 is OK

ESP32-C3 **v1.1** silicon would need ESP-IDF v5.0.5+. **Your C3U is v0.3**, which v5.0.1 supports, so no IDF change is needed.

| Item | Value (from `esptool` and the boot log) |
|---|---|
| Chip | ESP32-C3 (QFN32), **revision v0.3** |
| Flash | 4 MB embedded (XMC), DIO @ 80 MHz |
| Crystal | 40 MHz |
| MAC (eFuse) | `60:55:f9:57:a5:f8` (use this instead of the hard-coded MACs) |
| Mask ROM | `esp32c3-api1-20210207`. Matches what v5.0.1's `esp32c3.rom.ld` expects, so ROM symbols like `g_osi_funcs_p` and `rom_enable_wifi_agc` line up. |
| USB port | Shows up as **COM11** (`303A:1001` USB-Serial/JTAG) |

**Verified:** `hello_world` built with v5.0.1, flashed, booted, and printed to the USB console. Needed `sdkconfig.defaults`:
```
CONFIG_ESP_CONSOLE_USB_SERIAL_JTAG=y
CONFIG_ESPTOOLPY_FLASHSIZE_4MB=y
```
The default `idf.py flash` auto-reset works over USB-Serial/JTAG, so you don't have to hold the button each time.

If the board ever doesn't show up on USB at all, suspect the cable first. The C3U has no USB-serial chip, so a charge-only cable leaves it invisible.

### 3.3 M5Stamp C3U notes

| Feature | Detail | Effect on the project |
|---|---|---|
| SoC | ESP32-C3, single-core RISC-V @160 MHz, 400 KB SRAM, 4 MB flash | Single core: drop the core pinning and dual-core assumptions (`NUM_CORES 2` in `proprietary.h`). Fewer race conditions. |
| USB-C | Native **USB-Serial/JTAG**, no USB-UART chip | Set `CONFIG_ESP_CONSOLE_USB_SERIAL_JTAG=y` (boot logs go to UART0 by default). **Built-in JTAG**: OpenOCD + GDB work with no extra probe, which is a big help for register tracing. |
| RGB LED | SK6812 on GPIO2 | Status indicator (scanning / associated / error) via the `led_strip` or RMT driver |
| Button | GPIO9 (also the boot strap pin) | Download mode. At runtime: a user action (for example, toggle AP). |
| Download mode | Hold GPIO9 while plugging in USB | Flashing workflow |

### 3.4 Hardware to have

- **2× M5Stamp C3U.** The TX/ACK/crypto tests need a sender and a receiver.
- A monitor-mode USB Wi-Fi adapter with Wireshark, as the sniffer.
- An open AP and a WPA2 AP you control. Later, a Linux box with `hostapd` and `iw` for WPA3 and mesh interop.

### 3.5 Bring-up steps

1. Get `hello_world` running on the C3U with the USB-Serial/JTAG console.
2. Run the stock ESP-IDF `wifi/getting_started/station` example on the C3U and **capture a pcap** of how the proprietary stack behaves (rates, durations, seq-ctrl, assoc IEs). That's the golden reference.
3. **Strongly recommended:** flash the Rust C3 stack (esp-wifi-hal@esp32c3 examples, FoA `sta` example) onto a C3U. You then have a known-good open stack on the exact chip, and you can **dump its registers over JTAG** after init and compare them with your C port. That's the fastest way to tell "my port is wrong" from "the chip differs". The `esp` Rust toolchain is installed; add the `riscv32imc-unknown-none-elf` target on nightly.
4. **Repo restructuring on `c3-port`:**
   - `idf.py set-target esp32c3`, then regenerate `sdkconfig`
   - Remove the ESP32-only `#error`s and the PHY version check in `main/main.c`
   - Vendor the **C3** blobs from v5.0.1 (`components/esp_wifi/lib/esp32c3/libpp.a`). `components/esp_phy/lib/esp32c3/` already has `libphy.a` and `libbtbb.a`.
   - Delete the ESP32/S2/S3/C2/H2 blobs and `phy_init_data` folders
   - Update `esp32-wifi.yaml`, `license/README.md`, and the README

---

## 4. Phase 1: C hardware layer for the C3

**This comes first:** nothing can be tested on the C3 without it.

New component `components/openmac_hal/`:

| Piece | Rust source | C3 specifics |
|---|---|---|
| `wifi_reg_c3.h` | esp-pacs `wifi.yaml` | Generate it with a small script (`tools/svd_yaml_to_h.py`) from `esp32c3/svd/patches/wifi.yaml` + `common_patches/wifi/mac/*.yaml`. Base `0x60033000`. No magic numbers in the C code. |
| Init | `ll.rs` `init`/`setup_mac`/`set_mac_state` | 1. Modem clock: `APB_CTRL.WIFI_CLK_EN \|= 0x00fb9fcf`. 2. PHY enable (IDF `esp_phy_enable`). 3. Reset MAC. 4. `CTRL` (0xca0): clear with mask `0xff00efff`, wait while `0x6000` is set. 5. `g_osi_funcs_p = &g_wifi_osi_funcs`. 6. `hal_init()` (blob). 7. Filters and crypto setup. |
| OS adapter | `ffi.rs` `install_osi_funcs`, `coex_pti_get` | **Reuse ESP-IDF's own** `components/esp_wifi/esp32c3/esp_adapter.c` (`g_wifi_osi_funcs`). `g_osi_funcs_p` is already in `esp32c3.rom.ld` (0x3fcdf954). Override `_coex_pti_get` with a stub that returns 0 (no coexistence). |
| Interrupts | `ll.rs` interrupt config | RISC-V: use `esp_intr_alloc(ETS_WIFI_MAC_INTR_SOURCE, …)` instead of Xtensa `xt_set_interrupt_handler`. RX cause mask `0x1204000`. Also handle the **WIFI_PWR** interrupt (TBTT and TSF timer causes, `PWR_INT_ENABLE` 0x2110). |
| RX | `dma_list.rs`, `async_driver.rs` | DMA descriptor ring (`RX_DMA_LIST` at 0x88). **48-byte RX header** validated by `sig_len`. Clear ownership between the ISR, HAL task, and MAC task. |
| TX | `ll.rs:1044-1316`, `edca.rs` | 5 slots, **stride 0x4c**. C3 `PLCP1` layout (len 0–11, rate 12–16, key slot 17+, HT bit 25). The "misc" register (PAC: PLCP2) holds the response rate and interface. C3 `HT_SIG` layout. `DURATION`. **`PMD` = TX result** (ACK / timeout / collision). `TX_PTI` coex priority. Slot↔AC mapping with **reversed status bits**; handle every set bit. |
| Filters | `ll.rs:879-1040` | 2 banks (BSSID, RA) × 4 interfaces, with masks; scanning mode |
| TSF / TBTT | C3 branch commit `08909de` | Per-interface TSF counters, hardware **TBTT** (accurate AP/mesh beacon timing), 4 TSF timers |
| Crypto | `crypto.rs`, `ll.rs:1318-1485` | 25 key slots at 0x1400; `CRYPTO_CONTROL` at 0x800; CCMP-128 |
| Channel / power | `ffi.rs` | `chip_v7_set_chan_nomac` (blob), `rom_enable/disable_wifi_agc` (ROM), periodic `tx_pwctrl_background` |

**Done when:** C versions of `sniffer`, `acktest`, `txresult`, `tsf_timer_test`, `beacon`, `dup_test` and `crypto_tx/rx` pass between two C3Us, and the sniffer confirms the frames on air.

---

## 5. Phase 2: C MAC layer (chip-independent)

The frame library and host tests need no hardware, so **start them alongside Phase 1**.

New component `components/openmac_mac/`. It replaces `components/80211_mac_rust/`, which gets deleted along with cargo, bindgen and the ExternalProject.

| File | Ported from | Notes |
|---|---|---|
| `ieee80211.h/.c` | `ieee80211-rs` usage | Headers, element iterator (SSID, rates, DS, TIM, RSN), builders for Beacon, Probe Resp, Auth, Assoc Req/Resp, Data. Constants from hostap's `ieee802_11_defs.h` (BSD, in the IDF `wpa_supplicant` component). |
| `llc.c` | `llc-rs` | LLC/SNAP encapsulation and decapsulation |
| `mac_seqctl.c` | `lib.rs:890-941` | Per-peer 32-entry duplicate window |
| `mac_lmac.c` | FoA `foa/` | Virtual interface multiplexer, TX queue per access category, refcounted RX buffers |
| `mac_sta.c` | `lib.rs` + FoA `foa_sta` | Scan with BSS list (not a hard-coded SSID), then auth, assoc, associated. Settings via Kconfig. MAC from eFuse (`esp_read_mac`). |
| `mac_ap.c` | `lib.rs` | Beacons driven by hardware TBTT, probe response, open auth, AID table, client timeout |
| `mac_data.c` | `lib.rs` | 802.11 ↔ Ethernet. Real per-peer sequence numbers. |
| `mac_task.c` | `lib.rs` `rust_mac_task` | FreeRTOS event loop; buffer ownership rules written at the top |
| `main/mac.c` | (kept) | esp-netif glue |

**Tests:**
- Host-side unit tests (CMake + ctest on Windows, or Unity) for frames, elements, seqctl, LLC and rates.
- Golden frames from the Phase 0 pcaps.

**Done when:** an open-network STA gets a DHCP lease and passes ping, a phone joins the C3U's AP, and dual STA+AP works.

---

## 6. Bugs from the old code (MAC layer: fix while porting)

| # | Location | Problem |
|---|---|---|
| B1 | `lib.rs:461-470` | AP assoc writes the new client into **every** free slot (no `break`) |
| B2 | `lib.rs:621-626` | AP data RX refreshes the timestamp of the **destination**, not the transmitter |
| B3 | `lib.rs:167` | TX payload length `+1`: reads one byte past the buffer |
| B4 | `lib.rs:732-734, 760-762` | Fragment number set to 1 (should be 0). Only hidden by the HW-side seq overwrite. |
| B5 | `lib.rs:709` | Assoc request hard-codes SSID `meshtest` and odd rates |
| B6 | `80211_mac_interface.c:163-165` | A full RX queue calls `abort()`. It should drop the frame and recycle. |
| B7 | `lib.rs:520, 855` | Beacon timestamp is always 0. Fixed by the C3 TSF counters. |

Lessons from the old ESP32 `hardware.c` that apply to the C3 rewrite:
- Handle **every** TX-complete bit, using the reversed slot mapping (the old code handled only one).
- Lock the RX ring between tasks.
- Double-check register addresses. The old code had `0x3ff73ccc0`, with an extra digit; the generated header prevents this.

---

## 7. Later phases: the remaining goals

### Phase 3: WPA2-PSK with hardware CCMP (STA)

Already proven on the C3 in Rust (FoA + esp-wifi-hal@esp32c3).

- **Crypto via mbedTLS** (bundled with IDF):
  - PMK: PBKDF2-HMAC-SHA1, 4096 iterations
  - PTK: 802.11 PRF (HMAC-SHA1)
  - EAPOL MIC with the KCK
  - GTK unwrap: AES Key Wrap (`mbedtls_nist_kw`)
- EAPOL 4-way handshake and group-key handshake, ported from `foa_sta/operations/connect.rs` and `rsn.rs`
- Install PTK/GTK into hardware key slots; per-key PN and replay counters
- Validate with IEEE 802.11 Annex J test vectors (host tests)

### Phase 4: AP completeness

- WPA2 AP side (authenticator)
- Multiple clients
- Power save with TIM/DTIM using hardware TBTT
- A-MSDU RX
- Channel list per regulatory domain (US: 1–11)

### Phase 5: 802.11s mesh (the project's original goal)

1. Port `foa_mesh`: mesh beacons (Mesh ID, Mesh Configuration), Mesh Peering Management open/confirm/close.
2. Add what that branch lacks: 4-address data frames, the mesh control header, **HWMP** path selection (PREQ/PREP/PERR) with an optional proactive root.
3. Interop target: Linux mac80211 (`iw dev <if> mesh join <id>`) alongside several C3Us.
4. Use the C3's **TSF/TBTT hardware** for beacon timing and neighbour sync.

### Phase 6: WPA3-SAE and PMF

- SAE over ECC group 19 (mbedTLS ECP), with hash-to-element preferred
- PMF (802.11w), which WPA3 requires: management frame protection plus BIP-CMAC
- Test against `hostapd` with `sae_pwe=2`
- Then secure mesh: SAE + AMPE

### Phase 7: Fewer blobs on the C3

| Call | Difficulty | Notes |
|---|---|---|
| `hal_init` | Medium | Includes the coex PTI init. Reverse it with Ghidra on the C3 `libpp.a` and confirm with JTAG register traces. |
| `rom_enable/disable_wifi_agc` | Low priority | Lives in **mask ROM** on the C3, so it's fixed silicon code, not a linked blob. Reimplementing it is optional. |
| `chip_v7_set_chan[_nomac]` | Medium–High | RF channel programming |
| `tx_pwctrl_background` | High | TX power calibration |
| libphy `esp_phy_enable` / calibration | Very high | Accept it as a blob, as the Rust stack does |

**Tooling note:** the esp32-open-mac QEMU fork is ESP32/Xtensa only. Espressif's QEMU runs the C3 but doesn't emulate Wi-Fi. For the C3, use **Ghidra plus on-chip JTAG** over the C3U's USB.

**Rule:** document the behaviour and write fresh code. Don't paste decompiled blob code.

### Phase 8 (optional): Leave v5.0.1

Once the port is stable, move to a current IDF (v5.4.x is installed). Re-vendor the matching C3 blobs and re-check the `hal_init` behaviour.

---

## 8. Fork workflow

- **Remotes:**
  - `origin` = your fork
  - `upstream` = esp32-open-mac, read-only history (it's discontinued, so pulls are optional)
- **Branches:**
  - `main` is a frozen upstream snapshot
  - `c3-port` is the integration branch
  - Feature branches off it: `c3/hal-init`, `c3/hal-tx`, `c3/mac-frames`, `c3/wpa2` and so on, merged back when their acceptance test passes
- **CI (optional):** a GitHub Actions job on your fork that builds with `espressif/idf:v5.0.1` for `esp32c3` and runs the host unit tests.
- **Attribution:** keep the MIT/Apache notices in ported files and list the pinned source commits (§1) in `license/README.md`.

---

## 9. Risks

| Risk | Mitigation |
|---|---|
| Chip revision vs IDF v5.0.1 | **Resolved:** your board is v0.3. Re-check any extra C3U you buy; v1.1 units need IDF v5.0.5+. |
| The C3 Rust port is experimental (one author, register meanings partly guessed) | Use the Rust C3 build on the same board as a live reference; compare JTAG register dumps |
| **Blob version mismatch:** the Rust C3 port was tested with `esp-wifi-sys-esp32c3 0.2.0` blobs, not IDF v5.0.1's `libpp.a`, so `hal_init` may behave differently | Check the register state after `hal_init` against the Rust build early in Phase 1 |
| Coexistence: the C3 also has BLE | Out of scope. Stub coex and don't run BLE at the same time. |
| RF and regulatory limits | Use only legal channels and power for your region (US: ch 1–11). The C3U's PCB antenna limits range. |

---

## 10. Milestones (relative size)

| # | Milestone | Size | Depends on |
|---|---|---|---|
| M0 | ~~Chip revision check~~ ✅ · ~~hello_world over USB-JTAG~~ ✅ · stock-Wi-Fi pcap · Rust C3 reference build flashed · repo re-targeted to C3 | S | — |
| M1 | `wifi_reg_c3.h` generator; HAL init + RX (`sniffer` passes) | M | M0 |
| M2 | HAL TX + TX result + auto-ACK (`acktest`, `txresult`, `beacon`, `dup_test`) | M | M1 |
| M3 | Frame library + seqctl + LLC + rates with host tests | M | — (parallel with M1–M2) |
| M4 | C MAC: open STA + DHCP, AP, dual; Rust removed; B1–B7 fixed | M | M2, M3 |
| M5 | TSF/TBTT + crypto key slots (`tsf_timer_test`, `crypto_tx/rx`) | M | M2 |
| M6 | WPA2-PSK STA with hardware CCMP | L | M4, M5 |
| M7 | WPA2 AP, multi-client, power save, A-MSDU | M | M6 |
| M8 | 802.11s open mesh + HWMP, Linux interop | XL | M5, M7 |
| M9 | WPA3-SAE + PMF; secure mesh | L | M6, M8 |
| M10 | Blob reduction (`hal_init`, channel set) | L–XL | M2 |
| M11 | (Optional) Move to current ESP-IDF | M | M4 |
