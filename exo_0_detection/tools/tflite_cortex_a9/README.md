# tflite-runtime 2.13.0 — Cortex-A9 / PYNQ-Z2

Le diagnostic effectué sur le PYNQ indique que son wheel ARM officiel 2.13.0
utilise VFPv4 alors que le Cortex-A9 du Zynq-7020 expose ARMv7-A, NEON et VFPv3.
Des instructions VFPv4 non supportées peuvent provoquer SIGILL / « Illegal
instruction » pendant `interpreter.invoke()`. VFPv4 ajoute notamment des
instructions flottantes fusionnées absentes de VFPv3.

Le patch ajoute une cible `armhf_vfpv3` sans changer la cible `armhf` historique.
Il reprend conceptuellement la séparation des cibles des versions plus récentes :
la nouvelle branche réutilise le téléchargement GCC ARM 8.3 et les chemins
inclus de `armhf`, mais remplace uniquement, dans les flags retournés pour cette
nouvelle cible, `neon-vfpv4` par `neon-vfpv3`. Les flags sont donc
`-march=armv7-a -mfpu=neon-vfpv3 -funsafe-math-optimizations`.
La branche CMake conserve Linux, armv7 et XNNPACK désactivé.
La plateforme de packaging reste `linux-armv7l` (`linux_armv7l` dans le nom du wheel).

Références de la version ciblée :
- https://github.com/tensorflow/tensorflow/blob/v2.13.0/tensorflow/lite/tools/cmake/download_toolchains.sh
- https://github.com/tensorflow/tensorflow/blob/v2.13.0/tensorflow/lite/tools/pip_package/build_pip_package_with_cmake.sh

## Ouvrir et construire manuellement

Ouvrir `exo_0_detection/` dans VS Code, choisir **Dev Containers: Reopen in
Container**, puis **Exo 0 - Notebooks / PYNQ**. Exécuter depuis ce dossier :

```bash
./tools/tflite_cortex_a9/build.sh
```

Le script utilise `/opt/notebooks-venv/bin/python3` (Python 3.10 et NumPy 1.21.5).
Il clone le tag `v2.13.0` dans `.build/tflite_cortex_a9/tensorflow`, vérifie le tag,
l'origine et l'index, puis fait `git apply --check` avant d'appliquer le patch.
Un patch déjà appliqué est reconnu par `git apply --reverse --check`.
Ne pas utiliser ce checkout temporaire pour des modifications manuelles.
Le script ne réinitialise pas un checkout divergent et ne remplace pas une
installation TensorFlow système.

Le lancement officiel est :

```bash
CI_BUILD_PYTHON=/opt/notebooks-venv/bin/python3 \
TENSORFLOW_TARGET=armhf_vfpv3 \
tensorflow/lite/tools/pip_package/build_pip_package_with_cmake.sh
```

La première exécution manuelle télécharge TensorFlow, la toolchain et les
dépendances CMake. Deux tâches de compilation sont utilisées par défaut ;
`BUILD_NUM_JOBS=4 ./tools/tflite_cortex_a9/build.sh` permet d'ajuster ce nombre.
Une relance réutilise les sources et le patch, mais le script officiel recrée
son répertoire de compilation. Le wheel CPython 3.10 n'est copié dans
`artifacts/tflite_runtime/` qu'après validation ; un wheel du même nom y est remplacé.
`.build/` et ces wheels sont ignorés par Git. Aucun `git add` n'est exécuté.

Cette procédure fixe le tag et le patch ; elle ne garantit pas encore des
binaries identiques octet pour octet. L'image du devcontainer et certaines
versions d'outils/dépendances restent non verrouillées. La compatibilité des
headers Python, de la libc et des bibliothèques liées reste à vérifier sur la carte.

## Vérifier un artefact

Depuis `exo_0_detection/` :

```bash
./tools/tflite_cortex_a9/verify.sh artifacts/tflite_runtime/tflite_runtime-2.13.0-cp310-cp310-linux_armv7l.whl
# Ou avec le wrapper déjà extrait :
./tools/tflite_cortex_a9/verify.sh /chemin/_pywrap_tensorflow_interpreter_wrapper.so
```

Le script extrait uniquement le wrapper attendu dans un répertoire temporaire,
supprimé en sortie, puis exécute `file` et `readelf -A`. Il exige `Tag_CPU_arch: v7`
et `Tag_FP_arch: VFPv3`, et rejette VFPv4 ou les attributs manquants. Il affiche
les résultats ARMv7, VFPv3 et absence de VFPv4 avec un code de sortie non nul
si une condition échoue. Aucun module ARM n'est importé sur l'hôte x86_64.

Les attributs ELF sont un contrôle nécessaire, pas une preuve exhaustive de
compatibilité de chaque instruction ou dépendance dynamique. Le wheel n'est
**jamais installé automatiquement sur le PYNQ**. La validation finale reste
le chargement du modèle, `allocate_tensors()` puis `interpreter.invoke()` sur
la vraie carte, avec une image fixe et le kernel Python cible.

## Vérifications sans build

```bash
bash -n tools/tflite_cortex_a9/build.sh
bash -n tools/tflite_cortex_a9/verify.sh
git apply --numstat tools/tflite_cortex_a9/patches/tensorflow-2.13-armhf-vfpv3.patch
```

Le contrôle d'applicabilité sur le checkout réel est effectué par `build.sh`.
