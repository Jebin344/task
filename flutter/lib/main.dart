import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'package:vector_math/vector_math_64.dart' as vm;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pose',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF0A0E21),
      ),
      home: const PoseMimicScreen(),
    );
  }
}

class PoseMimicScreen extends StatefulWidget {
  const PoseMimicScreen({super.key});

  @override
  State<PoseMimicScreen> createState() => _PoseMimicScreenState();
}

class _PoseMimicScreenState extends State<PoseMimicScreen> with TickerProviderStateMixin {
  Socket? _socket;
  bool _isConnected = false;
  String _status = 'Disconnected';
  List<List<double>>? _landmarks;

  final TextEditingController _hostController = TextEditingController(text: '10.0.2.2');
  final TextEditingController _portController = TextEditingController(text: '8765');

  late AnimationController _rotationController;
  double _rotationY = 0;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    );
    _isConnected?_disconnect(): _connectToServer();
  }

  Future<void> _connectToServer() async {
    try {
      setState(() {
        _status = 'Connecting...';
      });

      _socket = await Socket.connect(
        _hostController.text,
        int.parse(_portController.text),
        timeout: const Duration(seconds: 10),
      );

      setState(() {
        _isConnected = true;
        _status = 'Connected - Waiting for data...';
      });

      _socket!.listen(
        _onData,
        onError: (error) {
          setState(() {
            _status = 'Error: $error';
            _isConnected = false;
          });
          _disconnect();
        },
        onDone: () {
          setState(() {
            _status = 'Connection closed by server';
            _isConnected = false;
          });
          _disconnect();
        },
        cancelOnError: false,
      );

      _socket!.write('CONNECTED\n');

    } on SocketException catch (e) {
      String errorMsg = 'Connection failed: ';

      if (e.osError?.errorCode == 61 || e.osError?.errorCode == 111) {
        errorMsg += 'Server not running or refusing connections';
      } else if (e.osError?.errorCode == 60 || e.osError?.errorCode == 110) {
        errorMsg += 'Connection timeout - check IP/firewall';
      } else if (e.osError?.errorCode == 51 || e.osError?.errorCode == 101) {
        errorMsg += 'Network unreachable - check WiFi/IP';
      } else {
        errorMsg += e.message;
      }

      setState(() {
        _status = errorMsg;
        _isConnected = false;
      });
    } on FormatException catch (e) {
      setState(() {
        _status = 'Invalid port number';
        _isConnected = false;
      });
    } catch (e) {
      setState(() {
        _status = 'Failed: $e';
        _isConnected = false;
      });
    }
  }

  void _onData(List<int> data) {
    try {
      String message = utf8.decode(data);

      List<String> messages = message.split('\n');

      for (String msg in messages) {
        if (msg.trim().isEmpty) continue;

        try {
          Map<String, dynamic> poseData = jsonDecode(msg);

          if (poseData.containsKey('landmarks')) {
            List<List<double>> landmarksList = [];

            for (var landmark in poseData['landmarks']) {
              List<double> point = [];
              for (var value in landmark) {
                if (value is num) {
                  point.add(value.toDouble());
                } else {
                  point.add(0.0);
                }
              }
              landmarksList.add(point);
            }

            setState(() {
              _landmarks = landmarksList;
              if (_status == 'Connected - Waiting for data...') {
                _status = 'Connected - Receiving pose data';
              }
            });

          }
        } catch (e) {
          print('Message: $msg');
        }
      }
    } catch (e) {
      print('Error decoding data: $e');
    }
  }

  void _disconnect() {
    _socket?.close();
    _socket = null;
    setState(() {
      _isConnected = false;
      _status = 'Disconnected';
      _landmarks = null;
    });
  }

  @override
  void dispose() {
    _disconnect();
    _rotationController.dispose();
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pose'),
        backgroundColor: const Color(0xFF1D1E33),
      ),
      body: Column(
        children: [
          _buildConnectionPanel(),
          Expanded(
            child: _isConnected
                ? _build3DView()
                : _buildConnectionInstructions(),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Expanded(
              //   child: TextField(
              //     controller: _hostController,
              //     decoration: const InputDecoration(
              //       labelText: 'Server IP',
              //       border: OutlineInputBorder(),
              //       contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              //     ),
              //     enabled: !_isConnected,
              //   ),
              // ),
              // const SizedBox(width: 12),
              // SizedBox(
              //   width: 100,
              //   child: TextField(
              //     controller: _portController,
              //     decoration: const InputDecoration(
              //       labelText: 'Port',
              //       border: OutlineInputBorder(),
              //       contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              //     ),
              //     keyboardType: TextInputType.number,
              //     enabled: !_isConnected,
              //   ),
              // ),
              // const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _isConnected ? _disconnect : _connectToServer,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isConnected ? Colors.red : Colors.green,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                ),
                child: Text(_isConnected ? 'Disconnect' : 'Connect'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: _isConnected ? Colors.green : Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _status,
                  style: TextStyle(
                    color: _isConnected ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionInstructions() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        margin: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF1D1E33),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.wifi_off, size: 64, color: Colors.grey),
      ),
    );
  }

  Widget _build3DView() {
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        setState(() {
          _rotationY += details.delta.dx * 0.01;
        });
      },
      child: CustomPaint(
        painter: Pose3DPainter(
          landmarks: _landmarks,
          rotationY: _rotationY,
        ),
        child: Container(),
      ),
    );
  }
}

class Pose3DPainter extends CustomPainter {
  final List<List<double>>? landmarks;
  final double rotationY;

  Pose3DPainter({
    required this.landmarks,
    required this.rotationY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (landmarks == null || landmarks!.length < 33) {
      _drawNoDataMessage(canvas, size);
      return;
    }

    final paint = Paint()
      ..color = Colors.cyan
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    final jointPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = Colors.black26
      ..style = PaintingStyle.fill;

    final center = Offset(size.width / 2, size.height / 2);
    final scale = size.width * 0.8;

    _drawShadow(canvas, size, shadowPaint);

    _drawConnection(canvas, center, scale, 11, 12, paint); // Shoulders
    _drawConnection(canvas, center, scale, 11, 13, paint); // Left arm
    _drawConnection(canvas, center, scale, 13, 15, paint); // Left forearm
    _drawConnection(canvas, center, scale, 12, 14, paint); // Right arm
    _drawConnection(canvas, center, scale, 14, 16, paint); // Right forearm
    _drawConnection(canvas, center, scale, 11, 23, paint); // Left torso
    _drawConnection(canvas, center, scale, 12, 24, paint); // Right torso
    _drawConnection(canvas, center, scale, 23, 24, paint); // Hips
    _drawConnection(canvas, center, scale, 23, 25, paint); // Left thigh
    _drawConnection(canvas, center, scale, 25, 27, paint); // Left shin
    _drawConnection(canvas, center, scale, 24, 26, paint); // Right thigh
    _drawConnection(canvas, center, scale, 26, 28, paint); // Right shin

    _drawConnection(canvas, center, scale, 0, 1, paint);
    _drawConnection(canvas, center, scale, 1, 2, paint);
    _drawConnection(canvas, center, scale, 2, 3, paint);
    _drawConnection(canvas, center, scale, 3, 7, paint);

    for (int i in [0, 11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28]) {
      final point = _project3DPoint(
        landmarks![i][0],
        landmarks![i][1],
        landmarks![i][2],
        center,
        scale,
      );
      canvas.drawCircle(point, 6, jointPaint);
    }

    _drawInfoText(canvas, size);
  }

  void _drawShadow(Canvas canvas, Size size, Paint paint) {
    final shadowCenter = Offset(size.width / 2, size.height * 0.85);
    canvas.drawOval(
      Rect.fromCenter(
        center: shadowCenter,
        width: 150,
        height: 50,
      ),
      paint,
    );
  }

  void _drawConnection(Canvas canvas, Offset center, double scale,
      int idx1, int idx2, Paint paint) {
    if (landmarks == null ||
        idx1 >= landmarks!.length ||
        idx2 >= landmarks!.length) {
      return;
    }

    final point1 = _project3DPoint(
      landmarks![idx1][0],
      landmarks![idx1][1],
      landmarks![idx1][2],
      center,
      scale,
    );

    final point2 = _project3DPoint(
      landmarks![idx2][0],
      landmarks![idx2][1],
      landmarks![idx2][2],
      center,
      scale,
    );

    final gradient = LinearGradient(
      colors: [Colors.cyan.withOpacity(0.6), Colors.blue],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );

    final gradientPaint = Paint()
      ..shader = gradient.createShader(Rect.fromPoints(point1, point2))
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(point1, point2, gradientPaint);
  }

  Offset _project3DPoint(double x, double y, double z, Offset center, double scale) {
    x = 1.0 - x;

    double cx = (x - 0.5) * scale;
    double cy = (y - 0.5) * scale;
    double cz = z * scale;

    final cosY = math.cos(rotationY);
    final sinY = math.sin(rotationY);

    double rotatedX = cx * cosY - cz * sinY;
    double rotatedZ = cx * sinY + cz * cosY;

    final perspective = 1000.0;
    final projectedX = rotatedX * perspective / (perspective + rotatedZ);
    final projectedY = cy * perspective / (perspective + rotatedZ);

    return Offset(
      center.dx + projectedX,
      center.dy + projectedY,
    );
  }

  void _drawNoDataMessage(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'Waiting for pose data...\nStand in front of the webcam',
        style: TextStyle(
          color: Colors.white54,
          fontSize: 18,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        (size.height - textPainter.height) / 2,
      ),
    );
  }

  void _drawInfoText(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      text: const TextSpan(
        text: '← Drag to rotate →',
        style: TextStyle(
          color: Colors.white54,
          fontSize: 14,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        size.height - 40,
      ),
    );
  }

  @override
  bool shouldRepaint(Pose3DPainter oldDelegate) {
    return oldDelegate.landmarks != landmarks ||
        oldDelegate.rotationY != rotationY;
  }
}