# 009 El tap de Homebrew vive en este repositorio, con una versión «nightly»

**Decisión:** los casks están en `Casks/` en la raíz de MycSs, y el tap se añade con la dirección completa (`brew tap frenkiieeee/mycss https://github.com/frenkiieeee/MycSs`). No hay un repo `homebrew-mycss` aparte. Hay dos: `mycss` (versión numerada) y `mycss@nightly` (la rama `main`).

**Por qué:** un tap aparte obliga a copiar el cask a mano en cada versión (era el paso 6 de `RELEASING.md`) y a guardar un token para que una acción de un repo escriba en otro. Con el cask en el mismo repositorio, `brew update` lo recibe con cada cambio y la release lo actualiza con el `GITHUB_TOKEN` normal. Para «tener todo al día cada vez que se actualiza `main`», `nightly.yml` reconstruye un DMG por cada push (sin tocar docs ni casks) y reemplaza la pre-release `nightly`; el cask `mycss@nightly` tiene `version :latest` y se actualiza con `brew upgrade --cask --greedy-latest`.

**Cómo:** `release.yml` construye el DMG de la etiqueta, publica la release con las notas del changelog y, en otro trabajo, apunta `Casks/mycss.rb` a esa versión con la suma sha256 **del archivo publicado** (la del DMG construido en local no valdría: el DMG no se reconstruye idéntico). `scripts/release.sh` ya no toca el cask. Los dos casks quitan la cuarentena tras instalar, porque la app no está notarizada.

**Coste y riesgos:** el nombre del tap tiene que escribirse con la dirección (`brew tap` a secas buscaría `homebrew-mycss`). El workflow hace un commit del bot en `main` por cada release; si algún día `main` se protege, hará falta permitirlo. La versión `nightly` puede romperse y no se puede tener a la vez que la numerada (`conflicts_with`). Se usa `postflight_steps`, de Homebrew reciente.

**Revertir:** crear `frenkiieeee/homebrew-mycss`, mover `Casks/` allí y volver a copiar el cask en cada release.
