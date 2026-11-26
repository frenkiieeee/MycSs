# 016 Superficies del notch: cristal, teñido y temporizador de regla

Estado: hecho

## Objetivo
Que el notch no sea solo una forma negra: poder elegir su **superficie** (sólida como hoy, de **cristal** que deja ver lo que hay detrás, o de cristal **teñido** con un color), la redondez de sus esquinas y un temporizador con **regla** como el de la isla dinámica del iPhone. Todo se puede guardar como estilo propio (plantilla) y hay dos estilos de fábrica nuevos: «Cristal» e «Isla».

## No objetivos
- Copiar el aspecto exacto de la isla de Apple ni usar sus recursos: es una interpretación propia.
- La API `glassEffect` de macOS 26: el SDK de las Command Line Tools con el que se compila no la ofrece, y la app debe seguir funcionando en macOS 15. El cristal se hace con desenfoque real de lo que hay detrás de la ventana (`NSVisualEffectView`), un velo, un brillo y un borde de luz.
- Exportar e importar plantillas en un archivo (queda como siguiente paso; hoy se guardan en los ajustes, como los demás estilos propios).

## Datos
Ajustes nuevos, todos dentro de `StyleDomain.notch`, así que un estilo propio los guarda sin más:

| Clave | Valores | Por defecto |
|---|---|---|
| `notchSurface` | `solid`, `glass`, `tinted` | `solid` |
| `notchGlass` | 0,15 a 0,95: cuánto deja ver (más = más transparente) | 0,55 |
| `notchCorner` | 0,7 a 1,5: multiplica la redondez de las esquinas de abajo | 1 |
| `notchTimerStyle` | `presets` (cuatro botones), `ruler` (regla que se arrastra) | `presets` |
| `notchAccent` | gana `amber`, `sky`, `rose` | sin cambio |

El notch **en reposo** (idle) es siempre negro, para fundirse con el recorte físico de la pantalla; el cristal aparece en cuanto el notch crece (alas, aviso, volumen, abierto) con un fundido.

Capas del cristal, de abajo arriba: negro (la base), desenfoque de lo que hay detrás, velo oscuro (más ligero cuanto más transparente), brillo diagonal, color del acento (solo «teñido») y un borde de luz que se desvanece hacia arriba.

En las vistas previas de los ajustes y en las capturas (sin ventana propia) el desenfoque se sustituye por un degradado, porque no hay nada detrás que desenfocar.

Estilos de fábrica nuevos (`NotchLook`): **Cristal** (cristal neutro, acento blanco, rebote) e **Isla** (cristal teñido ámbar, esquinas grandes, anillo de volumen, temporizador de regla). Los tres anteriores fijan ahora también la superficie (sólida), para que cambiar de uno a otro no deje restos.

## Interfaz
- Notch › Aspecto › Aspecto: «Superficie», «Transparencia» (si no es sólida), «Esquinas», «Temporizador» y los acentos nuevos.
- Notch › Estilos: «Cristal» e «Isla» junto a los demás, y «Guardar los ajustes actuales» para la plantilla propia.
- Temporizador de regla: se arrastra la regla a izquierda y derecha (un minuto por marca, marca grande cada cinco), la cuenta se ve grande a la derecha y «Iniciar» la arranca. Hace un toque háptico por minuto.

## Permisos y riesgos
- Ninguno nuevo. El desenfoque de detrás de la ventana no pide permiso de grabación de pantalla.
- Sobre fondos muy claros el cristal se ve más gris: el velo oscuro mantiene legible el texto blanco, pero «Transparencia» alta lo aclara.
- El notch nunca toca `ignoresMouseEvents` (ADR 005): el cristal es solo fondo.

## Verificación
- `./scripts/verify.sh` (`--selftest-pure`: ajustes nuevos, estilos de fábrica y la regla) y `./scripts/verify.sh --notch`.
- `MycSs --demo --notch-look=island|glass --notch-snapshot /tmp/n` dibuja el notch con ese estilo (sin desenfoque: no hay nada detrás).
- A ojo con la app abierta: cada superficie sobre un fondo claro y otro oscuro, el temporizador de regla, guardar un estilo propio y recuperarlo. El desenfoque real solo se ve en pantalla (`screencapture` lo recoge), no en `--snapshot` ni en las capturas del notch. Comprobado así con «Isla»: se ve el desenfoque de la página de detrás y el tinte ámbar.

## Preguntas abiertas
- ¿Exportar e importar plantillas (JSON) para compartirlas?
- ¿El color del cristal teñido debería poder elegirse libremente y no solo entre los acentos?
