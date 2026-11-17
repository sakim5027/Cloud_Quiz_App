import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html_unescape/html_unescape.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase before runApp.
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
          return const QuizScreen();
        }

        return const SignInScreen();
      },
    );
  }
}

//SignInScreen allows users to sign in with email and password.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool _isLoading = false;
  String _error = '';

  Future<void> _signIn() async {
    if (emailController.text.trim().isEmpty ||
        passwordController.text.isEmpty) {
      setState(() {
        _error = 'Please enter your email and password.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      // Code provided by your professor.
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text,
      );

      //Print the signed-in user's UID.
      debugPrint('Signed-in UID: ${FirebaseAuth.instance.currentUser?.uid}');

      // AuthGate automatically displays QuizScreen.
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'Sign-in failed: ${e.code}';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'Sign-in failed. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signUp() async {
    if (emailController.text.trim().isEmpty ||
        passwordController.text.isEmpty) {
      setState(() {
        _error = 'Please enter your email and password.';
      });
      return;
    }

    if (passwordController.text.length < 6) {
      setState(() {
        _error = 'Password must be at least 6 characters.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text,
      );

      debugPrint('Registered UID: ${FirebaseAuth.instance.currentUser?.uid}');

      // AuthGate automatically displays QuizScreen.
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'Sign-up failed: ${e.code}';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'Sign-up failed. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
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
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Sign In to Cloud Quiz',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
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
              Text(_error, style: const TextStyle(color: Colors.red)),

            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: _isLoading ? null : _signIn,
              child: Text(_isLoading ? 'Signing In...' : 'Sign In'),
            ),

            const SizedBox(height: 12),

            ElevatedButton(
              onPressed: _isLoading ? null : _signUp,
              child: const Text('Sign Up'),
            ),
          ],
        ),
      ),
    );
  }
}

//Question class represents a single quiz question with its text, correct answer, and options.
class Question {
  final String questionText;
  final String correctAnswer;
  final List<String> options;
  Question({
    required this.questionText,
    required this.correctAnswer,
    required this.options,
  });

  factory Question.fromJson(Map<String, dynamic> json) {
    final unescape = HtmlUnescape();

    // Check category, difficulty, and question type.
    if (json['category'] != 'General Knowledge' ||
        json['difficulty'] != 'easy' ||
        json['type'] != 'multiple') {
      throw FormatException('Invalid question category or type.');
    }

    // Check that question and answer fields exist.
    if (json['question'] is! String ||
        json['correct_answer'] is! String ||
        json['incorrect_answers'] is! List) {
      throw FormatException('Invalid question data.');
    }

    var incorrect = json['incorrect_answers'] as List;

    // Every question must have exactly 3 incorrect answers.
    if (incorrect.length != 3 || incorrect.any((answer) => answer is! String)) {
      throw FormatException('Expected 3 incorrect answers.');
    }

    var correct = json['correct_answer'] as String;

    // Decode HTML special characters.
    String clean(String val) => unescape.convert(val).trim();

    var allOptions = [...incorrect.cast<String>().map(clean), clean(correct)];

    // Reject empty questions or answers.
    if (clean(json['question'] as String).isEmpty ||
        allOptions.any((option) => option.isEmpty)) {
      throw FormatException('Question or answer is empty.');
    }

    // Make sure all 4 answers are different after decoding.
    if (allOptions.toSet().length != 4) {
      throw FormatException('Duplicate answer choices.');
    }

    // Shuffle only once, not inside build().
    allOptions.shuffle();

    return Question(
      questionText: clean(json['question'] as String),
      correctAnswer: clean(correct),
      options: allOptions,
    );
  }
}

//QuizScreen displays the quiz questions, handles user answers, and manages score synchronization.
class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});
  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  List<Question> _questions = [];
  bool _isLoading = true;
  String _error = '';
  int _currentIndex = 0;
  int _score = 0;
  bool _answered = false;
  String? _selectedOption;
  List<String?> _selectedAnswers = [];
  bool _isSynced = false;
  bool _isSyncing = false;
  late String _roundId;
  DateTime? _lastApiRequest;
  @override
  void initState() {
    super.initState();

    final uid = FirebaseAuth.instance.currentUser!.uid;

    _roundId = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('attempts')
        .doc()
        .id;

    _loadQuizData();
  }

  Future<void> _loadQuizData() async {
    final roundId = _roundId;

    // Wait at least 5 seconds between API requests.
    if (_lastApiRequest != null &&
        DateTime.now().difference(_lastApiRequest!) <
            const Duration(seconds: 5)) {
      setState(() {
        _error = 'Please wait 5 seconds before retrying.';
        _isLoading = false;
      });
      return;
    }

    try {
      final uri = Uri.parse(
        'https://opentdb.com/api.php?amount=10&category=9&difficulty=easy&type=multiple',
      );

      // Record when the API request begins.
      _lastApiRequest = DateTime.now();

      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Check the API response format.
        if (data is! Map<String, dynamic>) {
          throw FormatException('Invalid API response.');
        }

        if (data['response_code'] == 0) {
          // Check that results is a list.
          if (data['results'] is! List) {
            throw FormatException('Invalid results data.');
          }

          final results = data['results'] as List;

          if (!mounted || roundId != _roundId) return;

          // Require exactly 10 questions.
          if (results.length != 10) {
            throw FormatException(
              'Expected 10 questions, but received ${results.length}.',
            );
          }

          // Validate all questions before allowing gameplay.
          final questions = results.map((q) {
            if (q is! Map<String, dynamic>) {
              throw FormatException('Invalid question format.');
            }

            return Question.fromJson(q);
          }).toList();

          setState(() {
            _questions = questions;
            _selectedAnswers = List<String?>.filled(questions.length, null);
            _error = '';
            _isLoading = false;
          });
        } else {
          if (!mounted || roundId != _roundId) return;

          setState(() {
            _error =
                'Quiz API returned response code ${data['response_code']}. Please try again.';
            _isLoading = false;
          });
        }
      } else {
        if (!mounted || roundId != _roundId) return;

        setState(() {
          _error = 'Server error: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted || roundId != _roundId) return;

      setState(() {
        _error = 'Connection failed: $e';
        _isLoading = false;
      });
    }
  }

  
  void _answerQuestion(String option) {
    if (_answered) return;

    setState(() {
      _answered = true;
      _selectedOption = option;

      // Save the selected answer for review.
      _selectedAnswers[_currentIndex] = option;

      if (option == _questions[_currentIndex].correctAnswer) {
        _score++;
      }
    });
  }


  void _nextQuestion() {
    setState(() {
      if (_currentIndex < _questions.length - 1) {
        _currentIndex++;
        _answered = false;
        _selectedOption = null;
      } else {
        _currentIndex++; // triggers results screen
      }
    });
  }

  Future<void> _syncScoreToCloud() async {
    if (_isSyncing || _isSynced) return;
    final roundId = _roundId;

    // Create a simulated submission payload.
    final payload = {
      'score': _score,
      'totalQuestions': _questions.length,
      'roundId': roundId,
    };

    setState(() {
      _isSyncing = true;
    });

    // Display the payload in the debug console.
    debugPrint('Simulated submission payload: ${jsonEncode(payload)}');

    // Simulate waiting for a server.
    await Future.delayed(const Duration(seconds: 1));

    if (!mounted || roundId != _roundId) return;

    setState(() {
      _isSyncing = false;
      _isSynced = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Simulation complete. No real backend request was sent.'),
      ),
    );
  }

  void _retryQuiz() {
    setState(() {
      _isLoading = true;
      _error = '';
      _questions = [];
      _currentIndex = 0;
      _score = 0;
      _answered = false;
      _selectedOption = null;
    });

    // Retry without changing the round ID.
    _loadQuizData();
  }

  
  void _restart() {
    if (_isSyncing) return;

    final uid = FirebaseAuth.instance.currentUser!.uid;

    setState(() {
      // Generate a new ID for a new quiz round.
      _roundId = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('attempts')
          .doc()
          .id;

      _isLoading = true;
      _error = '';
      _questions = [];
      _selectedAnswers = [];
      _currentIndex = 0;
      _score = 0;
      _answered = false;
      _selectedOption = null;
      _isSynced = false;
      _isSyncing = false;
    });

    _loadQuizData();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cloud Quiz App: API Edition'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _isSyncing
                ? null
                : () async {
                    await FirebaseAuth.instance.signOut();
                  },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error.isNotEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _error,
                      style: const TextStyle(color: Colors.red, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _retryQuiz,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            : _currentIndex >= _questions.length
            ? SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Quiz Complete!',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Final Score: $_score / ${_questions.length}',
                      style: const TextStyle(fontSize: 18),
                    ),
                    const SizedBox(height: 24),

                    const Text(
                      'Answer Review',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 12),

                    ...List.generate(_questions.length, (index) {
                      final question = _questions[index];
                      final selected = _selectedAnswers[index];
                      final correct = selected == question.correctAnswer;

                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${index + 1}. ${question.questionText}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text('Your Answer: ${selected ?? "No answer"}'),
                              Text('Correct Answer: ${question.correctAnswer}'),
                              Text(
                                correct ? '✓ Correct' : '✗ Incorrect',
                                style: TextStyle(
                                  color: correct ? Colors.green : Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),

                    const SizedBox(height: 24),

                    if (!_isSynced)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                        onPressed: _isSyncing ? null : _syncScoreToCloud,
                        icon: const Icon(Icons.cloud_upload),
                        label: Text(
                          _isSyncing
                              ? 'Simulating sync...'
                              : 'Simulate Score Sync to Leaderboard',
                        ),
                      )
                    else
                      const Text(
                        '✓ Sync Simulation Complete',
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _isSyncing ? null : _restart,
                      child: const Text('Play Again'),
                    ),
                  ],
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LinearProgressIndicator(
                    value: (_currentIndex + 1) / _questions.length,
                    backgroundColor: Colors.orange.shade100,
                    color: Colors.deepOrange,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Question ${_currentIndex + 1} of ${_questions.length}',
                    style: const TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Text(
                        _questions[_currentIndex].questionText,
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ..._questions[_currentIndex].options.map((opt) {
                    Color btnColor = Colors.white;
                    if (_answered) {
                      if (opt == _questions[_currentIndex].correctAnswer) {
                        btnColor = Colors.green.shade200;
                      } else if (opt == _selectedOption) {
                        btnColor = Colors.red.shade200;
                      }
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: btnColor,
                          foregroundColor: Colors.black87,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: () => _answerQuestion(opt),
                        child: Text(opt, style: const TextStyle(fontSize: 16)),
                      ),
                    );
                  }),
                  const Spacer(),
                  if (_answered)
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: _nextQuestion,
                      child: Text(
                        _currentIndex < _questions.length - 1
                            ? 'Next Question →'
                            : 'View Final Score',
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
