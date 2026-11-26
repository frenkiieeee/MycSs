# 007 El navegador, con AppleScript y JavaScript

**Decisión:** leer lo que suena en el navegador ejecutando un script pequeño en la pestaña por AppleScript (`execute javascript` en Chromium, `do JavaScript` en Safari).

**Por qué:** MediaRemote sigue descartado ([ADR 001](001-applescript-no-mediaremote.md)). Es la única vía pública que da título, estado, posición e icono de una pestaña y deja pausar o saltar.

**Coste:** el usuario tiene que activar «Permitir JavaScript desde eventos de Apple» en cada navegador y conceder la Automatización. Firefox y Zen quedan fuera de esta vía: se leen con la [008](008-now-playing-con-perl.md). Leer todas las pestañas cuesta, así que el barrido es lento (cada 4 s) y luego solo se lee la pestaña que suena.

**Revertir:** quitar `BrowserSource` y la opción; el resto de la app no depende de ello.
