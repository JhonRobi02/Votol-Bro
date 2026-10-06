# VotolConfig — Fase 1

App Android (Flutter) para leer datos en vivo de un controlador Votol por el cable USB (chip PL2303), sin necesidad de computadora.

## Qué hace esta primera versión

- Detecta el cable cuando lo conectas al teléfono (con un adaptador USB-C a USB-A, modo OTG).
- Manda el comando de lectura documentado por la comunidad.
- Decodifica y muestra: voltaje de batería, corriente, RPM, temperatura del controlador, temperatura externa, código de falla, marcha, estado (reversa/parking/freno/antirrobo/caballete/regenerativa), y el estado general del controlador (RUN, FAULT, etc.).
- Botón para leer una sola vez, o activar lectura automática cada 1 segundo.
- Verifica el checksum de cada paquete recibido y avisa si algo no cuadra (para no confiar en datos corruptos).

**Lo que todavía NO hace** (queda para la Fase 2): cambiar parámetros (escritura), ya que aún falta terminar de descifrar en qué posición exacta va cada parámetro dentro del paquete de escritura.

## Fuente del protocolo

Foro endless-sphere.com, hilo "VOTOL serial communication protocol":
https://endless-sphere.com/sphere/threads/votol-serial-communication-protocol.112970/

No todos los bytes están descifrados (por ejemplo el byte 9 del paquete de lectura sigue siendo desconocido por la comunidad) — si algo se ve raro en una lectura, puede ser por eso.

## Para probarla

1. Instala el `.apk` en tu teléfono (puede pedirte permitir "instalar de fuentes desconocidas" la primera vez).
2. Conecta el cable Votol al controlador, y el otro extremo a tu teléfono con el adaptador USB-C.
3. Abre la app — debería aparecer el dispositivo en la lista. Tócalo para conectar.
4. Dale "Leer datos".

Si Android te pide permiso para acceder al dispositivo USB la primera vez, acéptalo.
