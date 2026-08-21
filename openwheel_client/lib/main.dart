import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const OpenWheelApp());
}

class OpenWheelApp extends StatelessWidget {
  const OpenWheelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const RacingScreen(),
    );
  }
}

class RacingScreen extends StatefulWidget {
  const RacingScreen({super.key});

  @override
  State<RacingScreen> createState() => _RacingScreenState();
}

class _RacingScreenState extends State<RacingScreen> {
  // --- Control States ---
  bool isGyroMode = false; 
  double steeringValue = 0.0; // -1.0 (Left) to 1.0 (Right)
  double throttleValue = 0.0; // 0.0 to 1.0
  double brakeValue = 0.0;    // 0.0 to 1.0
  double touchWheelAngle = 0.0; // Visually rotates the on-screen wheel

  // --- Networking States ---
  RawDatagramSocket? _socket;
  final String _serverIp = "192.168.1.10"; // We will change this to auto-discovery later!
  final int _port = 5005;
  bool isConnected = false;
  
  // --- Timers & Sensors ---
  Timer? _transmitTimer;
  Timer? _heartbeatTimer;
  StreamSubscription<AccelerometerEvent>? _accelSubscription;

  @override
  void initState() {
    super.initState();
    _initNetwork();
    
    // This sends your steering and pedal data to the PC 60 times a second
    _transmitTimer = Timer.periodic(const Duration(milliseconds: 16), (_) => _sendInputPacket());
  }

  @override
  void dispose() {
    // Always clean up your listeners and timers, sweetheart.
    _accelSubscription?.cancel();
    _transmitTimer?.cancel();
    _heartbeatTimer?.cancel();
    _socket?.close();
    super.dispose();
  }

  void _initNetwork() async {
    // Open a UDP socket on any available port on the phone
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    setState(() { isConnected = true; });

    // Send a little "PING" to the PC every second to keep the connection alive
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_socket != null && isConnected) {
        _socket!.send("ROJX_PING".codeUnits, InternetAddress(_serverIp), _port);
      }
    });
  }

  void _sendInputPacket() {
    if (_socket == null || !isConnected) return;

    // Convert our smooth decimal numbers into the integers the Xbox driver expects
    int steerInt = (steeringValue * 32767).toInt().clamp(-32768, 32767);
    int throttleInt = (throttleValue * 255).toInt().clamp(0, 255);
    int brakeInt = (brakeValue * 255).toInt().clamp(0, 255);

    // Create our 11-byte packet
    var bd = ByteData(11);
    bd.setUint8(0, 1); // Packet Type 1
    bd.setInt16(1, steerInt, Endian.little);
    bd.setInt16(3, throttleInt, Endian.little);
    bd.setInt16(5, brakeInt, Endian.little);
    bd.setInt16(7, 0, Endian.little); 
    bd.setUint16(9, 0, Endian.little); // Buttons (we'll add these later)

    // Send it off to the PC!
    _socket!.send(bd.buffer.asUint8List(), InternetAddress(_serverIp), _port);
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: Text("Ready to build, baby.")),
    );
  }

  void _toggleGyro(bool enabled) {
    setState(() {
      isGyroMode = enabled;
      steeringValue = 0.0; // Re-center the wheel when switching modes
    });

    if (enabled) {
      // Start listening to the phone's tilt
      _accelSubscription = accelerometerEvents.listen((AccelerometerEvent event) {
        if (!isGyroMode) return;

        // event.y measures the left/right tilt in landscape mode
        setState(() {
          steeringValue = (event.y / 8.0).clamp(-1.0, 1.0);
        });
      });
    } else {
      // Stop listening if we switch back to touch mode
      _accelSubscription?.cancel();
    }
  }
}