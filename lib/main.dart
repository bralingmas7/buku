import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/google_drive_service.dart';

Future<void> _restoreGoogleSession() async {
  try {
    await GoogleDriveService.instance.restoreAccount();
  } catch (e) {
    debugPrint('Pemulihan sesi Google saat startup gagal: $e');
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _restoreGoogleSession();
  runApp(const BukuUtangApp());
}

class BukuUtangApp extends StatelessWidget {
  const BukuUtangApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Buku Utang Warung',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
        visualDensity: VisualDensity.standard,
      ),
      home: const HomeScreen(),
    );
  }
}
