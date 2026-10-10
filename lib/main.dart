import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:usb_serial/usb_serial.dart';

void main() {
  runApp(const VotolApp());
}

class VotolApp extends StatelessWidget {
  const VotolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VotolConfig',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF34C759),
        scaffoldBackgroundColor: const Color(0xFF0E0E10),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF34C759),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const VotolHomePage(),
    );
  }
}

class VotolHomePage extends StatefulWidget {
  const VotolHomePage({super.key});

  @override
  State<VotolHomePage> createState() => _VotolHomePageState();
}

class _VotolHomePageState extends State<VotolHomePage> {
  // Comando exacto de lectura, documentado por la comunidad (foro endless-sphere,
  // hilo "VOTOL serial communication protocol"). No se debe modificar a mano.
  // Paquete SHOW de lectura de telemetría de 24 bytes documentado en
  // la referencia comunitaria bananu7/votol (reference/raw_notes.md).
  // Se usa la variante de lectura con longitud 0x18 y checksum 0xC4.
  static final Uint8List readCommand = Uint8List.fromList([
    0xc9, 0x14, 0x02, 0x53, 0x48, 0x4f, 0x57, 0x00, 0x00, 0x00, 0x00, 0x00,
    0xaa, 0x00, 0x00, 0x00, 0x18, 0xaa, 0x00, 0x00, 0x00, 0x00, 0xc4, 0x0d
  ]);

  List<UsbDevice> _devices = [];
  UsbPort? _port;
  StreamSubscription<Uint8List>? _subscription;
  bool _connected = false;
  bool _polling = false;
  Timer? _pollTimer;
  String _status = 'Sin conectar. Enchufa el cable del Votol al teléfono.';
  VotolReading? _lastReading;
  bool _lastChecksumOk = true;

  @override
  void initState() {
    super.initState();
    _refreshDevices();
  }

  Future<void> _refreshDevices() async {
    try {
      final devices = await UsbSerial.listDevices();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _status = devices.isEmpty
            ? 'No se detecta ningún USB. Comprueba el adaptador OTG y vuelve a buscar.'
            : 'Se detectaron ${devices.length} dispositivo(s) USB.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Error buscando USB: $e');
    }
  }

  Future<void> _connect(UsbDevice device) async {
    if (!mounted) return;
    setState(() => _status = 'Solicitando permiso y conectando al USB…');
    UsbPort? port;
    try {
      port = await device.create();
      if (port == null) {
        throw Exception('El dispositivo no creó un puerto USB.');
      }
      final opened = await port.open();
      if (!opened) {
        throw Exception('No se pudo abrir el puerto USB. Comprueba el permiso OTG.');
      }
      await port.setPortParameters(
        9600,
        UsbPort.DATABITS_8,
        UsbPort.STOPBITS_1,
        UsbPort.PARITY_NONE,
      );
      await port.setDTR(true);
      await port.setRTS(true);

      final input = port.inputStream;
      if (input == null) {
        throw Exception('El puerto abrió, pero no ofrece un flujo de lectura.');
      }

      _port = port;
      _buffer.clear();
      _subscription = input.listen(
        _handleIncoming,
        onError: (Object error) {
          if (mounted) setState(() => _status = 'Error leyendo USB: $error');
        },
        onDone: () {
          if (mounted && _connected) {
            setState(() => _status = 'El flujo USB se cerró. Desconecta y vuelve a conectar.');
          }
        },
      );

      if (!mounted) return;
      setState(() {
        _connected = true;
        _status = 'Conectado a ${device.productName ?? "dispositivo USB"}. Toca “Leer datos”.';
      });
    } catch (e) {
      try { await port?.close(); } catch (_) {}
      if (!mounted) return;
      setState(() {
        _connected = false;
        _port = null;
        _status = 'No se pudo conectar: $e';
      });
    }
  }

  void _handleIncoming(Uint8List data) {
    // Las respuestas pueden llegar fragmentadas o varias juntas. El frame de
    // telemetría tiene 24 bytes: C0 14 ... XOR ... 0D.
    if (!mounted) return;
    _buffer.addAll(data);

    while (_buffer.length >= 24) {
      final start = _findFrameStart(_buffer);
      if (start == -1) {
        // Conserva un posible primer byte de cabecera partido entre paquetes.
        final keepLastByte = _buffer.isNotEmpty && _buffer.last == 0xc0;
        final last = keepLastByte ? _buffer.last : null;
        _buffer.clear();
        if (last != null) _buffer.add(last);
        return;
      }
      if (start > 0) _buffer.removeRange(0, start);
      if (_buffer.length < 24) return;

      final frame = Uint8List.fromList(_buffer.sublist(0, 24));
      if (frame[23] != 0x0d) {
        // Cabecera falsa o datos corruptos: desplaza un byte y vuelve a buscar.
        _buffer.removeAt(0);
        continue;
      }

      _buffer.removeRange(0, 24);
      final checksumOk = _checkChecksum(frame);
      if (!checksumOk) {
        setState(() {
          // Do not leave a previous valid reading on screen as if it were current.
          _lastReading = null;
          _lastChecksumOk = false;
          _status = 'Respuesta recibida, pero el checksum no coincide. No se muestran valores dudosos.';
        });
        continue;
      }

      final reading = VotolReading.fromFrame(frame);
      setState(() {
        _lastReading = reading;
        _lastChecksumOk = true;
        _status = 'Última lectura válida recibida.';
      });
    }
  }

  final List<int> _buffer = [];

  int _findFrameStart(List<int> buf) {
    for (var i = 0; i < buf.length - 1; i++) {
      if (buf[i] == 0xc0 && buf[i + 1] == 0x14) return i;
    }
    return -1;
  }

  bool _checkChecksum(Uint8List frame) {
    if (frame.length != 24 || frame[0] != 0xc0 || frame[1] != 0x14 || frame[23] != 0x0d) {
      return false;
    }
    int xorSum = 0;
    for (var i = 0; i < 22; i++) {
      xorSum ^= frame[i];
    }
    return xorSum == frame[22];
  }

  Future<void> _readOnce() async {
    final port = _port;
    if (port == null || !_connected) return;
    try {
      port.write(readCommand);
      if (mounted) setState(() => _status = 'Solicitud enviada; esperando respuesta del controlador…');
    } catch (e) {
      if (mounted) setState(() => _status = 'No se pudo enviar la solicitud USB: $e');
    }
  }

  void _togglePolling() {
    if (_polling) {
      _pollTimer?.cancel();
      _pollTimer = null;
      setState(() => _polling = false);
    } else {
      // Envía una petición inmediatamente y luego consulta cada segundo.
      _readOnce();
      _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _readOnce());
      setState(() => _polling = true);
    }
  }

  Future<void> _disconnect() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    try { await _subscription?.cancel(); } catch (_) {}
    try { await _port?.close(); } catch (_) {}
    _subscription = null;
    _buffer.clear();
    if (!mounted) return;
    setState(() {
      _connected = false;
      _polling = false;
      _port = null;
      _lastReading = null;
      _status = 'Desconectado.';
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _subscription?.cancel();
    _port?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VotolConfig — Fase 1'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshDevices,
            tooltip: 'Buscar cable',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            if (!_connected) ...[
              const Text('Dispositivos USB detectados:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (_devices.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('Ninguno. Conecta el cable del Votol y toca el ícono de recargar arriba.'),
                ),
              ..._devices.map((d) => Card(
                    child: ListTile(
                      title: Text(d.productName ?? 'Dispositivo USB'),
                      subtitle: Text('VID: ${d.vid}  PID: ${d.pid}'),
                      trailing: ElevatedButton(
                        onPressed: () => _connect(d),
                        child: const Text('Conectar'),
                      ),
                    ),
                  )),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _readOnce,
                      icon: const Icon(Icons.download),
                      label: const Text('Leer datos'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _togglePolling,
                      icon: Icon(_polling ? Icons.pause : Icons.play_arrow),
                      label: Text(_polling ? 'Detener auto' : 'Auto cada 1s'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: _disconnect, child: const Text('Desconectar')),
              const Divider(height: 32),
              if (_lastReading != null) _ReadingView(reading: _lastReading!, checksumOk: _lastChecksumOk),
            ],
          ],
        ),
      ),
    );
  }
}

/// Representa una lectura decodificada del frame de 24 bytes, según el
/// protocolo documentado por la comunidad (no todos los bytes están
/// descifrados todavía — ver notas en el README del proyecto).
class VotolReading {
  final double batteryVoltage;
  final double batteryCurrent;
  final int rpm;
  final int controllerTempC;
  final int externalTempC;
  final int tempCoefficient;
  final int faultCode;
  final int gearRaw;
  final String gearLabel;
  final bool reverse;
  final bool park;
  final bool brake;
  final bool antitheft;
  final bool sideStand;
  final bool regen;
  final int statusRaw;
  final String statusLabel;
  final List<int> rawBytes;

  VotolReading({
    required this.batteryVoltage,
    required this.batteryCurrent,
    required this.rpm,
    required this.controllerTempC,
    required this.externalTempC,
    required this.tempCoefficient,
    required this.faultCode,
    required this.gearRaw,
    required this.gearLabel,
    required this.reverse,
    required this.park,
    required this.brake,
    required this.antitheft,
    required this.sideStand,
    required this.regen,
    required this.statusRaw,
    required this.statusLabel,
    required this.rawBytes,
  });

  factory VotolReading.fromFrame(Uint8List f) {
    int u16(int hi, int lo) => (f[hi] << 8) | f[lo];
    final voltage = u16(5, 6) / 10.0;
    final current = u16(7, 8) / 10.0;
    final rpm = u16(14, 15);
    final controllerTemp = f[16] - 50;
    final externalTemp = f[17] - 50;
    final tempCoef = u16(18, 19);
    final fault = (f[10] << 24) | (f[11] << 16) | (f[12] << 8) | f[13];
    final b20 = f[20];
    final gearRaw = b20 & 0x03;
    const gearLabels = ['L', 'M', 'H', 'S'];
    final status = f[21];
    const statusLabels = ['IDLE', 'INIT', 'START', 'RUN', 'STOP', 'BRAKE', 'WAIT', 'FAULT'];

    return VotolReading(
      batteryVoltage: voltage,
      batteryCurrent: current,
      rpm: rpm,
      controllerTempC: controllerTemp,
      externalTempC: externalTemp,
      tempCoefficient: tempCoef,
      faultCode: fault,
      gearRaw: gearRaw,
      gearLabel: gearLabels[gearRaw],
      reverse: (b20 & 0x04) != 0,
      park: (b20 & 0x08) != 0,
      brake: (b20 & 0x10) != 0,
      antitheft: (b20 & 0x20) != 0,
      sideStand: (b20 & 0x40) != 0,
      regen: (b20 & 0x80) != 0,
      statusRaw: status,
      statusLabel: status < statusLabels.length ? statusLabels[status] : 'DESCONOCIDO ($status)',
      rawBytes: f,
    );
  }
}

class _ReadingView extends StatelessWidget {
  final VotolReading reading;
  final bool checksumOk;
  const _ReadingView({required this.reading, required this.checksumOk});

  @override
  Widget build(BuildContext context) {
    final rows = <MapEntry<String, String>>[
      MapEntry('Voltaje batería', '${reading.batteryVoltage.toStringAsFixed(1)} V'),
      MapEntry('Corriente batería', '${reading.batteryCurrent.toStringAsFixed(1)} A'),
      MapEntry('RPM', '${reading.rpm}'),
      MapEntry('Temp. controlador', '${reading.controllerTempC} °C'),
      MapEntry('Temp. externa', '${reading.externalTempC} °C'),
      MapEntry('Coeficiente temp.', '${reading.tempCoefficient}'),
      MapEntry('Código de falla', '0x${reading.faultCode.toRadixString(16).padLeft(8, '0')}'),
      MapEntry('Marcha', reading.gearLabel),
      MapEntry('Reversa', reading.reverse ? 'Sí' : 'No'),
      MapEntry('Parking', reading.park ? 'Sí' : 'No'),
      MapEntry('Freno', reading.brake ? 'Sí' : 'No'),
      MapEntry('Antirrobo', reading.antitheft ? 'Sí' : 'No'),
      MapEntry('Caballete lateral', reading.sideStand ? 'Sí' : 'No'),
      MapEntry('Regenerativa', reading.regen ? 'Sí' : 'No'),
      MapEntry('Estado', reading.statusLabel),
    ];

    return Expanded(
      child: ListView(
        children: [
          if (!checksumOk)
            Container(
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(bottom: 8),
              color: Colors.red.withValues(alpha: 0.2),
              child: const Text(
                '⚠ El checksum de este paquete no coincide. Puede ser ruido en la línea — vuelve a leer.',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ...rows.map((r) => Card(
                child: ListTile(
                  title: Text(r.key),
                  trailing: Text(r.value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              )),
          const SizedBox(height: 16),
          Text(
            'Bytes crudos: ${reading.rawBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}',
            style: const TextStyle(fontSize: 11, color: Colors.grey, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}
