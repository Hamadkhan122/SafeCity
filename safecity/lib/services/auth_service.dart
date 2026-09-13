import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  Future<String?> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return null;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case "user-not-found":
          return "No account found with this email.";
        case "invalid-email":
          return "Invalid email address.";
        case "too-many-requests":
          return "Too many attempts. Please try again later.";
        default:
          return e.message ?? "Couldn't send reset email.";
      }
    } catch (e) {
      return e.toString();
    }
  }
}