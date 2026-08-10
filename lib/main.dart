// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // NEW: initialize Firebase, then activate App Check. This must happen
  // before anything else touches Firebase. Play Integrity attests that
  // requests are coming from this real, untampered app — this pairs with
  // the manual X-Firebase-AppCheck header now sent on every request in
  // firebase_service.dart, since that file talks to Firebase over plain
  // REST rather than the Firebase SDK (which would attach it
  // automatically).
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider.playIntegrity,
  );

  // Force portrait — Ludo boards don't benefit from landscape on phones.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Immersive UI: extend into status/nav bar areas with dark icons.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor:       Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0D0D1A),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const ProviderScope(child: LudoProMaxApp()));
}

class LudoProMaxApp extends StatelessWidget {
  const LudoProMaxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ludo Pro Max',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const LoginScreen(),
      // Smooth page transitions
      builder: (context, child) => MediaQuery(
        // Clamp font scale — prevents layout breaks on large-text accessibility settings.
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(
            MediaQuery.of(context).textScaleFactor.clamp(0.8, 1.2),
          ),
        ),
        child: child!,
      ),
    );
  }
}
