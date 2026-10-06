import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:usb_serial/usb_serial.dart';
import 'package:usb_serial/transaction.dart';

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
  static final Uint8List readCommand = Uint8List.fromList([
    0xc9, 0x14, 0x02, 0x53, 0x48, 0x4f, 0x57, 0x00, 0x00, 0x00, 0x00, 0x00,
    0xaa, 0x00, 0x00, 0x00, 0x1e, 0xaa, 0x04, 0x67, 0x00, 0xf3, 0x52, 0x0d
  ]);

  List<UsbDevice> _devices = [];
  UsbPort? _port;
  Transaction<Uint8List>? _transaction;
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
    final devices = await UsbSerial.listDevices();
    setState(() => _devices = devices);
  }

  Future<void> _connect(UsbDevice device) async {
    setState(() => _status = 'Conectando…');
    final port = await device.create();
    if (port == null || !(await port.open())) {
      setState(() => _status = 'No se pudo abrir el puerto. ¿Permiso USB concedido?');
      return;
    }
    await port.setDTR(true);
    await port.setRTS(true);
    await port.setPortParameters(
      9600,
      UsbPort.DATABITS_8,
      UsbPort.STOPBITS_1,
      UsbPort.PARITY_NONE,
    );

    _port = port;
    _transaction = Transaction.createStreamTransaction(port.inputStream!, Uint8List.fromList);
    _subscription = _transaction!.stream.listen(_handleIncoming);

    setState(() {
      _connected = true;
      _status = 'Conectado. Toca "Leer datos" para pedir una lectura.';
    });
  }

  void _handleIncoming(Uint8List data) {
    // El controlador puede mandar los 24 bytes partidos en varios paquetes;
    // los vamos juntando hasta tener el frame completo que empieza con c0 14.
    _buffer.addAll(data);
    final start = _findFrameStart(_buffer);
    if (start == -1) {
      if (_buffer.length > 200) _buffer.clear();
      return;
    }
    if (_buffer.length - start < 24) return;

    final frame = Uint8List.fromList(_buffer.sublist(start, start + 24));
    _buffer.removeRange(0, start + 24);

    final reading = VotolReading.fromFrame(frame);
    final checksumOk = _checkChecksum(frame);
    setState(() {
      _lastReading = reading;
      _lastChecksumOk = checksumOk;
      _status = checksumOk
          ? 'Última lectura OK.'
          : 'Lectura recibida, pero el checksum no coincide — tómala con cuidado.';
    });
  }

  final List<int> _buffer = [];

  int _findFrameStart(List<int> buf) {
    for (var i = 0; i
