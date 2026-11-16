import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';
import 'quiz_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const CloudQuizApp());
}

class CloudQuizApp extends StatelessWidget {
  const CloudQuizApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'API-to-Cloud Quiz App',
      theme: ThemeData(primarySwatch: Colors.deepOrange),
      home: const AuthGate(),
    );
  }
}

// Decide whether to show login or quiz.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Text('Authentication error: ${snapshot.error}'),
            ),
          );
        }

        if (snapshot.hasData) {
          final user = snapshot.data!;

          return QuizScreen(key: ValueKey(user.uid), uid: user.uid);
        }

        return const SignInScreen();
      },
    );
  }
}

// Email and password login form.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool _isSigningIn = false;
  String _error = '';

  Future<void> _signIn() async {
    final email = emailController.text.trim();
    final password = passwordController.text;

    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _error = 'Please enter a valid email address.';
      });
      return;
    }

    if (password.isEmpty) {
      setState(() {
        _error = 'Please enter your password.';
      });
      return;
    }

    setState(() {
      _isSigningIn = true;
      _error = '';
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // AuthGate automatically switches to QuizScreen.
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'Sign-in failed: ${e.code}';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'Unable to sign in. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSigningIn = false;
        });
      }
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cloud Quiz Sign In')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Icon(Icons.quiz, size: 70, color: Colors.deepOrange),
              const SizedBox(height: 20),
              const Text(
                'Sign in to play the Cloud Quiz',
                style: TextStyle(fontSize: 20),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 16),

              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 16),

              if (_error.isNotEmpty)
                Text(
                  _error,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),

              const SizedBox(height: 20),

              ElevatedButton(
                onPressed: _isSigningIn ? null : _signIn,
                child: Text(_isSigningIn ? 'Signing in...' : 'Sign In'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
