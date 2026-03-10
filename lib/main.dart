import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:vibration/vibration.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

void main() => runApp(const TambagApp());

class TambagApp extends StatelessWidget {
  const TambagApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: const ShelfHome(),
    );
  }
}

class ShelfHome extends StatefulWidget {
  const ShelfHome({super.key});
  @override
  State<ShelfHome> createState() => _ShelfHomeState();
}

class _ShelfHomeState extends State<ShelfHome> {
  WebSocketChannel? _channel;
  bool _isConnected = false;
  bool _isAlert = false;
  bool _isConnecting = false;
  String _statusMessage = "Ready to Scan";
  String? _activeShelfId;

  void _openScanner() async {
    final String? qrData = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const QrScannerPage()),
    );
    if (qrData != null && qrData.contains('|')) {
      _connectToShelf(qrData);
    }
  }

  void _connectToShelf(String qrData) async {
    List<String> parts = qrData.split('|');
    String ip = parts[0];
    String shelfId = parts.length > 1 ? parts[1] : "A";

    setState(() {
      _activeShelfId = shelfId;
      _isConnecting = true;
      _statusMessage = "Connecting...";
    });

    try {
      _channel = WebSocketChannel.connect(Uri.parse('ws://$ip:81'));

      await Future.delayed(const Duration(milliseconds: 600));
      _channel!.sink.add("ARM_$shelfId");

      _channel!.stream.listen(
            (message) {
          debugPrint("Incoming: $message");
          if (message == "LOCKED_$shelfId") {
            setState(() {
              _isConnected = true;
              _isConnecting = false;
              _statusMessage = "Shelf $shelfId Secured";
            });
          } else if (message == "ALERT_$shelfId") {
            if (!_isAlert) {
              setState(() => _isAlert = true);
              _showIntrusionDialog();
              Vibration.vibrate(duration: 1000);
            }
          }
        },
        onDone: () => _handleDisconnect(),
        onError: (e) => _handleDisconnect(),
      );
    } catch (e) {
      _handleDisconnect();
    }
  }

  void _showIntrusionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.red.shade900,
        title: const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 60),
        content: Text(
          "INTRUSION ON SHELF $_activeShelfId!\n\nIs it you taking the item?",
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              // USER SAYS YES: Disarm and Close
              if (_activeShelfId != null) {
                _channel?.sink.add("DISARM_$_activeShelfId");
              }
              _handleDisconnect();
              Navigator.pop(context);
            },
            child: const Text("YES, IT'S ME"),
          ),
          OutlinedButton(
            onPressed: () {
              // USER SAYS NO: Keep Guarding
              setState(() => _isAlert = false);
              Navigator.pop(context);
            },
            child: const Text("NO! NOT ME", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _handleDisconnect() {
    _channel?.sink.close();
    if (mounted) {
      setState(() {
        _isConnected = false;
        _isAlert = false;
        _isConnecting = false;
        _statusMessage = "Ready to Scan";
        _activeShelfId = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Color bgColor = _isAlert ? Colors.red.shade900 : (_isConnected ? Colors.blue.shade100 : Colors.green.shade50);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(title: const Text("TAMBAG SHELF GUARD"), centerTitle: true),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isConnecting)
              const CircularProgressIndicator()
            else
              Icon(
                _isAlert ? Icons.warning_rounded : (_isConnected ? Icons.lock : Icons.qr_code_scanner),
                size: 120,
                color: _isAlert ? Colors.white : (_isConnected ? Colors.blue : Colors.green),
              ),
            const SizedBox(height: 20),
            Text(_statusMessage, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 50),
            if (!_isConnected && !_isConnecting)
              ElevatedButton.icon(
                onPressed: _openScanner,
                icon: const Icon(Icons.camera_alt),
                label: const Text("SCAN SHELF QR"),
              ),
            if (_isConnected && !_isAlert)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: TextButton(
                  onPressed: _handleDisconnect,
                  child: const Text("STOP GUARDING", style: TextStyle(color: Colors.red)),
                ),
              )
          ],
        ),
      ),
    );
  }
}

class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});
  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  bool _scanned = false;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Align QR Code")),
      body: MobileScanner(
        onDetect: (BarcodeCapture capture) {
          if (_scanned) return;
          final List<Barcode> barcodes = capture.barcodes;
          if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
            _scanned = true;
            Navigator.pop(context, barcodes.first.rawValue);
          }
        },
      ),
    );
  }
}