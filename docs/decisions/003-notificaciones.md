# 003 Notificaciones en el notch

**Decisión:** leer las notificaciones de la base de datos de `usernoted` con Acceso total al disco, con un spike de validación y un plan B.

**Por qué:** no hay API pública para recibir notificaciones de otras apps. Y no se puede ocultar el banner nativo: el sistema lo dibuja por su cuenta. Con volumen y brillo sí funciona porque son teclas que una app puede interceptar y consumir.

**Cómo queda:** el usuario pone los banners de las apps elegidas en "Ninguno" (o usa un Focus propio) y MycSs muestra las suyas en el notch. **Falta verificar** que la base de datos recibe la notificación en esos casos.

**Riesgos:** Apple anunció el 2 oct 2026 controles más estrictos para Acceso total al disco, sin fecha. Plan B: solo eventos propios de MycSs.
