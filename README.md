# Webcam Streaming Using FPGA and ESP32 🎥

Real-time webcam streaming to a **Basys 3 (Artix-7)** FPGA. A laptop captures webcam frames and sends them over Wi-Fi (UDP) to an **ESP32**, which forwards them to the FPGA over **SPI**. The FPGA stores each frame in block RAM and outputs it to a VGA monitor.

## Project Overview

```
Webcam -> webcam.py (PC) --UDP/Wi-Fi--> ESP32 --SPI--> Basys 3 FPGA --VGA--> Monitor
```
<img width="1532" height="805" alt="Screenshot 2026-10-30 221407" src="https://github.com/user-attachments/assets/fb485090-491a-4efb-a486-03a1140ad73c" />


The focus of this project is the FPGA side: SPI reception, pixel packing, dual-port frame buffering and VGA output, all written in Verilog. The PC script and ESP32 firmware are supporting tools that deliver the data (see the Development Note below).

### Key Functionality

**Frame Capture and Packing (PC):** `webcam.py` grabs frames with OpenCV, downscales them to 160x120 and packs each pixel into 2 bytes of RGB444. Each frame is split into 30 UDP packets of 4 lines each.

**Wi-Fi to SPI Bridge (ESP32):** The ESP32 runs as a Wi-Fi access point, receives the UDP packets and forwards each one unchanged as a single DMA-driven SPI transaction (CS low for the whole packet). A 16-slot buffer queue decouples Wi-Fi reception from SPI transmission.

**SPI Reception (FPGA):** `SPI_Rx` acts as an SPI slave, sampling `mosi` on `sclk` while `cs_n` is low and producing an 8-bit word with a `data_valid` pulse.

**Pixel Packing (FPGA):** `FSM_8to16` assembles the received bytes into 12-bit RGB444 pixels, `{1st_byte[3:0], 2nd_byte}`, and raises `data_ready` for each completed pixel.

**On-Chip Storage:** A dual-port Block RAM (`blk_mem_gen_0`) holds the frame. Port A is the write side (SPI data) and port B is the read side (VGA), so reception and display run independently.

**Display:** `VGA_Controller` generates `Hsync`, `Vsync`, `video_on` and a 25 MHz pixel tick for 640x480 @ 60 Hz. `Rd_Address` walks through the RAM in step with the beam, and an output mux blanks `RGB[11:0]` outside the visible region.

## Block Diagram

![Block diagram](docs/block_diagram.png)

![Elaborated design (Vivado)](docs/elaborated_design.png)

## Data Format

160x120 pixels, RGB444, 30 fps, 30 packets per frame (900 packets/s).

| Bytes | Content |
|---|---|
| 0 | `frame_id` (0-255, wraps) |
| 1 | `start_line` (0, 4, 8, ... 116) |
| 2-3 | Spare (0) |
| 4-1283 | 4 lines x 160 pixels x 2 bytes |

Per pixel, 2 bytes: `0000 R3 R2 R1 R0` then `G3 G2 G1 G0 B3 B2 B1 B0`.

Each packet is 1284 bytes, so the SPI link carries about 9.2 Mbit/s at 900 packets/s. The ESP32 SPI clock is set to 20 MHz (10 MHz is recommended for first bring-up).

## Tools and Technologies

| Item | Details |
|---|---|
| FPGA board | Digilent Basys 3 (Artix-7, xc7a35tcpg236-1) |
| HDL | Verilog |
| FPGA toolchain | Xilinx Vivado 2025.2 |
| Microcontroller | ESP32 (Arduino-ESP32 core, FreeRTOS tasks, SPI master with DMA) |
| Host software | Python 3, OpenCV, NumPy |
| Transport | UDP over Wi-Fi, then SPI (mode 0) |
| Display | VGA monitor, 640x480 @ 60 Hz |

## RTL Design Modules

| Instance | Module | Purpose |
|---|---|---|
| dut1 | `SPI_Rx` | SPI slave receiver, outputs `data[7:0]` and `data_valid` |
| dut2 | `FSM_8to16` | Packs received bytes into a 12-bit pixel, outputs `data_mem[11:0]` and `data_ready` |
| dut3 | `Wr_Address` | Write address counter (`wr_address[14:0]`) and write enable `wr_enb` |
| dut4 | `blk_mem_gen_0` | Dual-port block RAM IP (12-bit data, 15-bit address) |
| dut5 | `VGA_Controller` | `Hsync`, `Vsync`, `video_on` and the 25 MHz pixel tick |
| dut6 | `Rd_Address` | Read address generator (`rd_address[14:0]`) |
| - | `TOP` | Connects all modules and drives `RGB[11:0]`, `Hsync`, `Vsync` |

## Repository Structure

```
├── rtl/                      Verilog sources
├── ip/                       blk_mem_gen_0.xci
├── constraints/              basys3.xdc
├── sim/                      Testbenches
├── host/webcam.py            Webcam capture and UDP sender
├── esp32/esp32_spi_bridge/   ESP32 Wi-Fi to SPI firmware (esp32_spi_bridge.ino)
├── docs/                     Diagrams, waveforms, demo media
└── README.md
```

## Hardware Setup

| Signal | ESP32 | Basys 3 |
|---|---|---|
| MOSI | GPIO23 | `<Pmod pin>` |
| SCLK | GPIO18 | `<Pmod pin>` |
| CS | GPIO5 | `<Pmod pin>` |
| GND | GND | GND (mandatory, keep wires short) |
| READY (optional) | GPIO4 | `<Pmod pin>`, only if `USE_READY` is set to 1 |

Both boards use 3.3 V logic, so no level shifting is needed.

## How to Run

**1. FPGA**
1. Open the project in Vivado 2025.2 with the Basys 3 board part.
2. Add the sources from `rtl/`, the IP from `ip/` and the constraints from `constraints/`. Generate output products for `blk_mem_gen_0`.
3. Set `TOP` as the top module, run Synthesis, Implementation and Generate Bitstream, then program the board.

**2. ESP32**
1. Open `esp32/esp32_spi_bridge/esp32_spi_bridge.ino` in the Arduino IDE with the ESP32 board package installed.
2. Change `AP_PASS` to your own password. For router mode, set `USE_AP` to 0 and fill in `STA_SSID` and `STA_PASS` (do not commit real credentials).
3. Upload and open the Serial Monitor at 115200 baud. It prints packet statistics once per second and should show about 900 packets/s when streaming.

**3. PC**
1. Install dependencies: `pip install opencv-python numpy`
2. Connect your PC to the ESP32 Wi-Fi network (default SSID `ESP32-VIDEO`).
3. Run the sender:

```
python host/webcam.py                    # webcam, ESP32 in AP mode (192.168.4.1)
python host/webcam.py --test             # moving colour bars, no camera needed
python host/webcam.py --ip 192.168.1.50  # ESP32 in STA mode
python host/webcam.py --preview          # local preview window (adds latency)
```

`--test` is useful for bring-up: it checks the whole Wi-Fi, SPI and VGA chain without involving the camera.

## Testing and Verification

**Behavioral simulation:** Testbenches in `sim/` check `SPI_Rx` byte reception, `FSM_8to16` pixel packing and the write and read address counters.

## Results

<img width="548" height="412" alt="test_image" src="https://github.com/user-attachments/assets/995b0247-9862-4d8d-9487-a46b18b5bb43" />


## Resource utilization from the Vivado report:

<img width="486" height="355" alt="Screenshot 2026-10-30 233722" src="https://github.com/user-attachments/assets/edacad9e-5504-44b3-ab83-3fdb0ffa7c59" />


