# Exo 0 — Notebooks / PYNQ

Ce devcontainer prépare le travail notebooks/PYNQ et la future cross-compilation
de `tflite-runtime`. Il utilise Ubuntu 22.04 sur **x86_64 (linux/amd64)**,
avec le Python 3.10.x fourni par Ubuntu. Il est destiné à la VM x86_64 :
il n'émule pas le PYNQ et ne remplace pas son kernel Jupyter distant.
Les extensions Python et Jupyter permettent de travailler dans VS Code ;
la sélection du kernel distant reste manuelle.

Le PYNQ-Z2 possède un Cortex-A9 ARMv7-A avec NEON et VFPv3. Selon le diagnostic
réalisé sur la carte, le binaire `tflite-runtime 2.13.0` installé utilise VFPv4,
ce qui provoque `Illegal instruction` / SIGILL pendant `interpreter.invoke()`.
La future chaîne de cross-compilation devra produire des artefacts ARMv7
compatibles Cortex-A9 / VFPv3, depuis cet environnement x86_64.

Cette première étape installe uniquement les outils de préparation. Aucun
compilateur croisé ARM, sysroot, source TensorFlow ou script de build TFLite
n'est encore configuré. Aucun périphérique caméra ni connexion automatique
au PYNQ n'est ajouté.

Les paquets pip sont isolés dans `/opt/notebooks-venv`, créé avec
`/usr/bin/python3`. Ce répertoire est accessible à `vscode` et son `bin` est
placé dans le `PATH`. NumPy est fixé à 1.21.5. L'image de base, les paquets APT
et les autres paquets pip ne sont pas encore verrouillés : leur verrouillage
fera partie du futur travail de reproductibilité du build.

## Ouverture

Ouvrir le dossier `exo_0_detection/` dans VS Code, lancer **Dev Containers: Reopen in
Container**, puis sélectionner **Exo 0 - Notebooks / PYNQ** parmi les configurations.
La construction et l'exécution demandent explicitement `linux/amd64`.

## Validation après ouverture

```bash
uname -m
python3 --version
cmake --version
file --version
readelf --version
python3 -c "import numpy, pybind11; print(numpy.__version__); print(pybind11.__version__)"
```

Résultats attendus : `x86_64`, Python `3.10.x`, outils disponibles et NumPy `1.21.5`.
Ces vérifications portent sur les outils hôtes, pas sur un wheel ARMv7.

## Headers Python pour la cible ARMHF

Le build s'execute sur x86_64, mais le wrapper Python compile est destine au
PYNQ ARMv7. Le header commun `/usr/include/python3.10/pyconfig.h` selectionne
la configuration de la cible du compilateur : il a donc besoin de
`/usr/include/arm-linux-gnueabihf/python3.10/pyconfig.h`. Les seuls headers
amd64 ne suffisent pas.

Le Dockerfile active `armhf` avec `dpkg --add-architecture armhf`, limite les
depots Ubuntu standards a `amd64`, et configure les suites Jammy, updates,
security et backports sur `ports.ubuntu.com/ubuntu-ports` pour `armhf`.
Il installe `libpython3.10-dev:armhf` et ses dependances via APT, dans la meme
transaction que les outils natifs pour permettre la resolution des versions
multiarch. Cela ne remplace pas l'interpreteur hote du venv par un Python ARM.

Reference du package :
https://packages.ubuntu.com/jammy-updates/armhf/libpython3.10-dev/filelist

La construction du devcontainer verifie obligatoirement :

```bash
test -f /usr/include/arm-linux-gnueabihf/python3.10/pyconfig.h
```

Reconstruire avec **Dev Containers: Rebuild Container**, puis executer cette
commande dans le nouveau container. Ensuite seulement, relancer manuellement
`./tools/tflite_cortex_a9/build.sh` depuis `exo_0_detection/`.
Le venv `/opt/notebooks-venv` et NumPy 1.21.5 conservent leur configuration.
