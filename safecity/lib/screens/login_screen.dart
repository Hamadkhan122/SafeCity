import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'home_screen.dart';
import 'signup_screen.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final AuthService _authService = AuthService();

  final _formKey = GlobalKey<FormState>();

  final TextEditingController emailController = TextEditingController();

  final TextEditingController passwordController = TextEditingController();

  bool obscurePassword = true;
  bool rememberMe = false;
  bool isLoading = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  InputDecoration fieldDecoration({
    required String label,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        color: Color(0xff0A2E73),
        fontWeight: FontWeight.w600,
      ),
      filled: true,
      fillColor: Colors.white,
      prefixIcon: Icon(icon, color: const Color(0xff0A2E73)),
      suffixIcon: suffix,
      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xff66BB6A), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Colors.red, width: 2),
      ),
    );
  }

  Future<void> _showForgotPasswordDialog() async {
    final resetEmailController = TextEditingController(
      text: emailController.text.trim(),
    );
    bool sending = false;
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text("Reset Password"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Enter your account email. We'll send you a link to reset your password.",
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: resetEmailController,
                    keyboardType: TextInputType.emailAddress,
                    enabled: !sending,
                    decoration: InputDecoration(
                      labelText: "Email Address",
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      errorText: errorText,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: sending
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xff66BB6A),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: sending
                      ? null
                      : () async {
                          final email = resetEmailController.text.trim();

                          if (email.isEmpty ||
                              !RegExp(
                                r'^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$',
                              ).hasMatch(email)) {
                            setDialogState(
                              () => errorText = "Enter a valid email",
                            );
                            return;
                          }

                          setDialogState(() {
                            sending = true;
                            errorText = null;
                          });

                          final error = await _authService.resetPassword(email);

                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext);

                          if (!context.mounted) return;

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: error == null
                                  ? Colors.green
                                  : Colors.red,
                              content: Text(
                                error ??
                                    "Password reset link sent to $email. Check your inbox.",
                              ),
                            ),
                          );
                        },
                  child: sending
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text("Send Link"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xff071B52), Color(0xff0A2E73)],
              ),
            ),
          ),

          // Background map image
          Positioned.fill(
            child: Opacity(
              opacity: 0.10,
              child: Image.asset("assets/pakistan_map.png", fit: BoxFit.cover),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    const SizedBox(height: 25),

                    Hero(
                      tag: "logo",
                      child: Image.asset("assets/logo.png", height: 110),
                    ),

                    const SizedBox(height: 18),

                    const Text(
                      "Welcome Back",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),

                    const SizedBox(height: 8),

                    const Text(
                      "Login to continue using SafeCity",
                      style: TextStyle(color: Colors.white70, fontSize: 15),
                    ),

                    const SizedBox(height: 35),

                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Column(
                        children: [
                          // Email field
                          TextFormField(
                            controller: emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: fieldDecoration(
                              label: "Email Address",
                              icon: Icons.email_outlined,
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return "Please enter your email";
                              }
                              if (!RegExp(
                                r'^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$',
                              ).hasMatch(value.trim())) {
                                return "Enter a valid email";
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 20),

                          // Password field
                          TextFormField(
                            controller: passwordController,
                            obscureText: obscurePassword,
                            decoration: fieldDecoration(
                              label: "Password",
                              icon: Icons.lock_outline,
                              suffix: IconButton(
                                icon: Icon(
                                  obscurePassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: const Color(0xff0A2E73),
                                ),
                                onPressed: () {
                                  setState(() {
                                    obscurePassword = !obscurePassword;
                                  });
                                },
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return "Please enter password";
                              }
                              if (value.length < 6) {
                                return "Password must be at least 6 characters";
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 18),

                          // Remember me + Forgot password
                          Row(
                            children: [
                              Transform.scale(
                                scale: 0.95,
                                child: Checkbox(
                                  value: rememberMe,
                                  activeColor: const Color(0xff66BB6A),
                                  onChanged: (value) {
                                    setState(() {
                                      rememberMe = value!;
                                    });
                                  },
                                ),
                              ),
                              const Text(
                                "Remember Me",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: _showForgotPasswordDialog,
                                child: const Text(
                                  "Forgot Password?",
                                  style: TextStyle(
                                    color: Color(0xff66BB6A),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 20),

                          // Login button
                          SizedBox(
                            width: double.infinity,
                            height: 58,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xff66BB6A),
                                foregroundColor: Colors.white,
                                elevation: 8,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              onPressed: () async {
                                if (!_formKey.currentState!.validate()) {
                                  return;
                                }

                                setState(() {
                                  isLoading = true;
                                });

                                try {
                                  await _auth.signInWithEmailAndPassword(
                                    email: emailController.text.trim(),
                                    password: passwordController.text.trim(),
                                  );

                                  if (!context.mounted) return;

                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const HomeScreen(),
                                    ),
                                  );
                                } on FirebaseAuthException catch (e) {
                                  String message = "";

                                  switch (e.code) {
                                    case "user-not-found":
                                      message =
                                          "No account found with this email.";
                                      break;
                                    case "wrong-password":
                                      message = "Incorrect password.";
                                      break;
                                    case "invalid-email":
                                      message = "Invalid email address.";
                                      break;
                                    case "invalid-credential":
                                      message =
                                          "Email or password is incorrect.";
                                      break;
                                    case "too-many-requests":
                                      message =
                                          "Too many attempts. Try again later.";
                                      break;
                                    default:
                                      message = e.message ?? "Login failed.";
                                  }

                                  if (!context.mounted) return;

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      backgroundColor: Colors.red,
                                      content: Text(message),
                                    ),
                                  );
                                } catch (e) {
                                  if (!context.mounted) return;

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      backgroundColor: Colors.red,
                                      content: Text(e.toString()),
                                    ),
                                  );
                                } finally {
                                  if (mounted) {
                                    setState(() {
                                      isLoading = false;
                                    });
                                  }
                                }
                              },
                              child: isLoading
                                  ? const SizedBox(
                                      height: 25,
                                      width: 25,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 3,
                                      ),
                                    )
                                  : const Text(
                                      "LOGIN",
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1,
                                      ),
                                    ),
                            ),
                          ),

                          const SizedBox(height: 25),

                          // Sign up row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                "Don't have an account?",
                                style: TextStyle(color: Colors.white70),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const SignupScreen(),
                                    ),
                                  );
                                },
                                child: const Text(
                                  "Create Account",
                                  style: TextStyle(
                                    color: Color(0xff66BB6A),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 15),

                          const Text(
                            "Secure • Smart • Connected",
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                              letterSpacing: 1,
                            ),
                          ),

                          const SizedBox(height: 35),

                          const Divider(color: Colors.white24, thickness: .8),

                          const SizedBox(height: 15),

                          const Text(
                            "Powered by Firebase",
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                          ),

                          const SizedBox(height: 8),

                          const Text(
                            "SafeCity © 2026",
                            style: TextStyle(color: Colors.white38),
                          ),

                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
