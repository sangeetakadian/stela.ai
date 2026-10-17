import 'package:firebase_auth/firebase_auth.dart';

Future<Map<String, String>> codeExecutionHeaders() async {
  final auth = FirebaseAuth.instance;
  final user = auth.currentUser ?? await auth.authStateChanges().first;
  if (user == null) {
    throw StateError('Sign in before running code.');
  }

  final token = await user.getIdToken();
  if (token == null || token.isEmpty) {
    throw StateError('Could not verify your sign-in. Please sign in again.');
  }

  return {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };
}
