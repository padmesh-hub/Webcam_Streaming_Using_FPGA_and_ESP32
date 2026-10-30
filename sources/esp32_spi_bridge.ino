/*
 * ESP32: Wi-Fi UDP receiver -> SPI master -> Basys 3
 *
 * Each UDP packet (1284 bytes) is forwarded unchanged as ONE SPI transaction
 * (CS low for the whole packet). The FPGA parses the 4-byte header itself.
 *
 * Wiring (default VSPI pins, direct IO_MUX path):
 *   GPIO23 MOSI -> Basys 3 Pmod pin (spi mosi)
 *   GPIO18 SCLK -> Basys 3 Pmod pin (spi sclk)
 *   GPIO5  CS   -> Basys 3 Pmod pin (spi cs_n)
 *   GND         -> Basys 3 GND   (mandatory, keep wires short)
 *   GPIO4  <- FPGA "ready" output (only if USE_READY is 1)
 *
 * Board package: Arduino-ESP32 (core 2.x or 3.x).
 */

#include <WiFi.h>
#include <lwip/sockets.h>
#include "esp_wifi.h"
#include "driver/spi_master.h"
#include "driver/gpio.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"

// ---------------- configuration ----------------
#define USE_AP 1                          // 1 = ESP32 makes its own network (IP 192.168.4.1)
                                          // 0 = join an existing router/hotspot

static const char *AP_SSID = "ESP32-VIDEO";
static const char *AP_PASS = "video12345";   // at least 8 characters
static const int   AP_CHANNEL = 1;           // use 1, 6 or 11; pick the least crowded

static const char *STA_SSID = "YOUR_WIFI_NAME";
static const char *STA_PASS = "YOUR_WIFI_PASSWORD";

static const uint16_t UDP_PORT = 5005;

#define PKT_SIZE    1284                  // 4 header + 1280 payload (must match sender)
#define NUM_SLOTS   16                    // packet buffers between Wi-Fi and SPI
#define SPI_CLK_HZ  20000000              // use 10000000 for first bring-up

#define PIN_MOSI    23
#define PIN_SCLK    18
#define PIN_CS      5

#define USE_READY   0                     // 1 = wait for FPGA ready pin before each packet
#define PIN_READY   4
// ------------------------------------------------

// Static arrays live in internal DRAM, which is DMA-capable.
static uint8_t slots[NUM_SLOTS][PKT_SIZE] __attribute__((aligned(4)));

static QueueHandle_t freeQ;     // indices of empty slots
static QueueHandle_t filledQ;   // indices of slots holding a packet
static spi_device_handle_t spiDev;

static volatile uint32_t cntRx = 0, cntSpi = 0, cntDropNoSlot = 0, cntBad = 0;

// Receives UDP packets straight into a free slot (no extra copy).
static void udpTask(void *)
{
  int sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
  struct sockaddr_in addr;
  memset(&addr, 0, sizeof(addr));
  addr.sin_family = AF_INET;
  addr.sin_port = htons(UDP_PORT);
  addr.sin_addr.s_addr = htonl(INADDR_ANY);
  bind(sock, (struct sockaddr *)&addr, sizeof(addr));

  struct timeval tv = {1, 0};
  setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

  static uint8_t trash[1500];

  for (;;) {
    uint8_t idx;
    if (xQueueReceive(freeQ, &idx, 0) == pdTRUE) {
      int n = recvfrom(sock, slots[idx], PKT_SIZE, 0, NULL, NULL);
      if (n == PKT_SIZE && slots[idx][1] < 120) {
        cntRx++;
        xQueueSend(filledQ, &idx, 0);
      } else {
        if (n > 0) cntBad++;                 // wrong size or bad line number
        xQueueSend(freeQ, &idx, 0);          // give the slot back (also on timeout)
      }
    } else {
      // SPI side is behind: drop this packet rather than block Wi-Fi
      int n = recvfrom(sock, trash, sizeof(trash), 0, NULL, NULL);
      if (n > 0) cntDropNoSlot++;
    }
  }
}

// Sends each queued packet to the FPGA as one DMA SPI transaction.
static void spiTask(void *)
{
  spi_transaction_t t;
  for (;;) {
    uint8_t idx;
    if (xQueueReceive(filledQ, &idx, portMAX_DELAY) != pdTRUE) continue;

#if USE_READY
    uint32_t t0 = millis();
    while (!gpio_get_level((gpio_num_t)PIN_READY) && (millis() - t0) < 5) {
      delayMicroseconds(50);
    }
#endif

    memset(&t, 0, sizeof(t));
    t.length = PKT_SIZE * 8;                 // length is in bits
    t.tx_buffer = slots[idx];
    spi_device_transmit(spiDev, &t);         // blocks (task sleeps) while DMA runs
    cntSpi++;

    xQueueSend(freeQ, &idx, 0);
  }
}

static void startWifi()
{
#if USE_AP
  WiFi.mode(WIFI_AP);
  WiFi.softAP(AP_SSID, AP_PASS, AP_CHANNEL);
  Serial.print("AP started, IP: ");
  Serial.println(WiFi.softAPIP());
#else
  WiFi.mode(WIFI_STA);
  WiFi.begin(STA_SSID, STA_PASS);
  while (WiFi.status() != WL_CONNECTED) {
    delay(200);
    Serial.print(".");
  }
  Serial.print("\nConnected, IP: ");
  Serial.println(WiFi.localIP());
#endif
  esp_wifi_set_ps(WIFI_PS_NONE);             // power save off: avoids latency spikes
}

static void startSpi()
{
  spi_bus_config_t bus;
  memset(&bus, 0, sizeof(bus));
  bus.mosi_io_num = PIN_MOSI;
  bus.miso_io_num = -1;
  bus.sclk_io_num = PIN_SCLK;
  bus.quadwp_io_num = -1;
  bus.quadhd_io_num = -1;
  bus.max_transfer_sz = PKT_SIZE;
  ESP_ERROR_CHECK(spi_bus_initialize(SPI3_HOST, &bus, SPI_DMA_CH_AUTO));

  spi_device_interface_config_t dev;
  memset(&dev, 0, sizeof(dev));
  dev.clock_speed_hz = SPI_CLK_HZ;
  dev.mode = 0;                              // CPOL=0, CPHA=0, MSB first
  dev.spics_io_num = PIN_CS;                 // hardware CS, low for whole transaction
  dev.queue_size = 2;
  ESP_ERROR_CHECK(spi_bus_add_device(SPI3_HOST, &dev, &spiDev));
}

void setup()
{
  Serial.begin(115200);
  delay(300);

#if USE_READY
  pinMode(PIN_READY, INPUT_PULLDOWN);
#endif

  freeQ = xQueueCreate(NUM_SLOTS, sizeof(uint8_t));
  filledQ = xQueueCreate(NUM_SLOTS, sizeof(uint8_t));
  for (uint8_t i = 0; i < NUM_SLOTS; i++) xQueueSend(freeQ, &i, 0);

  startWifi();
  startSpi();

  xTaskCreatePinnedToCore(spiTask, "spi", 4096, NULL, 5, NULL, 1);
  xTaskCreatePinnedToCore(udpTask, "udp", 4096, NULL, 6, NULL, 1);
}

void loop()
{
  // Stats once per second. Never print per packet: it would stall reception.
  static uint32_t lastRx = 0;
  delay(1000);
  uint32_t rx = cntRx;
  Serial.printf("rx %lu pkt/s (expect 900) | spi total %lu | drop(no slot) %lu | bad %lu\n",
                (unsigned long)(rx - lastRx), (unsigned long)cntSpi,
                (unsigned long)cntDropNoSlot, (unsigned long)cntBad);
  lastRx = rx;
}
