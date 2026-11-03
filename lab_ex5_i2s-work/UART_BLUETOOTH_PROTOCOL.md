# Bluetooth UART control protocol

UART settings: **9600 baud, 8 data bits, no parity, 1 stop bit (8N1)**.

## Phone to FPGA

Each command is four bytes:

```
A5 CMD ARG CHECK
```

`CHECK = A5 XOR CMD XOR ARG`.

| CMD | Meaning | ARG |
|---|---|---|
| `01` | Query status | `00` |
| `02` | Play one image and enter manual mode | Image number `01`-`10` hex (1-16 decimal) |
| `03` | Enable automatic playback | `00` |
| `04` | Next image and enter manual mode | `00` |
| `05` | Previous image and enter manual mode | `00` |
| `06` | Enter manual mode without changing image | `00` |
| `07` | Set transition effect | `00`=cut, `01`=fade, `02`=slide |
| `08` | Set brightness | Level `00`-`09` |
| `09` | Set contrast | Level `00`-`09` |
| `0A` | Clear phone notice | `00` |
| `0B` | Set current image size | `00`=640×480, `01`=512×384, `02`=320×240 |
| `0C` | Set current image aspect ratio | `00`=original, `01`=4:3, `02`=16:9, `03`=1:1 |
| `0D` | Select music track by numeric filename prefix | `01`-`10` hex (1-16 decimal); ignored if no matching WAV |
| `0E` | Set music playback | `00`=pause, `01`=play |
| `0F` | Set lyric display | `00`=off, `01`=on |
| `10` | Set title display | `00`=off, `01`=on |
| `11` | Previous available music track | `00` |
| `12` | Next available music track | `00` |
| `13` | Cycle transition effect | `00` |
| `14` / `15` | Brightness up / down | `00`; clamp at 0/9 |
| `16` / `17` | Contrast up / down | `00`; clamp at 0/9 |
| `18` | Cycle current image size | `00` |
| `19` | Cycle current image aspect ratio | `00` |
| `1A` | Toggle lyric display | `00` |
| `1B` | Toggle title display | `00` |
| `1C` | Toggle music playback | `00` |

ASRPRO sends the same 9600 8N1 four-byte commands to J1 GPIOA2 (G12).
J1 GPIOA3 (F13) returns the first `5A 81` image-state frame after each valid
ASRPRO command to its RX pin. See [ASRPRO_VOICE_CONTROL.md](ASRPRO_VOICE_CONTROL.md)
for the crossed TX/RX wiring. W02 continues to receive all status frames.

## Gesture FPGA UART

The separate gesture FPGA uses 3.3 V TTL UART at 9600 baud, 8N1. Connect its
J2 pin 19 (GPIOB16/G1, TX) to this board's J1 pin 5 (GPIOA4/H13, `gesture_rx`),
and connect both boards' grounds (sender J2 pin 12 to receiver J1 pin 12).
Do not connect a 5 V UART output to these GPIO pins. The boards use their own
clocks; no clock wire is needed.

The gesture board sends `A5 CODE ~CODE 5A`. Right wave `A5 04 FB 5A` selects
the next image/page; left wave `A5 03 FC 5A` selects the previous image/page.
Open hand `A5 01 FE 5A`, fist `A5 02 FD 5A`, and no target `A5 00 FF 5A`
are accepted but do not change the display. Only left and right waves change
the page. Frames with a wrong complement or terminator are ignored. The link
uses only TX→RX and ground; there is no heartbeat or acknowledgement.

Examples:

```
A5 01 00 A4    query
A5 02 03 A4    play image 3
A5 03 00 A6    automatic playback
```

## FPGA to phone

The FPGA sends an eight-byte state frame after a query and whenever the queue,
current image, or playback mode changes. It also repeats the latest state once
per second so the link recovers automatically after Bluetooth reconnects:

```
5A 81 COUNT CURRENT FLAGS MAP_L MAP_H CHECK
```

- `COUNT`: number of images in the queue (`00`-`10` hex).
- `CURRENT`: current image number, 1-based; zero means unavailable.
- `FLAGS[0]`: automatic playback.
- `FLAGS[1]`: TF directory scan finished.
- `MAP_H:MAP_L`: valid image bitmap; bit 0 represents image 1.
- `CHECK`: XOR of the first seven bytes.

The second frame reports image attributes:

```
5A 82 BRIGHTNESS CONTRAST EFFECT 00 00 CHECK
```

- `BRIGHTNESS`: brightness level `0`-`9`.
- `CONTRAST`: contrast level `0`-`9`.
- `EFFECT`: `0`=cut, `1`=fade, `2`=slide.

The third frame reports the phone notice state:

```
5A 83 FLAGS WIDTH_L WIDTH_H 00 00 CHECK
```

- `FLAGS[0]`: notice visible.
- `FLAGS[1]`: urgent red banner.
- `FLAGS[3:2]`: scrolling speed (`0` slow, `1` normal, `2` fast).
- `FLAGS[5:4]`: automatic clear time (`0` persistent, `1` 10 s, `2` 30 s, `3` 60 s).
- `WIDTH_H:WIDTH_L`: bitmap width in pixels (`0`-`512`).

The fourth frame reports the currently displayed image's geometry:

```
5A 84 SIZE ASPECT 00 00 00 CHECK
```

- `SIZE`: `0`=640×480, `1`=512×384, `2`=320×240.
- `ASPECT`: `0`=original, `1`=4:3, `2`=16:9, `3`=1:1.
- Both settings are stored per image. A change triggers a reload of that image.

The fifth frame reports music properties:

```
5A 85 TRACK COUNT FLAGS MAP_L MAP_H CHECK
```

- `TRACK`: current track's numeric filename prefix, 1-based; zero if unavailable.
- `COUNT`: number of recognized WAV tracks.
- `FLAGS[0]`: playing; `[1]`: lyric display enabled; `[2]`: title display enabled.
- `FLAGS[3]`: lyric bitmap loaded; `[4]`: title bitmap loaded.
- `MAP_H:MAP_L`: recognized WAV tracks; bit 0 means track `01`.
- Every status frame uses the XOR of its first seven bytes as `CHECK`.

## Phone notice bitmap

The browser renders Unicode text into a 512×16 monochrome bitmap, then sends:

```
A6 FLAGS WIDTH_L WIDTH_H DATA[1024] CHECK
```

- Bitmap storage is row-major, 64 bytes per row, MSB first.
- `CHECK` is the XOR of every previous byte in the frame.
- FPGA hides the banner while receiving and only commits it after checksum validation.
- An incomplete transfer times out after one second.

