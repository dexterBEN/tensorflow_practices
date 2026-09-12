# Exo 0 — Person Detection : récapitulatif détaillé jusqu'au flux vidéo WebRTC fonctionnel

## Architecture overview

<img width="1672" height="941" alt="image" src="https://github.com/user-attachments/assets/6b031415-fdff-406a-9b32-8ac444741e31" />


## 1. Objectif initial

L’objectif du projet `exo_0_detection` est de construire progressivement une petite application de détection de personne autour d’une **PYNQ-Z2**, d’une **caméra USB Tenveo**, de **Flutter Web** et, à terme, de **TensorFlow / TensorFlow Lite**.

L’idée générale est la suivante :

```text
Caméra USB
   │
   ▼
PYNQ-Z2
   │
   ├── Capture vidéo
   ├── Traitement / détection de personne
   └── Envoi des résultats
          │
          ▼
     Application Flutter Web
```

Cependant, afin de ne pas mélanger plusieurs problèmes à la fois, le travail a été volontairement séparé en deux flux indépendants :

```text
                      Flutter Web
                           │
             ┌─────────────┴─────────────┐
             │                           │
             ▼                           ▼
        Flux vidéo                  Détection
         WebRTC                     de personne
             │                           │
         VideoView                  DetectionBloc
             │                           │
         PYNQ-Z2                DetectionRepository
                                         │
                                  Mock au départ
```

Le premier objectif concret a donc été :

> **Afficher dans Flutter Web le flux vidéo réel de la caméra USB branchée sur la PYNQ-Z2, avec une latence faible, avant de commencer l’intégration TensorFlow.**

À l’état actuel :

- le flux vidéo réel fonctionne ;
- Flutter affiche correctement la caméra ;
- le statut vidéo passe à `Connected` ;
- la partie détection est encore simulée avec un `MockDetectionRepository` ;
- TensorFlow n’est pas encore intégré ;
- le FPGA/PL n’est pas encore utilisé pour le traitement vidéo.

## 2. Structure du projet

```text
tensorflow_practices/
└── exo_0_detection/
    ├── front_app/
    │   └── application Flutter Web
    └── notebooks/
        ├── camera_test.ipynb
        └── webrtc_stream.ipynb
```

Répartition actuelle :

```text
camera_test.ipynb
    └── tests caméra / OpenCV

webrtc_stream.ipynb
    └── capture caméra + GStreamer + WebRTC + signaling

front_app/
    ├── UI Flutter
    ├── VideoView
    ├── WebRtcVideoRepository
    ├── DetectionBloc
    └── MockDetectionRepository
```

## 3. Première étape : valider l’accès à la caméra

La caméra Tenveo USB est visible sous Linux avec :

```text
/dev/video0
/dev/video1
```

Le test OpenCV a montré que `/dev/video0` est exploitable alors que `/dev/video1` ne fonctionne pas correctement avec OpenCV.

Résultat du test :

```text
Opened: True
Captured: True
Shape: (480, 640, 3)
```

Chaîne validée :

```text
Caméra Tenveo USB
       │
       ▼
   /dev/video0
       │
       ▼
    OpenCV
       │
       ▼
   Frame valide
```

### Première image sombre

La première image était très sombre. Le problème venait du temps nécessaire à l’auto-exposition de la caméra.

Solution :

1. ouvrir la caméra ;
2. attendre environ 2 secondes ;
3. ignorer quelques premières frames ;
4. afficher ensuite une frame stabilisée.

## 4. Permissions Linux sur `/dev/video0`

L’utilisateur `xilinx` n’avait pas initialement les droits nécessaires.

Le périphérique était associé au groupe `video`. La bonne solution a été d’ajouter l’utilisateur au groupe :

```bash
sudo usermod -aG video xilinx
```

Après reconnexion :

```text
/dev/video0
   │
   └── groupe : video
           │
           ▼
        xilinx
           │
           ▼
    accès caméra OK
```

Cela évite une mauvaise pratique comme `chmod 777`.

## 5. Choix du protocole vidéo

Trois options ont été étudiées :

- **MJPEG** : simple à mettre en place, mais moins adapté à une application faible latence finale ;
- **RTSP** : très courant côté vidéo, mais non lisible directement par un navigateur Web ;
- **WebRTC** : faible latence et support natif navigateur.

Le choix final a été **WebRTC**.

Le signaling est séparé :

```text
             SIGNALING
Flutter  <──────────────>  PYNQ
       WebSocket / SDP / ICE

               VIDEO
Flutter  <──────────────  PYNQ
           WebRTC / RTP
```

Le WebSocket ne transporte pas les images ; il transporte seulement SDP et ICE.

## 6. Installation et validation de GStreamer

GStreamer n’était pas totalement prêt sur le PYNQ. Les composants nécessaires ont été installés, notamment :

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

Version :

```text
GStreamer 1.20.1
```

Plugins validés :

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

## 7. Tests de performances vidéo

Avant WebRTC, plusieurs pipelines ont été testés.

### MJPEG direct

Caméra :

```text
640x480 @ 30 FPS
```

Résultat : environ `29.5 FPS`.

### VP8

Pipeline :

```text
MJPEG → jpegdec → videoconvert → I420 → vp8enc
```

Résultats :

```text
~20 FPS en 640x480
~22.5 FPS en 640x360
```

### H.264 avec x264

Pipeline :

```text
MJPEG → jpegdec → videoconvert → I420 → x264enc
```

Résultat : environ `25 FPS`.

En limitant à **15 FPS**, le pipeline tenait le temps réel de manière confortable.

Pipeline retenu :

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

Paramètres importants :

```text
bitrate=800
key-int-max=30
tune=zerolatency
speed-preset=ultrafast
profile=constrained-baseline
```

Ce choix garde aussi de la marge CPU pour la future détection TensorFlow.

## 8. Obstacle majeur : liaison RTP → `webrtcbin`

La première approche consistait à tout construire avec `Gst.parse_launch(...)`, mais GStreamer refusait de relier automatiquement le payloader RTP à `webrtcbin`.

```text
rtph264pay
    │
    X
    │
webrtcbin
```

### Technique de débogage

Les pads et caps ont été inspectés séparément.

`webrtcbin` exposait :

```text
sink_%u
direction: sink
presence: request
caps: application/x-rtp
```

Le payloader exposait bien :

```text
application/x-rtp
media=video
encoding-name=H264
clock-rate=90000
```

Les deux étaient donc compatibles.

### Solution

Créer `webrtcbin` séparément, demander son request pad et relier manuellement :

```python
sink_pad = webrtc.request_pad_simple("sink_%u")
src_pad = payloader.get_static_pad("src")
result = src_pad.link(sink_pad)
```

Résultat :

```text
GST_PAD_LINK_OK
Camera pipeline created: OK
WebRTC element created: OK
WebRTC sink pad: sink_0
RTP -> WebRTC: ok
```

## 9. Mise en place du signaling WebSocket

Serveur Python sur la PYNQ :

```text
ws://0.0.0.0:8765
```

Flutter se connecte à :

```text
ws://192.168.200.111:8765
```

Rôles :

```text
PYNQ = offerer
Flutter = answerer
```

Séquence :

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
   │========== WebRTC média =============│
```

## 10. Problème de lifecycle Jupyter

Le serveur WebSocket avait parfois été créé avant une redéfinition de `handle_client`. Jupyter conservait l’ancienne référence.

La procédure de test est donc devenue :

```text
Restart Kernel
    ↓
Run All
    ↓
attendre le démarrage du serveur
    ↓
lancer Flutter
```

Cela garantit un état propre.

## 11. Bug `pipeline_started` non défini

Erreur :

```text
NameError: name 'pipeline_started' is not defined
```

Le handler utilisait la variable sans initialisation.

Solution :

```python
pipeline_started = False
```

avant la définition du handler.

## 12. Gestion du reload Flutter

Lors d’un refresh, le serveur affichait :

```text
ConnectionClosedError
received 1005
```

Ce n’était pas un crash du pipeline, mais la fermeture de la WebSocket par le navigateur.

Solution :

```python
except ConnectionClosed:
    print("Flutter WebSocket closed")
```

## 13. Première négociation SDP complète

Logs obtenus :

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

Cela a validé :

```text
WebSocket                   OK
Création SDP offer          OK
Envoi offer vers Flutter    OK
Réception SDP answer        OK
Application answer          OK
```

Mais la vidéo n’était toujours pas visible.

## 14. Erreur Flutter : `Unexpected null value`

Chrome DevTools a montré :

```text
WebSocket connected
SDP offer received
Remote video track received
Remote description set
SDP answer sent
Video connection error: Unexpected null value
```

Le problème était côté Flutter.

Certaines propriétés ICE (`candidate`, `sdpMid`, `sdpMLineIndex`) peuvent être null. Une assertion `!` incorrecte provoquait l’erreur.

Solution :

```text
candidate null/empty
    └── ignorer proprement

sdpMLineIndex null
    └── fallback à 0
        car une seule m-line vidéo existe
```

Après correction :

```text
Received: ice
Remote ICE candidate added
```

Flutter envoyait enfin ses candidats ICE au PYNQ.

## 15. Ajout de logs détaillés ICE / WebRTC

Des callbacks ont été ajoutés pour suivre :

```text
PYNQ ICE gathering state
PYNQ ICE connection state
PYNQ WebRTC connection state
```

On observait alors :

```text
PYNQ ICE connection state: checking
PYNQ WebRTC connection state: connecting
```

Les candidats complets ont aussi été loggés.

PYNQ :

```text
candidate ... 192.168.200.111 ... typ host
candidate ... 192.168.2.99 ... typ host
```

Flutter/Chrome :

```text
candidate ... xxxxxxxx-xxxx-xxxx.local ... typ host
```

## 16. Obstacle mDNS

Chrome masquait l’IP locale derrière un nom mDNS de type :

```text
7d06e84f-2dbd-4fa6-8504-075f92a6ca26.local
```

Tests sur PYNQ :

```bash
getent hosts <hostname>.local
ping <hostname>.local
```

Résultat : aucun nom résolu.

## 17. Installation d’Avahi

Au départ :

```text
avahi-daemon.service could not be found
hosts: files dns
```

Installation :

```bash
sudo apt install -y avahi-daemon avahi-utils libnss-mdns
sudo systemctl enable --now avahi-daemon
```

Après cela :

```text
avahi-daemon.service : active (running)
hosts: files mdns4_minimal [NOTFOUND=return] dns
```

Le PYNQ s’annonçait comme :

```text
pynq.local
```

## 18. Avahi ne résolvait toujours pas Chrome

Même après installation :

```bash
avahi-resolve-host-name -4 <chrome-hostname>.local
```

retournait :

```text
Timeout reached
```

Cela a déplacé le diagnostic vers la topologie réseau.

## 19. Découverte du NAT VirtualBox

Dans Ubuntu :

```bash
ip -br addr
```

donnait :

```text
enp0s3    10.0.2.15/24
```

La VM était derrière le NAT VirtualBox.

Topologie :

```text
Flutter / Chrome dans Ubuntu VM
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

Le WebSocket TCP sortant fonctionnait, mais WebRTC avait besoin d’un chemin UDP direct entre les peers.

## 20. Identification de l’interface Windows

PowerShell a permis d’identifier :

```text
Ethernet 3
Realtek USB GbE Family Controller
Status: Up
```

Puis :

```text
Windows : 192.168.200.112/24
PYNQ    : 192.168.200.111/24
```

Le `Realtek USB GbE Family Controller` était donc l’interface physique à utiliser.

## 21. Solution réseau : deuxième carte VirtualBox en Bridge

L’adaptateur 1 a été gardé en NAT pour Internet.

Un Adapter 2 a été ajouté :

```text
Mode : Accès par pont / Bridged Adapter
Nom  : Realtek USB GbE Family Controller
Type : Intel PRO/1000 MT Desktop
Câble branché : oui
```

Nouvelle topologie :

```text
                          Internet
                             │
                      Adapter 1 : NAT
                             │
                      Ubuntu 10.0.2.15


PYNQ                    Windows                   Ubuntu VM
192.168.200.111 ───── 192.168.200.112 ───── 192.168.200.110
                           Ethernet            Adapter 2 Bridge
```

Après redémarrage :

```text
enp0s3   10.0.2.15/24
enp0s8   192.168.200.110/24
```

## 22. Validation du routage direct

Test :

```bash
ping -c 3 192.168.200.111
```

Résultat :

```text
0% packet loss
```

Puis :

```bash
ip route get 192.168.200.111
```

Résultat :

```text
192.168.200.111 dev enp0s8 src 192.168.200.110
```

Le trafic passait bien par l’interface bridgée.

## 23. Résultat final

Après le changement réseau, le flux vidéo réel s’est affiché dans Flutter avec le statut :

```text
Connected
```

Chaîne complète :

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
│ IMAGE CAMERA RÉELLE   │
└───────────────────────┘
```

Le signaling fonctionne en parallèle :

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

## 24. Techniques de débogage les plus utiles

### Isoler chaque couche

Au lieu de déboguer « WebRTC » comme un bloc :

```text
Caméra
→ OpenCV
→ GStreamer
→ Encodeur
→ RTP
→ WebRTC
→ WebSocket
→ SDP
→ ICE
→ Réseau
→ Flutter
```

chaque couche a été testée séparément.

### Lire les états au lieu de deviner

Exemples :

```text
Opened: True
Captured: True
RTP -> WebRTC: ok
Received: answer
Received: ice
ICE state: checking
```

Chaque log réduisait l’espace de recherche.

### Inspecter les pads/caps GStreamer

Cela a permis de distinguer un problème d’auto-link d’un problème de compatibilité de codec.

### Utiliser Chrome DevTools

La console a permis d’identifier immédiatement le bug `Unexpected null value` côté Flutter.

### Logger les candidats ICE complets

Cela a révélé que Chrome envoyait un nom `.local`, donc un problème mDNS/réseau.

### Tester le réseau indépendamment de WebRTC

Commandes clés :

```bash
ip -br addr
ip route
ip route get 192.168.200.111
ping 192.168.200.111
```

### Tester mDNS indépendamment du code

```bash
getent hosts xxxxx.local
ping xxxxx.local
avahi-resolve-host-name -4 xxxxx.local
```

### Ne changer qu’une couche à la fois

Pendant le diagnostic réseau, le codec, le pipeline caméra, le BLoC et la détection n’ont pas été modifiés.

## 25. Tableau synthétique des obstacles

| Étape | Problème | Diagnostic | Solution |
|---|---|---|---|
| Caméra | première image sombre | auto-exposition | attendre / ignorer quelques frames |
| Linux | permissions `/dev/video0` | groupe `video` | ajouter `xilinx` au groupe |
| GStreamer | plugins WebRTC incomplets | `gst-inspect` | installer plugins / GI / nice |
| RTP → WebRTC | auto-link impossible | inspection pads/caps | request pad + link manuel |
| Jupyter | anciens callbacks | état persistant kernel | Restart Kernel + Run All |
| Python | `pipeline_started` absent | traceback | initialiser `False` |
| WebSocket | erreur 1005 au reload | fermeture normale navigateur | capturer `ConnectionClosed` |
| Flutter | `Unexpected null value` | DevTools | gérer ICE nullable |
| ICE | reste sur `checking` | logs d’états | logger candidats complets |
| mDNS | `.local` non résolu | `getent`, `avahi-resolve` | installer Avahi |
| Réseau | Avahi timeout malgré tout | `ip -br addr` | découverte NAT VirtualBox |
| VirtualBox | VM isolée en `10.0.2.15` | routage | ajouter adaptateur bridgé |
| Réseau final | besoin chemin direct | ping + route | VM `192.168.200.110` |
| Résultat | aucune vidéo | toutes couches corrigées | WebRTC connecté ✅ |

## 26. Architecture actuelle

```text
                               ┌─────────────────────────┐
                               │ Flutter Web             │
                               │ Chrome                  │
                               │ 192.168.200.110         │
                               └───────────┬─────────────┘
                                           │
                  ┌────────────────────────┴────────────────────────┐
                  │                                                 │
                  │ WebRTC vidéo                                    │ WebSocket
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

## 27. Ce qui reste à faire

Le transport vidéo est maintenant fonctionnel, mais l’application complète de détection ne l’est pas encore.

Étapes logiques :

1. stabiliser le lifecycle WebRTC ;
2. améliorer la reconnexion après reload ;
3. mieux gérer timeouts et erreurs ;
4. conserver le flux vidéo indépendant ;
5. remplacer progressivement `MockDetectionRepository` par la vraie détection TensorFlow/TFLite ;
6. envoyer les métadonnées de détection vers Flutter ;
7. plus tard seulement, envisager l’accélération FPGA.

## 28. Attention future : ne pas ouvrir `/dev/video0` deux fois

À l’arrivée de TensorFlow, il faudra éviter :

```text
WebRTC    ──► /dev/video0
TensorFlow──► /dev/video0
```

Une architecture plus saine sera :

```text
                  /dev/video0
                       │
                       ▼
                Capture unique
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

État actuel :

```text
Caméra USB                  ✅
Capture Linux               ✅
GStreamer                   ✅
H.264                       ✅
RTP                         ✅
webrtcbin                   ✅
WebSocket signaling         ✅
SDP offer / answer          ✅
ICE candidates              ✅
mDNS / réseau               ✅
VirtualBox bridge           ✅
Flutter WebRTC              ✅
Vidéo réelle affichée       ✅
TensorFlow                  ⏳
Détection réelle            ⏳
Accélération FPGA           ⏳
```

La principale leçon technique de cette phase est la méthode de débogage :

```text
Observer
   ↓
Isoler une couche
   ↓
Ajouter un log précis
   ↓
Tester indépendamment
   ↓
Confirmer une hypothèse
   ↓
Modifier une seule chose
   ↓
Recommencer
```

Le problème paraissait initialement être « la vidéo ne s’affiche pas », mais plusieurs problèmes indépendants se cumulaient :

```text
permissions Linux
+ plugins GStreamer
+ request pads WebRTC
+ lifecycle Jupyter
+ null safety Flutter
+ ICE
+ mDNS
+ NAT VirtualBox
```

Les traiter un par un a permis d’arriver à une architecture fonctionnelle, mais surtout compréhensible.

**État actuel : le flux caméra PYNQ → Flutter Web via WebRTC fonctionne.**
