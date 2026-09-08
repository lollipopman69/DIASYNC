import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/doctor_home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DiASync',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2196F3)),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasData && snapshot.data != null) {
          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('patients')
                .doc(snapshot.data!.uid)
                .snapshots(),
            builder: (context, docSnap) {
              if (!docSnap.hasData || docSnap.data == null) {
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              }
              if (!docSnap.data!.exists) {
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              }
              final data = docSnap.data!.data() as Map<String, dynamic>;
              final role = data['role'] ?? '';
              if (role.isEmpty) {
                // Doc exists but role not written yet — wait
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              }
              if (role == 'doctor') return const DoctorHomeScreen();
              return const HomeScreen();
            },
          );
        }
        return const LoginScreen();
      },
    );
  }
}