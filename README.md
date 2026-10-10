# VotolConfig — Fase 1

Aplicación Flutter para Android que intenta leer telemetría en vivo de un controlador Votol por USB OTG y un adaptador USB-serial compatible (por ejemplo, PL2303).

## Funciones actuales

- Detecta dispositivos USB seriales y permite elegir uno.
- Abre el puerto a 9600 baudios, 8 bits, sin paridad, 1 bit de parada.
- Envía una solicitud de telemetría `SHOW`.
- Acumula respuestas fragmentadas, busca la cabecera `C0 14`, comprueba el XOR y muestra voltaje, corriente, RPM, temperaturas, fallas y estados disponibles.
- Permite lectura manual o consultas periódicas cada segundo.
- Muestra errores de conexión y lectura en pantalla.

## Importante

Este proyecto está en fase experimental. Los campos se basan en documentación comunitaria del protocolo Votol y pueden variar según el modelo/firmware del controlador. Una lectura que pase el checksum no garantiza que todos los campos estén interpretados correctamente. No se envían comandos de configuración ni de control del motor.

Antes de conectar:
1. Deja la rueda motriz levantada o la moto apagada de forma segura.
2. Usa un adaptador OTG y un cable USB-serial compatible con el nivel eléctrico del controlador.
3. No conectes/desconectes el cable durante la marcha.
4. Si los valores son absurdos o el checksum falla, no los uses para tomar decisiones mecánicas.

## Crear el proyecto Android

Este repositorio originalmente solo contiene el código Dart y un directorio Android parcial; no incluía todos los archivos de plataforma generados por Flutter. El workflow de GitHub Actions intenta generar los archivos Android que faltan, compilar un APK de depuración y publicarlo como artefacto.

También puedes completar la plataforma en un entorno con Flutter instalado, desde la raíz del repositorio:

```bash
flutter create --platforms=android --project-name votol_config --org com.jhonrobi.votol .
flutter pub get
flutter analyze
flutter build apk --debug
```

El APK de depuración, si la compilación termina correctamente, queda en `build/app/outputs/flutter-apk/app-debug.apk`.

## Referencia de protocolo

La solicitud `SHOW` y la estructura básica del frame se contrastaron con las notas comunitarias de [bananu7/votol](https://github.com/bananu7/votol/blob/1d41c8f2ed8866eb417486a1662abbf0efef2969/reference/raw_notes.md) y el hilo [VOTOL serial communication protocol](https://endless-sphere.com/sphere/threads/votol-serial-communication-protocol.112970/).

## Estado de validación

El código se revisó y corrigió en el repositorio, pero todavía hace falta probarlo físicamente con el controlador, el cable y el teléfono concretos. La compilación automatizada debe terminar antes de considerar listo el APK.
