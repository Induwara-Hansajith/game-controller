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
    return Scaffold(
      backgroundColor: Colors.black,
      body: Row(
        children: [
          // LEFT PANEL: Steering Control
          Expanded(
            flex: 4,
            child: Container(
              color: const Color(0xFF1A1D24), 
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // The Touch Steering Wheel
                  IgnorePointer(
                    ignoring: isGyroMode, // Gently ignore touches if we are tilting the phone
                    child: GestureDetector(
                      onPanUpdate: (details) {
                        setState(() {
                          touchWheelAngle += details.delta.dx * 0.01;
                          double limitedAngle = touchWheelAngle.clamp(-1.57, 1.57);
                          touchWheelAngle = limitedAngle;
                          steeringValue = limitedAngle / 1.57;
                        });
                      },
                      onPanEnd: (_) {
                        setState(() { 
                          touchWheelAngle = 0.0;
                          steeringValue = 0.0;
                        });
                      },
                      child: Transform.rotate(
                        angle: isGyroMode ? 0.0 : touchWheelAngle,
                        // We will use a simple circle for now until you add your custom images!
                        child: Container(
                          width: 250,
                          height: 250,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white30, width: 8),
                            color: Colors.white10,
                          ),
                          child: const Center(
                            child: Icon(Icons.drive_eta, color: Colors.white30, size: 50),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // The Sweet Little Mode Toggle
                  Positioned(
                    top: 20,
                    child: Row(
                      children: [
                        const Text("Touch", style: TextStyle(color: Colors.white70)),
                        Switch(
                          value: isGyroMode,
                          onChanged: _toggleGyro,
                          activeColor: Colors.cyanAccent,
                        ),
                        const Text("Gyro", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // MIDDLE PANEL: Dashboard
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.all(10),
              color: Colors.black,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Text(
                    isConnected ? "Connected" : "Waiting...", 
                    style: TextStyle(
                      color: isConnected ? Colors.greenAccent : Colors.amberAccent,
                      fontSize: 16,
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildControlButton("HB"),
                      _buildControlButton("CAM"),
                    ],
                  )
                ],
              ),
            ),
          ),

          // RIGHT PANEL: Analog Pedals
          Expanded(
            flex: 3,
            child: Container(
              color: const Color(0xFF1A1D24),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildPedal("BRAKE", Colors.redAccent, (val) => setState(() => brakeValue = val)),
                  _buildPedal("ACCEL", Colors.greenAccent, (val) => setState(() => throttleValue = val)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Gentle Helper Functions ---

  Widget _buildControlButton(String text) {
    return Container(
      width: 60,
      height: 40,
      decoration: BoxDecoration(
        color: const Color(0xFF323846),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: Colors.white24)
      ),
      alignment: Alignment.center,
      child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildPedal(String label, Color color, Function(double) onChanged) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Expanded(
          child: Container(
            width: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF101216),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12, width: 2)
            ),
            child: RotatedBox(
              quarterTurns: 3, 
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 80, 
                  thumbShape: SliderComponentShape.noThumb, 
                  activeTrackColor: color.withOpacity(0.6),
                  inactiveTrackColor: Colors.transparent,
                  overlayColor: Colors.transparent,
                ),
                child: Slider(
                  value: label == "ACCEL" ? throttleValue : brakeValue,
                  onChanged: onChanged,
                  onChangeEnd: (_) => onChanged(0.0), 
                ),
              ),
            ),
          ),
        ),
      ],
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