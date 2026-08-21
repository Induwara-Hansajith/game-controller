import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

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
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: Text("Ready to build, baby.")),
    );
  }
}