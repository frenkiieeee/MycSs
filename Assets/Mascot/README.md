# MycSs · mascota

Set completo de la mascota en SVG (vectorial, paths a mano) y PNG transparente.
Se regenera todo con `python3 generate.py` (necesita `fonttools` y `rsvg-convert`).

| Carpeta / archivo | Qué hay |
|---|---|
| `svg/mycss-<expresion>.svg` | 10 expresiones: neutro, feliz, sorprendido, pensando, guino, emocionado, enfocado, relajado, durmiendo, curioso. Mismo encuadre (512×512): se pueden intercambiar sin que el cuerpo se mueva |
| `svg/mycss-state-<estado>.svg` | 5 estados: asomando, portatil, auriculares, cafe, manta |
| `svg/mycss-wordmark-on-{dark,light}.svg` | Logotipo `MycSs` en trazos (Nunito ExtraBold, OFL) |
| `svg/mycss-logotype-on-{dark,light}.svg` | Mascota + logotipo en horizontal |
| `svg/mycss-icon-{cream,yellow,dark}.svg` | Iconos de app (tile redondeado) |
| `png/<nombre>-<px>.png` | Exportaciones: 1024/512/256/128 (iconos también 64/32; logos 1600/800/400) |
| `preview/overview.png` | Vista general del set |
| `palette.json` | Paleta Frenkiieeee + 3 colores derivados |

Cada SVG separa sus partes en grupos con id (`body`, `eye`, `mouth`, `extras`...) para animarlas.
Los PNG de expresiones y estados no llevan fondo: el contorno negro (#0B0B0F) se pierde sobre negro puro,
úsalos sobre #1A1A22 o más claro.
