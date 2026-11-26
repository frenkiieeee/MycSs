# 015 Pulido del notch, historial de avisos, portapapeles con imágenes y tap de Homebrew

Estado: hecho

## Objetivo
Cinco arreglos y mejoras que salieron del uso diario: el estilo «Minimal» no deja la portada pegada arriba, el temporizador se ve bien con cualquier tamaño del notch, los avisos que se abren siguen en «Avisos» (también tras reiniciar), el portapapeles se puede limpiar y guarda imágenes, y MycSs se instala y se mantiene al día con Homebrew sin repos aparte.

## No objetivos
- Sincronizar el historial entre Macs ni guardar los avisos del sistema que no pasaron por el notch.
- Guardar el portapapeles en disco: sigue solo en memoria.
- Notarizar la app (ver [006](../decisions/006-versionado-y-distribucion.md)).

## Datos
- **Portada de «Minimal»**: sin reloj, la columna de la portada se centra en vertical con la letra (`OverlayRootView`). Con reloj no cambia nada.
- **Temporizador**: `NotchKind.timer`. Mientras corre (o está en pausa) el notch cerrado baja una fila bajo el recorte (`NotchGeometry.timerRow`) con el icono y el tiempo, igual que un aviso. Los lados siguen con la portada y el visualizador si suena música. La fila ya no depende del ancho de los lados.
- **Historial de avisos**: `NotificationHistoryStore` guarda en `~/Library/Application Support/MycSs/notification-history.json` (permisos 0600) los últimos 50 avisos que llegaron al notch. Se carga al arrancar el lector y se escribe 0,6 s después del último cambio. Abrir un aviso (clic en el notch o en el widget) lo da por atendido y **lo quita de la lista**; el widget cuenta los que quedan. Ajuste `notchNotificationKeepHistory` (por defecto activo): apagarlo borra el archivo. Nunca se guarda con una base de prueba.
- **Caché de apps**: nombre e icono de cada app se piden una vez (`NotchNotification.appName/icon`), no en cada redibujado.
- **Portapapeles**: `ClipboardModel.Entry` es texto o imagen (PNG hasta 12 MB, con miniatura de 48 px). Una imagen se toma si el portapapeles no trae texto o solo la dirección que añaden los navegadores; también una imagen copiada en el Finder. Seis entradas como máximo, sin duplicados, solo en memoria. El botón de la cabecera lo vacía.
- **Distribución**: carpeta `Casks/` en la raíz de este repositorio, que es el tap (`brew tap frenkiieeee/mycss https://github.com/frenkiieeee/MycSs`). `mycss` apunta a la última versión numerada; `mycss@nightly` al DMG de la rama `main`. Decisión en [009](../decisions/009-tap-en-el-repositorio.md).
- **Changelog**: `scripts/changelog.py` (`check`, `release`, `notes`, `latest`). `release.sh` convierte `[Unreleased]` en la versión nueva y la release de GitHub usa sus notas.

## Interfaz
- Notch › Avisos: «Recordar el historial al reiniciar».
- Widget «Avisos»: insignia amarilla con cuántos hay.
- Widget «Copiado» (el portapapeles; el título corto cabe junto a las pestañas): título con botón de vaciar; las imágenes salen con miniatura y «Imagen · ancho × alto», y al apuntar una se ve grande sobre la lista (`hoveredImage`; deja pasar el puntero, así el clic sigue copiando). Se guarda una copia de 320 px para eso.

## Permisos y riesgos
- El historial guarda el texto de avisos privados en un archivo del usuario: por eso es un ajuste, tiene permisos 0600 y se borra al apagarlo. Con «Mostrar el contenido» apagado el notch no lo enseña, pero el archivo lo conserva.
- Una imagen copiada puede ser grande: tope de 12 MB por imagen y seis entradas.
- Homebrew reciente pide «confiar» en un tap de terceros (`brew trust frenkiieeee/mycss`). El cask pasa `brew style` y `brew audit`.
- La app no está notarizada: el cask quita la cuarentena tras instalar.

## Verificación
- `./scripts/verify.sh` y `MycSs --selftest-pure` (sección «Spec 015»: historial, portapapeles, disposición del temporizador).
- `./scripts/verify.sh --notch`.
- A ojo: estilo «Minimal» con la pantalla de bloqueo, un temporizador con el notch a tamaños distintos, un aviso abierto y reiniciar la app, copiar una captura con ⌃⇧⌘4 y ver el widget.
- `brew style Casks/` y, con el tap clonado, `brew audit --cask frenkiieeee/mycss/mycss@nightly`.

## Preguntas abiertas
- Ninguna.
