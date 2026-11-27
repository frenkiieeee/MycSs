# 017 MycSs en Macs y pantallas sin notch

Estado: hecho

## Objetivo
Que quien tiene una Mac sin notch (un MacBook sin recorte, o un monitor externo) use MycSs entero y a gusto. Hoy en esas pantallas se dibuja una píldora negra fija de 170×28 pegada al borde, más alta que la barra de menús, y siempre visible aunque no haya nada que enseñar. Debe ser una pieza pensada para ellas: **arriba del todo, dentro de la barra** y con su alto, **invisible en reposo** si se quiere (o, a elección, una **isla flotante** bajo la barra), con el mismo contenido (música, avisos, volumen, widgets, bandeja).

## No objetivos
- Cambiar nada en las pantallas **con** notch: allí el notch sigue siendo el recorte físico, como hasta ahora.
- Detectar un modelo concreto: se mira la pantalla (`safeAreaInsets`), no el nombre del Mac. Vale para cualquier Mac o monitor sin recorte.

## Datos
- **Detección**: una pantalla tiene notch físico si `safeAreaInsets.top > 0` y hay `auxiliaryTopLeftArea`/`auxiliaryTopRightArea`. Si no, es una pantalla **sin notch**. La Mac con notch usa el recorte; las demás (otra pantalla, o la única) usan la forma de abajo.
- **Alto de la barra de menús**: `NSScreen.frame.maxY - visibleFrame.maxY`, o 24 si la barra está oculta. La píldora de antes ya no se pasa de ese alto.
- **Ajustes nuevos** (dentro de `StyleDomain.notch`, así que un estilo propio los guarda):

| Clave | Valores | Por defecto |
|---|---|---|
| `notchPlainStyle` | `attached` (colgada del borde de arriba, dentro de la barra, como un notch), `island` (isla flotante bajo la barra, todas las esquinas redondas) | `attached` |
| `notchPlainRest` | `hidden` (no se ve nada en reposo), `visible` (píldora negra siempre) | `hidden` |
| `notchPlainWidth` | 70 a 220 pt: ancho de la zona de reposo | 110 |

- **Reposo invisible**: sin música ni nada que enseñar, no se dibuja nada. La música aparece como una isla con la portada y el visualizador a los lados, que crece desde el centro. Para abrir el notch se lleva el puntero al centro del borde de arriba de la pantalla (una franja del ancho elegido y el alto de la barra); en modo «Con un clic» (ya existente), se pulsa esa franja o, mejor, se usa el elemento nuevo del menú «Abrir el notch».
- **Isla flotante** (opcional): el notch queda `barra + 6 pt` por debajo del borde de arriba, con esquinas redondas por todos lados y una sombra suave; no tapa la barra de menús. El hueco entre las alas (donde en un notch está la cámara) pasa de 170 pt a 22 pt, porque no hay nada que esquivar.
- **Colgada** (por defecto): como el notch de siempre, pegada al borde de arriba y con las orejas curvas, con el alto de la barra: en reposo queda dentro de la barra, y solo crece hacia abajo cuando hay música con título, un aviso o está abierta. Se probó primero la isla como forma por defecto y en una segunda pantalla real se veía «fuera de la barra»: se cambió.
- **Abierto**: la tira de arriba (pestañas y engranaje) mide siempre 32 pt (`openHeader`), con o sin notch, para que el panel sea idéntico aunque la barra de menús mida 24.
- El cristal, los acentos, el temporizador de regla y los demás ajustes de [016](016-notch-surfaces.md) valen igual.
- **Vista previa**: la tarjeta del notch en los ajustes deja elegir «Con notch» o «Sin notch» (por defecto, lo que tenga la pantalla), para ver y ajustar esta forma aunque la Mac tenga recorte.
- `--no-notch` fuerza la forma sin notch en la pantalla principal (capturas, pruebas y probar sin otra pantalla).

## Interfaz
- Notch › Aspecto › «Pantallas sin notch»: «Forma» (arriba del todo o isla flotante), «En reposo», «Ancho de la zona», con una frase que dice cómo abrirlo.
- Menú de la barra: «Abrir el notch».
- README: ya no promete «una píldora fija».

## Permisos y riesgos
- Ninguno nuevo. El panel sigue sin tocar `ignoresMouseEvents` (ADR 005).
- Con reposo invisible no hay nada que señalar: por eso la frase en los ajustes y el menú. Quien prefiera verlo siempre elige «En reposo › Siempre visible».
- La isla flotante usa la altura de la barra en el momento de crearse: si cambia (barra oculta o mostrada), se rehace al cambiar la configuración de pantallas.
- No he podido probar un Mac sin notch real: se prueba con `--no-notch` y con un monitor externo.

## Verificación
- `./scripts/verify.sh` (`--selftest-pure`: geometría, reposo, zona de reposo) y `./scripts/verify.sh --notch`, que ahora repite la prueba del notch real con `--no-notch`.
- `MycSs --demo --no-notch --notch-snapshot /tmp/p` (comprobado: isla con música, aviso y título largos, abierta, y reposo sin dibujar nada) y a ojo con un monitor externo.

## Preguntas abiertas
- ¿Un atajo global para abrir el notch, además del menú?
- ¿Mostrar siempre un indicador mínimo (un punto) cuando hay música y el reposo es invisible?
