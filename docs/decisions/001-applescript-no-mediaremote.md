# 001 AppleScript y no MediaRemote

**Decisión:** leer Spotify y Apple Music con AppleScript.

**Por qué:** desde macOS 15.4 `mediaremoted` exige un entitlement que las apps de terceros no tienen, y la API privada MediaRemote dejó de funcionar para ellas. AppleScript habla con la app que el usuario ya tiene abierta y solo pide el permiso de Automatización.

**Alternativa de reserva:** `mediaremote-adapter`, que ejecuta un script con `/usr/bin/perl`, binario del sistema que sí tiene el entitlement. Depende de que Apple no se lo quite. Es lo que usa boring.notch.

**Consecuencia:** se lee una app concreta a la vez, no "lo que suene en el sistema".
