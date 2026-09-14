# Exo 0 — Person Detection: detailed recap up to a working WebRTC video stream

## Architecture overview

<img width="1672" height="941" alt="image" src="https://github.com/user-attachments/assets/6b031415-fdff-406a-9b32-8ac444741e31" />


## 1. Initial objective

The objective of the `exo_0_detection` project is to progressively build a small person detection application using a **PYNQ-Z2**, a **Tenveo USB camera**, **Flutter Web** and, eventually, **TensorFlow / TensorFlow Lite**.

The general idea is as follows:

```text
USB camera
   │
   ▼
PYNQ-Z2
   │
   ├── Video capture
   ├── Processing / person detection
   └── Sending results
          │
          ▼
     Flutter Web application
```

However, to avoid mixing several problems at once, the work was deliberately split into two independent streams:

```text
                      Flutter Web
                           │
             ┌─────────────┴─────────────┐
             │                           │
             ▼                           ▼
        Video stream                  Detection
         WebRTC                     of persons
             │                           │
         VideoView                  DetectionBloc
             │                           │
         PYNQ-Z2                DetectionRepository
                                         │
                                  Mock initially
```

The first concrete objective was therefore:

> **Display the live video stream from the USB camera connected to the PYNQ-Z2 in Flutter Web, with low latency, before starting TensorFlow integration.**

At the current stage:

- the live video stream works;
- Flutter displays the camera feed correctly;
- the video status changes to `Connected`;
- detection is still simulated with a `MockDetectionRepository`;
- TensorFlow is not integrated yet;
- the FPGA/PL is not used for video processing yet.

## 2. Project structure

```text
tensorflow_practices/
└── exo_0_detection/
    ├── front_app/
    │   └── Flutter Web application
    └── notebooks/
        ├── camera_test.ipynb
        └── webrtc_stream.ipynb
```

Current responsibilities:

```text
camera_test.ipynb
    └── camera / OpenCV tests

webrtc_stream.ipynb
    └── camera capture + GStreamer + WebRTC + signaling

front_app/
    ├── Flutter UI
    ├── VideoView
    ├── WebRtcVideoRepository
    ├── DetectionBloc
    └── MockDetectionRepository
```

## 3. First step: validating camera access

The Tenveo USB camera is visible on Linux as:

```text
/dev/video0
/dev/video1
```

The OpenCV test showed that `/dev/video0` is usable, while `/dev/video1` does not work correctly with OpenCV.

Test result:

```text
Opened: True
Captured: True
Shape: (480, 640, 3)
```

Validated pipeline:

```text
Tenveo USB camera
       │
       ▼
   /dev/video0
       │
       ▼
    OpenCV
       │
       ▼
   Valid frame
```

### Dark first image

The first image was very dark. The issue was caused by the time needed for the camera's auto-exposure to adjust.

Solution:

1. open the camera;
2. wait about 2 seconds;
3. skip the first few frames;
4. then display a stabilized frame.

## 4. Linux permissions on `/dev/video0`

The `xilinx` user initially lacked the required permissions.

The device belonged to the `video` group. The correct solution was to add the user to that group:

```bash
sudo usermod -aG video xilinx
```

After logging in again:

```text
/dev/video0
   │
   └── group: video
           │
           ▼
        xilinx
           │
           ▼
    camera access OK
```

This avoids bad practices such as `chmod 777`.

## 5. Choosing the video protocol

Three options were considered:

- **MJPEG**: easy to set up, but less suited to the final low-latency application;
- **RTSP**: very common for video, but cannot be played directly by a web browser;
- **WebRTC**: low latency and native browser support.

The final choice was **WebRTC**.

Signaling is separate:

```text
             SIGNALING
Flutter  <──────────────>  PYNQ
       WebSocket / SDP / ICE

               VIDEO
Flutter  <──────────────  PYNQ
           WebRTC / RTP
```

The WebSocket does not carry images; it only carries SDP and ICE.

## 6. Installing and validating GStreamer

GStreamer was not fully set up on the PYNQ. The required components were installed, including:

```text
gstreamer1.0-tools
gstreamer1.0-plugins-base
gstreamer1.0-plugins-good
gstreamer1.0-plugins-bad
gstreamer1.0-plugins-ugly
python3-gi
gir1.2-gstreamer-1.0
gir1.2-gst-plugins-base-1.0
gir1.2-gst-plugins-bad-1.0
gstreamer1.0-nice
```

Version:

```text
GStreamer 1.20.1
```

Validated plugins:

```text
webrtcbin     OK
nicesrc       OK
nicesink      OK
dtlsenc       OK
dtlsdec       OK
srtpenc       OK
srtpdec       OK
rtpbin        OK
vp8enc        OK
rtpvp8pay     OK
x264enc       OK
h264parse     OK
rtph264pay    OK
```

## 7. Video performance tests

Several pipelines were tested before WebRTC.

### Direct MJPEG

Camera:

```text
640x480 @ 30 FPS
```

Result: about `29.5 FPS`.

### VP8

Pipeline:

```text
MJPEG → jpegdec → videoconvert → I420 → vp8enc
```

Results:

```text
~20 FPS at 640x480
~22.5 FPS at 640x360
```

### H.264 with x264

Pipeline:

```text
MJPEG → jpegdec → videoconvert → I420 → x264enc
```

Result: about `25 FPS`.

When limited to **15 FPS**, the pipeline comfortably maintained real-time operation.

Selected pipeline:

```text
v4l2src /dev/video0
        │
        ▼
MJPEG 640x480 @ 30 FPS
        │
        ▼
     jpegdec
        │
        ▼
    videorate
        │
        ▼
  640x480 @ 15 FPS
        │
        ▼
  videoconvert
        │
        ▼
      I420
        │
        ▼
     x264enc
  ultrafast / zerolatency
        │
        ▼
 constrained-baseline
        │
        ▼
    h264parse
        │
        ▼
   rtph264pay
        │
        ▼
     WebRTC
```

Important parameters:

```text
bitrate=800
key-int-max=30
tune=zerolatency
speed-preset=ultrafast
profile=constrained-baseline
```

This choice also leaves CPU headroom for future TensorFlow detection.

## 8. Major obstacle: linking RTP → `webrtcbin`

The first approach was to build everything with `Gst.parse_launch(...)`, but GStreamer refused to automatically link the RTP payloader to `webrtcbin`.

```text
rtph264pay
    │
    X
    │
webrtcbin
```

### Debugging technique

The pads and caps were inspected separately.

`webrtcbin` exposed:

```text
sink_%u
direction: sink
presence: request
caps: application/x-rtp
```

The payloader did expose:

```text
application/x-rtp
media=video
encoding-name=H264
clock-rate=90000
```

The two were therefore compatible.

### Solution

Create `webrtcbin` separately, request its request pad and link manually:

```python
sink_pad = webrtc.request_pad_simple("sink_%u")
src_pad = payloader.get_static_pad("src")
result = src_pad.link(sink_pad)
```

Result:

```text
GST_PAD_LINK_OK
Camera pipeline created: OK
WebRTC element created: OK
WebRTC sink pad: sink_0
RTP -> WebRTC: ok
```

## 9. Setting up WebSocket signaling

Python server on the PYNQ:

```text
ws://0.0.0.0:8765
```

Flutter connects to:

```text
ws://192.168.200.111:8765
```

Roles:

```text
PYNQ = offerer
Flutter = answerer
```

Sequence:

```text
Flutter                                PYNQ
   │                                     │
   │──── WebSocket connection ──────────►│
   │                                     │
   │◄──────── SDP Offer ─────────────────│
   │                                     │
   │───────── SDP Answer ────────────────►│
   │                                     │
   │◄──────── ICE Candidates ────────────│
   │───────── ICE Candidates ────────────►│
   │                                     │
   │========== WebRTC media =============│
```

## 10. Jupyter lifecycle issue

The WebSocket server had sometimes been created before `handle_client` was redefined. Jupyter kept the old reference.

The testing procedure therefore became:

```text
Restart Kernel
    ↓
Run All
    ↓
wait for the server to start
    ↓
start Flutter
```

This ensures a clean state.

## 11. Undefined `pipeline_started` bug

Error:

```text
NameError: name 'pipeline_started' is not defined
```

The handler used the variable without initializing it.

Solution:

```python
pipeline_started = False
```

before defining the handler.

## 12. Handling Flutter reloads

During a refresh, the server displayed:

```text
ConnectionClosedError
received 1005
```

This was not a pipeline crash, but the browser closing the WebSocket.

Solution:

```python
except ConnectionClosed:
    print("Flutter WebSocket closed")
```

## 13. First complete SDP negotiation

Resulting logs:

```text
Flutter client connected
Pipeline state: success
Negotiation needed
SDP offer created
Local ICE candidate
...
Received: answer
Remote SDP answer applied
```

This validated:

```text
WebSocket                   OK
SDP offer creation          OK
Sending offer to Flutter    OK
Receiving SDP answer        OK
Applying answer          OK
```

But the video was still not visible.

## 14. Flutter error: `Unexpected null value`

Chrome DevTools showed:

```text
WebSocket connected
SDP offer received
Remote video track received
Remote description set
SDP answer sent
Video connection error: Unexpected null value
```

The issue was on the Flutter side.

Some ICE properties (`candidate`, `sdpMid`, `sdpMLineIndex`) can be null. An incorrect `!` assertion caused the error.

Solution:

```text
candidate null/empty
    └── skip safely

sdpMLineIndex null
    └── fall back to 0
        because there is only one video m-line
```

After the fix:

```text
Received: ice
Remote ICE candidate added
```

Flutter was finally sending its ICE candidates to the PYNQ.

## 15. Adding detailed ICE / WebRTC logs

Callbacks were added to monitor:

```text
PYNQ ICE gathering state
PYNQ ICE connection state
PYNQ WebRTC connection state
```

The following states were then observed:

```text
PYNQ ICE connection state: checking
PYNQ WebRTC connection state: connecting
```

The full candidates were also logged.

PYNQ:

```text
candidate ... 192.168.200.111 ... typ host
candidate ... 192.168.2.99 ... typ host
```

Flutter/Chrome:

```text
candidate ... xxxxxxxx-xxxx-xxxx.local ... typ host
```

## 16. The mDNS obstacle

Chrome hid the local IP behind an mDNS name such as:

```text
7d06e84f-2dbd-4fa6-8504-075f92a6ca26.local
```

Tests on the PYNQ:

```bash
getent hosts <hostname>.local
ping <hostname>.local
```

Result: no names resolved.

## 17. Installing Avahi

Initially:

```text
avahi-daemon.service could not be found
hosts: files dns
```

Installation:

```bash
sudo apt install -y avahi-daemon avahi-utils libnss-mdns
sudo systemctl enable --now avahi-daemon
```

Afterward:

```text
avahi-daemon.service : active (running)
hosts: files mdns4_minimal [NOTFOUND=return] dns
```

The PYNQ advertised itself as:

```text
pynq.local
```

## 18. Avahi still could not resolve Chrome

Even after installation:

```bash
avahi-resolve-host-name -4 <chrome-hostname>.local
```

returned:

```text
Timeout reached
```

This shifted the investigation toward the network topology.

## 19. Discovering VirtualBox NAT

In Ubuntu:

```bash
ip -br addr
```

returned:

```text
enp0s3    10.0.2.15/24
```

The VM was behind VirtualBox NAT.

Topology:

```text
Flutter / Chrome in Ubuntu VM
           │
           │ 10.0.2.15
           ▼
     VirtualBox NAT
           │
           ▼
       Windows
           │
           ▼
        PYNQ-Z2
```

The outgoing TCP WebSocket worked, but WebRTC needed a direct UDP path between peers.

## 20. Identifying the Windows interface

PowerShell was used to identify:

```text
Ethernet 3
Realtek USB GbE Family Controller
Status: Up
```

Then:

```text
Windows : 192.168.200.112/24
PYNQ    : 192.168.200.111/24
```

The `Realtek USB GbE Family Controller` was therefore the physical interface to use.

## 21. Network solution: a second VirtualBox adapter in bridged mode

Adapter 1 was kept in NAT mode for Internet access.

An Adapter 2 was added:

```text
Mode: Bridged Adapter
Name : Realtek USB GbE Family Controller
Type : Intel PRO/1000 MT Desktop
Cable connected: yes
```

New topology:

```text
                          Internet
                             │
                      Adapter 1 : NAT
                             │
                      Ubuntu 10.0.2.15


PYNQ                    Windows                   Ubuntu VM
192.168.200.111 ───── 192.168.200.112 ───── 192.168.200.110
                           Ethernet            Adapter 2 Bridged
```

After restarting:

```text
enp0s3   10.0.2.15/24
enp0s8   192.168.200.110/24
```

## 22. Validating direct routing

Test:

```bash
ping -c 3 192.168.200.111
```

Result:

```text
0% packet loss
```

Then:

```bash
ip route get 192.168.200.111
```

Result:

```text
192.168.200.111 dev enp0s8 src 192.168.200.110
```

Traffic was correctly flowing through the bridged interface.

## 23. Final result

After the network change, the live video stream appeared in Flutter with the status:

```text
Connected
```

Complete pipeline:

```text
┌───────────────────────┐
│ Tenveo USB Camera     │
└──────────┬────────────┘
           │ USB
           ▼
┌───────────────────────┐
│ PYNQ-Z2               │
│ /dev/video0           │
└──────────┬────────────┘
           │
           ▼
┌───────────────────────┐
│ GStreamer             │
│                       │
│ MJPEG 640x480@30      │
│      ↓                │
│ jpegdec               │
│      ↓                │
│ videorate 15 FPS      │
│      ↓                │
│ videoconvert / I420   │
│      ↓                │
│ x264 H.264            │
│      ↓                │
│ h264parse             │
│      ↓                │
│ rtph264pay            │
└──────────┬────────────┘
           │ RTP
           ▼
┌───────────────────────┐
│ webrtcbin             │
│ ICE / DTLS / SRTP     │
└──────────┬────────────┘
           │ WebRTC / UDP
           ▼
┌───────────────────────┐
│ Ubuntu VM             │
│ 192.168.200.110       │
│ Chrome / Flutter Web  │
└──────────┬────────────┘
           │
           ▼
┌───────────────────────┐
│ RTCVideoView          │
│ Status: Connected     │
│ LIVE CAMERA IMAGE   │
└───────────────────────┘
```

Signaling runs in parallel:

```text
Flutter                           PYNQ
   │                                │
   │──── WebSocket connect ────────►│
   │◄──── SDP offer ────────────────│
   │──── SDP answer ───────────────►│
   │◄──── ICE candidates ───────────│
   │──── ICE candidates ───────────►│
   │====== WebRTC Connected ========│
```

## 24. Most useful debugging techniques

### Isolate each layer

Instead of debugging “WebRTC” as a single block:

```text
Camera
→ OpenCV
→ GStreamer
→ Encoder
→ RTP
→ WebRTC
→ WebSocket
→ SDP
→ ICE
→ Network
→ Flutter
```

each layer was tested separately.

### Read the states instead of guessing

Examples:

```text
Opened: True
Captured: True
RTP -> WebRTC: ok
Received: answer
Received: ice
ICE state: checking
```

Each log narrowed down the search.

### Inspect GStreamer pads/caps

This helped distinguish an automatic linking issue from a codec compatibility issue.

### Use Chrome DevTools

The console immediately identified the `Unexpected null value` bug on the Flutter side.

### Log the full ICE candidates

This revealed that Chrome was sending a `.local` name, pointing to an mDNS/network issue.

### Test the network independently of WebRTC

Key commands:

```bash
ip -br addr
ip route
ip route get 192.168.200.111
ping 192.168.200.111
```

### Test mDNS independently of the code

```bash
getent hosts xxxxx.local
ping xxxxx.local
avahi-resolve-host-name -4 xxxxx.local
```

### Change only one layer at a time

During the network investigation, the codec, camera pipeline, BLoC and detection were left unchanged.

## 25. Summary table of obstacles

| Stage | Problem | Diagnosis | Solution |
|---|---|---|---|
| Camera | dark first image | auto-exposure | wait / skip a few frames |
| Linux | `/dev/video0` permissions | `video` group | add `xilinx` to the group |
| GStreamer | incomplete WebRTC plugins | `gst-inspect` | install plugins / GI / nice |
| RTP → WebRTC | automatic linking failed | pads/caps inspection | request pad + manual link |
| Jupyter | old callbacks | persistent kernel state | Restart Kernel + Run All |
| Python | missing `pipeline_started` | traceback | initialize to `False` |
| WebSocket | error 1005 on reload | normal browser closure | catch `ConnectionClosed` |
| Flutter | `Unexpected null value` | DevTools | handle nullable ICE properties |
| ICE | stuck on `checking` | state logs | log full candidates |
| mDNS | unresolved `.local` | `getent`, `avahi-resolve` | install Avahi |
| Network | Avahi still times out | `ip -br addr` | discovery of VirtualBox NAT |
| VirtualBox | VM isolated at `10.0.2.15` | routing | add a bridged adapter |
| Final network | direct path needed | ping + route | VM `192.168.200.110` |
| Result | no video | all layers fixed | WebRTC connected ✅ |

## 26. Current architecture

```text
                               ┌─────────────────────────┐
                               │ Flutter Web             │
                               │ Chrome                  │
                               │ 192.168.200.110         │
                               └───────────┬─────────────┘
                                           │
                  ┌────────────────────────┴────────────────────────┐
                  │                                                 │
                  │ WebRTC video                                    │ WebSocket
                  │ RTP / SRTP / DTLS / ICE                         │ SDP / ICE
                  │                                                 │
                  ▼                                                 ▼
                               ┌─────────────────────────┐
                               │ PYNQ-Z2                 │
                               │ 192.168.200.111         │
                               └───────────┬─────────────┘
                                           │
                                       GStreamer
                                           │
                        ┌──────────────────┴─────────────────┐
                        │                                    │
                        ▼                                    ▼
                /dev/video0                          Future AI path
                        │                                    │
                        ▼                                    ▼
                 Tenveo Camera                       TensorFlow/TFLite
                                                             │
                                                             ▼
                                                     Detection metadata
                                                             │
                                                             ▼
                                                        Flutter BLoC
```

## 27. Remaining work

Video transport is now functional, but the full detection application is not yet.

Logical next steps:

1. stabilize the WebRTC lifecycle;
2. improve reconnection after reload;
3. improve timeout and error handling;
4. keep the video stream independent;
5. progressively replace `MockDetectionRepository` with real TensorFlow/TFLite detection;
6. send detection metadata to Flutter;
7. only later, consider FPGA acceleration.

## 28. Future consideration: do not open `/dev/video0` twice

When TensorFlow is introduced, avoid:

```text
WebRTC    ──► /dev/video0
TensorFlow──► /dev/video0
```

A better architecture will be:

```text
                  /dev/video0
                       │
                       ▼
                Single capture
                       │
                       ▼
                     tee
                ┌──────┴──────┐
                │             │
                ▼             ▼
          WebRTC branch    AI branch
                │             │
                ▼             ▼
             Flutter       TensorFlow
                              │
                              ▼
                        Detection metadata
```

## 29. Conclusion

Current state:

```text
USB camera                  ✅
Linux capture               ✅
GStreamer                   ✅
H.264                       ✅
RTP                         ✅
webrtcbin                   ✅
WebSocket signaling         ✅
SDP offer / answer          ✅
ICE candidates              ✅
mDNS / network               ✅
VirtualBox bridge           ✅
Flutter WebRTC              ✅
Live video displayed       ✅
TensorFlow                  ⏳
Real detection            ⏳
FPGA acceleration           ⏳
```

The main technical lesson from this phase is the debugging method:

```text
Observe
   ↓
Isolate a layer
   ↓
Add a precise log
   ↓
Test independently
   ↓
Confirm a hypothesis
   ↓
Change only one thing
   ↓
Repeat
```

The problem initially seemed to be “the video does not appear”, but several independent issues were adding up:

```text
Linux permissions
+ GStreamer plugins
+ WebRTC request pads
+ Jupyter lifecycle
+ Flutter null safety
+ ICE
+ mDNS
+ VirtualBox NAT
```

Addressing them one by one led to a working architecture that, above all, is understandable.

**Current state: the PYNQ → Flutter Web camera stream via WebRTC works.**
