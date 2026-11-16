# 004 Modo salvapantallas propio

**Decisión:** el "salvapantallas" es un modo de presentación dentro de la app, no un `.saver` del sistema.

**Por qué:** un `.saver` es un bundle aparte con ScreenSaver.framework y sus propias restricciones. Un modo propio reutiliza `OverlayRootView`, se activa por atajo, menú o inactividad, y se cierra con tecla o ratón.

**Consecuencia:** no aparece en Ajustes del Sistema > Salvapantallas. Si hiciera falta, un `.saver` fino que lance MycSs se puede añadir después.
