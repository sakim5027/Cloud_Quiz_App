import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html_unescape/html_unescape.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';

const String testApiError = '';
const String testCloudError = '';
const bool testLostAcknowledgement = false;

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

// Check whether the user is signed in.
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
          return QuizScreen(key: ValueKey(snapshot.data!.uid));
        }

        return const SignInScreen();
      },
    );
  }
}

// SignInScreen allows users to sign in or sign up.
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
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text,
      );

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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const SizedBox(height: 80),

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

// Question class represents a single quiz question.
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

    // Check category, difficulty, and type.
    if (json['category'] != 'General Knowledge' ||
        json['difficulty'] != 'easy' ||
        json['type'] != 'multiple') {
      throw const FormatException('Invalid question category or type.');
    }

    if (json['question'] is! String ||
        json['correct_answer'] is! String ||
        json['incorrect_answers'] is! List) {
      throw const FormatException('Invalid question data.');
    }

    var incorrect = json['incorrect_answers'] as List;

    if (incorrect.length != 3 || incorrect.any((answer) => answer is! String)) {
      throw const FormatException('Expected 3 incorrect answers.');
    }

    var correct = json['correct_answer'] as String;

    // Decode HTML characters.
    String clean(String val) => unescape.convert(val).trim();

    var allOptions = [...incorrect.cast<String>().map(clean), clean(correct)];

    if (clean(json['question'] as String).isEmpty ||
        allOptions.any((option) => option.isEmpty)) {
      throw const FormatException('Question or answer is empty.');
    }

    if (allOptions.toSet().length != 4) {
      throw const FormatException('Duplicate answer choices.');
    }

    // Shuffle once, not inside build().
    allOptions.shuffle();

    return Question(
      questionText: clean(json['question'] as String),
      correctAnswer: clean(correct),
      options: allOptions,
    );
  }
}

// QuizScreen handles questions, scoring, and cloud submission.
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
  late String _roundUid;

  // Keep a shared request time across QuizScreen instances.
  static DateTime? _lastApiRequest;
  int _requestId = 0;

  // Cloud submission state.
  String _cloudState = 'playing';
  String _cloudMessage = '';
  String _verifiedPath = '';
  String _lastAttemptMessage = '';

  // Freeze the completed round's submission values.
  int? _frozenScore;
  Map<String, dynamic>? _frozenPayload;

  bool get _sameUser {
    return FirebaseAuth.instance.currentUser?.uid == _roundUid;
  }

  // Disable replay/sign-out while cloud status is unresolved.
  bool get _canLeave {
    return !_isSyncing &&
        (_cloudState == 'playing' ||
            _cloudState == 'readyToSubmit' ||
            _cloudState == 'cloudVerified');
  }

  // Reference for this exact quiz round.
  DocumentReference<Map<String, dynamic>> get _attemptRef {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(_roundUid)
        .collection('attempts')
        .doc(_roundId);
  }

  @override
  void initState() {
    super.initState();

    _roundUid = FirebaseAuth.instance.currentUser!.uid;

    // Generate an ID without creating a document.
    _roundId = FirebaseFirestore.instance
        .collection('users')
        .doc(_roundUid)
        .collection('attempts')
        .doc()
        .id;

    _loadQuizData();
    _retrieveLastAttempt();
  }

  Future<void> _loadQuizData() async {
    final roundId = _roundId;
    final requestId = ++_requestId;

    // Respect OpenTDB's five-second request interval.
    if (_lastApiRequest != null &&
        DateTime.now().difference(_lastApiRequest!) <
            const Duration(seconds: 5)) {
      if (!mounted) return;

      setState(() {
        _error = 'Please wait at least 5 seconds before retrying.';
        _isLoading = false;
        _cloudState = 'requestError';
      });
      return;
    }

    try {
      final uri = Uri.parse(
        'https://opentdb.com/api.php?amount=10&category=9&difficulty=easy&type=multiple',
      );

      _lastApiRequest = DateTime.now();

      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        if (testApiError == 'badJson') {
          throw const FormatException('Injected malformed JSON.');
        }

        final data = json.decode(response.body);

        if (data is! Map<String, dynamic>) {
          throw const FormatException('Invalid API response.');
        }

        if (data['response_code'] == 0 && testApiError != 'apiCode') {
          if (data['results'] is! List) {
            throw const FormatException('Invalid results data.');
          }

          final results = data['results'] as List;

          if (!mounted ||
              !_sameUser ||
              roundId != _roundId ||
              requestId != _requestId) {
            return;
          }

          if (results.length != 10 || testApiError == 'nineResults') {
            throw FormatException(
              'Expected 10 questions, but received '
              '${testApiError == 'nineResults' ? 9 : results.length}.',
            );
          }

          // Validate all 10 questions before play.
          final questions = results.map((q) {
            if (q is! Map<String, dynamic>) {
              throw const FormatException('Invalid question format.');
            }

            return Question.fromJson(q);
          }).toList();

          if (!mounted ||
              !_sameUser ||
              roundId != _roundId ||
              requestId != _requestId) {
            return;
          }

          setState(() {
            _questions = questions;
            _selectedAnswers = List<String?>.filled(questions.length, null);
            _error = '';
            _isLoading = false;
            _cloudState = 'playing';
          });
        } else {
          if (!mounted ||
              !_sameUser ||
              roundId != _roundId ||
              requestId != _requestId) {
            return;
          }

          setState(() {
            _error =
                'Quiz API returned response code '
                '${testApiError == 'apiCode' ? 5 : data['response_code']}. '
                'Please try again.';
            _isLoading = false;
            _cloudState = 'requestError';
          });
        }
      } else {
        if (!mounted ||
            !_sameUser ||
            roundId != _roundId ||
            requestId != _requestId) {
          return;
        }

        setState(() {
          _error = 'Server error: ${response.statusCode}';
          _isLoading = false;
          _cloudState = 'requestError';
        });
      }
    } catch (e) {
      if (!mounted ||
          !_sameUser ||
          roundId != _roundId ||
          requestId != _requestId) {
        return;
      }

      setState(() {
        _error = 'Could not load quiz: $e';
        _isLoading = false;
        _cloudState = 'requestError';
      });
    }
  }

  void _answerQuestion(String option) {
    if (_answered || !_sameUser) return;

    setState(() {
      _answered = true;
      _selectedOption = option;

      _selectedAnswers[_currentIndex] = option;

      if (option == _questions[_currentIndex].correctAnswer) {
        _score++;
      }
    });
  }

  void _nextQuestion() {
    if (!_answered) return;

    setState(() {
      if (_currentIndex < _questions.length - 1) {
        _currentIndex++;
        _answered = false;
        _selectedOption = null;
      } else {
        _currentIndex++; // Triggers results screen.
        _cloudState = 'readyToSubmit';
      }
    });
  }

  bool _fieldsMatch(Map<String, dynamic> data) {
    return data['schemaVersion'] is int &&
        data['schemaVersion'] == 1 &&
        data['variant'] == 'A' &&
        data['categoryId'] is int &&
        data['categoryId'] == 9 &&
        data['questionCount'] is int &&
        data['questionCount'] == 10 &&
        data['correctCount'] is int &&
        data['correctCount'] == _frozenScore;
  }

  bool _verifiedDocumentMatches(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();

    return snapshot.exists &&
        !snapshot.metadata.hasPendingWrites &&
        data != null &&
        data.length == 6 &&
        _fieldsMatch(data) &&
        data['submittedAt'] is Timestamp;
  }

  Future<void> _rememberVerifiedAttempt(String uid, String roundId) async {
    try {
      final prefs = SharedPreferencesAsync();

      // Store only the ID, not questions or credentials.
      await prefs.setString('lastAttempt_$uid', roundId);
    } catch (e) {
      debugPrint('Could not remember last attempt: $e');
    }
  }

  // T07: Retrieve the last verified attempt after restart.
  Future<void> _retrieveLastAttempt() async {
    final uid = _roundUid;

    try {
      final prefs = SharedPreferencesAsync();
      final lastId = await prefs.getString('lastAttempt_$uid');

      if (lastId == null) return;

      final ref = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('attempts')
          .doc(lastId);

      final snapshot = await ref.get(const GetOptions(source: Source.server));

      if (!mounted || !_sameUser) return;

      final data = snapshot.data();

      if (snapshot.exists &&
          !snapshot.metadata.hasPendingWrites &&
          data != null &&
          data.length == 6 &&
          data['schemaVersion'] == 1 &&
          data['variant'] == 'A' &&
          data['categoryId'] == 9 &&
          data['questionCount'] == 10 &&
          data['correctCount'] is int &&
          data['correctCount'] >= 0 &&
          data['correctCount'] <= 10 &&
          data['submittedAt'] is Timestamp) {
        setState(() {
          _lastAttemptMessage =
              'Previous server attempt:\n${ref.path}\n'
              'Score: ${data['correctCount']}/10';
        });
      }
    } catch (e) {
      if (!mounted || !_sameUser) return;

      setState(() {
        _lastAttemptMessage = 'Previous attempt lookup unavailable: $e';
      });
    }
  }

  Future<void> _syncScoreToCloud() async {
    if (_isSyncing || _isSynced || !_sameUser) return;

    // Submit only after completing all 10 questions.
    if (_cloudState != 'readyToSubmit' ||
        _questions.length != 10 ||
        _currentIndex != 10 ||
        _selectedAnswers.length != 10 ||
        _selectedAnswers.any((answer) => answer == null)) {
      return;
    }

    final uid = _roundUid;
    final roundId = _roundId;
    final ref = _attemptRef;

    // Freeze the score and payload once per round.
    _frozenScore ??= _score;

    _frozenPayload ??= {
      'schemaVersion': 1,
      'variant': 'A',
      'categoryId': 9,
      'questionCount': 10,
      'correctCount': _frozenScore,
      'submittedAt': FieldValue.serverTimestamp(),
    };

    bool transactionCompleted = false;

    setState(() {
      _isSyncing = true;
      _cloudState = 'submitting';
      _cloudMessage = 'Submitting score to Firestore...';
    });

    try {
      if (testCloudError.isNotEmpty) {
        // Inject a test error without contacting Firestore.
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: testCloudError,
          message: 'Injected development test error.',
        );
      }

      // Read before writing; never overwrite an existing attempt.
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final existing = await transaction.get(ref);

        if (existing.exists) {
          final data = existing.data();

          if (data == null ||
              data.length != 6 ||
              data['submittedAt'] is! Timestamp ||
              !_fieldsMatch(data)) {
            throw StateError(
              'Document collision: existing data does not match.',
            );
          }

          // Matching document already exists. No new write.
          return;
        }

        transaction.set(ref, _frozenPayload!);
      });

      transactionCompleted = true;

      if (!mounted || !_sameUser || roundId != _roundId) return;

      if (testLostAcknowledgement) {
        // Development test: the real transaction completed,
        // but the UI ignores its acknowledgement.
        setState(() {
          _cloudState = 'saveUnknown';
          _cloudMessage =
              'Injected lost acknowledgement. '
              'Use Resolve with Server Read.';
        });
        return;
      }

      setState(() {
        _cloudState = 'verifying';
        _cloudMessage = 'Verifying saved document...';
      });

      // Server-only read provided by the professor.
      final verified = await ref.get(const GetOptions(source: Source.server));

      if (!mounted || !_sameUser || roundId != _roundId) return;

      if (!_verifiedDocumentMatches(verified)) {
        setState(() {
          _cloudState = 'verificationUnavailable';
          _cloudMessage = 'Server document missing or fields do not match.';
        });
        return;
      }

      // Only display success after server verification.
      setState(() {
        _isSynced = true;
        _cloudState = 'cloudVerified';
        _cloudMessage = 'Cloud verified';
        _verifiedPath = ref.path;
      });

      debugPrint('Cloud verified: ${ref.path}');

      await _rememberVerifiedAttempt(uid, roundId);
    } on FirebaseException catch (e) {
      if (!mounted || !_sameUser || roundId != _roundId) return;

      setState(() {
        if (transactionCompleted) {
          _cloudState = 'verificationUnavailable';
          _cloudMessage =
              'Save completed, but verification unavailable: ${e.code}';
        } else if (e.code == 'permission-denied' ||
            e.code == 'unauthenticated') {
          _cloudState = 'permissionDenied';
          _cloudMessage = 'Access denied: ${e.code}';
        } else if (e.code == 'resource-exhausted') {
          _cloudState = 'saveUnknown';
          _cloudMessage = 'Resource limit reached. Resolve before retrying.';
        } else if (e.code == 'unavailable') {
          _cloudState = 'saveUnknown';
          _cloudMessage =
              'Cloud unavailable or offline. Reconnect and resolve.';
        } else {
          _cloudState = 'saveUnknown';
          _cloudMessage = 'Cloud error: ${e.code}. Resolve before retrying.';
        }
      });
    } on StateError catch (e) {
      if (!mounted || !_sameUser || roundId != _roundId) return;

      setState(() {
        _cloudState = 'permissionDenied';
        _cloudMessage = e.message.toString();
      });
    } catch (e) {
      if (!mounted || !_sameUser || roundId != _roundId) return;

      setState(() {
        _cloudState = transactionCompleted
            ? 'verificationUnavailable'
            : 'saveUnknown';
        _cloudMessage = 'Cloud operation could not be confirmed: $e';
      });
    } finally {
      if (mounted && _sameUser && roundId == _roundId) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  // --------------------------------------
  // RESOLVE AN UNCERTAIN SUBMISSION
  // --------------------------------------

  Future<void> _resolveSubmission() async {
    if (_isSyncing || _isSynced || !_sameUser) return;
    if (_frozenPayload == null) return;

    final uid = _roundUid;
    final roundId = _roundId;
    final ref = _attemptRef;

    setState(() {
      _isSyncing = true;
      _cloudState = 'verifying';
      _cloudMessage = 'Checking the exact document on the server...';
    });

    try {
      final verified = await ref.get(const GetOptions(source: Source.server));

      if (!mounted || !_sameUser || roundId != _roundId) return;

      if (!verified.exists) {
        // There is no outstanding transaction Future here.
        // Retry may use the same round ID.
        setState(() {
          _cloudState = 'readyToSubmit';
          _cloudMessage =
              'No saved attempt found. '
              'You may retry Submit with the same round ID.';
        });
        return;
      }

      if (!_verifiedDocumentMatches(verified)) {
        setState(() {
          _cloudState = 'permissionDenied';
          _cloudMessage =
              'Document collision or invalid saved data. '
              'Do not overwrite this attempt.';
        });
        return;
      }

      setState(() {
        _isSynced = true;
        _cloudState = 'cloudVerified';
        _cloudMessage = 'Cloud verified';
        _verifiedPath = ref.path;
      });

      await _rememberVerifiedAttempt(uid, roundId);
    } on FirebaseException catch (e) {
      if (!mounted || !_sameUser || roundId != _roundId) return;

      setState(() {
        _cloudState =
            (e.code == 'permission-denied' || e.code == 'unauthenticated')
            ? 'permissionDenied'
            : 'saveUnknown';

        _cloudMessage = 'Server recovery unavailable: ${e.code}';
      });
    } catch (e) {
      if (!mounted || !_sameUser || roundId != _roundId) return;

      setState(() {
        _cloudState = 'saveUnknown';
        _cloudMessage = 'Server recovery failed: $e';
      });
    } finally {
      if (mounted && _sameUser && roundId == _roundId) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  void _retryQuiz() {
    if (_isSyncing || !_sameUser) return;

    setState(() {
      _isLoading = true;
      _error = '';
      _questions = [];
      _selectedAnswers = [];
      _currentIndex = 0;
      _score = 0;
      _answered = false;
      _selectedOption = null;
      _cloudState = 'loading';
    });

    // Keep the same round ID.
    _loadQuizData();
  }

  void _restart() {
    if (!_canLeave || !_sameUser) return;

    final uid = _roundUid;

    // Invalidate older API responses.
    _requestId++;

    setState(() {
      // Generate a new round ID.
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

      _cloudState = 'loading';
      _cloudMessage = '';
      _verifiedPath = '';

      _frozenScore = null;
      _frozenPayload = null;
    });

    _loadQuizData();
  }

  Future<void> _signOut() async {
    if (!_canLeave) return;

    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cloud Quiz App: API Edition'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _canLeave ? _signOut : null,
          ),
        ],
      ),

      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            // API error screen.
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
            // Final score and answer review.
            : _currentIndex >= _questions.length
            ? SingleChildScrollView(
                child: Column(
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
                                '${index + 1}. '
                                '${question.questionText}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Your Answer: '
                                '${selected ?? "No answer"}',
                              ),
                              Text(
                                'Correct Answer: '
                                '${question.correctAnswer}',
                              ),
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

                    // Submit button.
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
                        onPressed: !_isSyncing && _cloudState == 'readyToSubmit'
                            ? _syncScoreToCloud
                            : null,
                        icon: const Icon(Icons.cloud_upload),
                        label: Text(
                          _isSyncing
                              ? 'Processing...'
                              : 'Submit Score to Firestore',
                        ),
                      )
                    else
                      const Text(
                        '✓ Cloud verified',
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),

                    const SizedBox(height: 12),

                    // Recovery button for uncertain results.
                    if (!_isSynced &&
                        (_cloudState == 'saveUnknown' ||
                            _cloudState == 'verificationUnavailable' ||
                            _cloudState == 'permissionDenied'))
                      ElevatedButton(
                        onPressed: _isSyncing ? null : _resolveSubmission,
                        child: const Text('Resolve with Server Read'),
                      ),

                    if (_cloudMessage.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_cloudMessage, textAlign: TextAlign.center),
                      ),

                    Text(
                      'Cloud state: $_cloudState',
                      style: const TextStyle(fontSize: 12),
                    ),

                    const SizedBox(height: 8),

                    SelectableText(
                      'Document: ${_attemptRef.path}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11),
                    ),

                    if (_isSynced)
                      SelectableText(
                        'Verified document: $_verifiedPath',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11),
                      ),

                    const SizedBox(height: 16),

                    TextButton(
                      onPressed: _canLeave ? _restart : null,
                      child: const Text('Play Again'),
                    ),

                    if (_lastAttemptMessage.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _lastAttemptMessage,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                  ],
                ),
              )
            // Original quiz question screen.
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
                    'Question ${_currentIndex + 1} '
                    'of ${_questions.length}',
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
                          disabledBackgroundColor: btnColor,
                          disabledForegroundColor: Colors.black87,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: _answered
                            ? null
                            : () => _answerQuestion(opt),
                        child: Text(opt, style: const TextStyle(fontSize: 16)),
                      ),
                    );
                  }),

                  const Spacer(),

                  // Text feedback as well as green/red colors.
                  if (_answered)
                    Text(
                      _selectedOption == _questions[_currentIndex].correctAnswer
                          ? '✓ Correct!'
                          : '✗ Incorrect!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color:
                            _selectedOption ==
                                _questions[_currentIndex].correctAnswer
                            ? Colors.green
                            : Colors.red,
                      ),
                    ),

                  const SizedBox(height: 12),

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
