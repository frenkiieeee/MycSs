# Marca Frenkiieeee en MycSs

Fuente de verdad de los valores: [`Assets/Mascot/palette.json`](../../Assets/Mascot/palette.json). Lo que no está derivado de un archivo o de una decisión tuya está marcado **por confirmar**.

## Principio

> Minimalismo en cantidad, maximalismo en intención.

Cada elemento en pantalla tiene un motivo. Pocas cosas, muy cuidadas. (Tomado de la skill `creative-editorial-web-uiux-skill`.)

## Paleta

| Rol | Valor | Uso |
|---|---|---|
| Primario | `#FFD400` | Acento de marca |
| Fondo | `#0B0B0F` | Fondo base |
| Superficie | `#1A1A22` | Paneles y tarjetas |
| Mascota | `#F7F4E8` | Cuerpo de la mascota |
| Borde | `#3A3A46` | Líneas finas |
| Sombra de la mascota | `#E8E0CB` | Derivado |
| Amarillo oscuro | `#E3AE00` | Derivado |
| Plata | `#CBCBD8` | Derivado |

**Por confirmar:** reglas de uso del amarillo (cuánta superficie, solo acento o también fondos), contraste mínimo sobre las letras, y si en el lock screen manda el color de la portada o el de marca. Hoy manda la portada (`ArtworkPalette`), con un tema fijo de reserva.

## Tipografía

- **Logotipo**: Nunito ExtraBold (OFL), ya en trazos en [`Assets/Mascot/svg/`](../../Assets/Mascot/svg/mycss-wordmark-on-dark.svg).
- **Interfaz y letras**: SF Pro, la fuente del sistema, por defecto.
- **Por confirmar:** tipografía de la marca personal Frenkiieeee fuera de MycSs.

## Mascota

Identidad del proyecto. 10 expresiones y 5 estados, todas en 512×512 para poder intercambiarlas sin que el cuerpo se mueva. Cada SVG separa partes en grupos con id (`body`, `eye`, `mouth`, `extras`) para animarlas. Los PNG no llevan fondo: úsalos sobre `#1A1A22` o más claro, el contorno negro se pierde sobre negro puro.

Propuesta de uso por momento (**por confirmar**):

| Momento | Archivo |
|---|---|
| Letras cargando | `mycss-pensando` |
| Sonando música | `mycss-state-auriculares` |
| Canción sin letra | `mycss-curioso` |
| Pausa larga o pantalla apagándose | `mycss-durmiendo` |
| Permiso concedido, ajuste guardado | `mycss-feliz` |
| Error o permiso denegado | `mycss-sorprendido` |
| Icono de barra de menú | silueta monocroma (plantilla) |

## Tono

**Por confirmar.** Los textos actuales de la app están en español, tuteo implícito, directos. Pendiente decidir si la mascota "habla" y con qué voz.

## Qué evitar

De la skill editorial: decoración sin función, exceso de tarjetas, degradados al azar, iconos innecesarios, rectángulos redondeados en todo.
