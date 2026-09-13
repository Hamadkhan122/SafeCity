import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'home_screen.dart';
import 'login_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  // Firebase
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Form
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Controllers
  final TextEditingController fullNameController = TextEditingController();

  final TextEditingController emailController = TextEditingController();

  final TextEditingController phoneController = TextEditingController();

  final TextEditingController passwordController = TextEditingController();

  final TextEditingController confirmPasswordController =
      TextEditingController();

  bool obscurePassword = true;
  bool obscureConfirmPassword = true;

  bool agreeTerms = false;

  bool isLoading = false;

  double passwordStrength = 0;

  String strengthText = "";

  Color strengthColor = Colors.red;

  @override
  void dispose() {
    fullNameController.dispose();

    emailController.dispose();

    phoneController.dispose();

    passwordController.dispose();

    confirmPasswordController.dispose();

    super.dispose();
  }

  // Password Strength
  void checkPassword(String password) {
    if (password.isEmpty) {
      setState(() {
        passwordStrength = 0;

        strengthText = "";
      });

      return;
    }

    if (password.length < 6) {
      setState(() {
        passwordStrength = .25;

        strengthText = "Weak Password";

        strengthColor = Colors.red;
      });
    } else if (password.length < 8) {
      setState(() {
        passwordStrength = .50;

        strengthText = "Medium Password";

        strengthColor = Colors.orange;
      });
    } else if (!password.contains(RegExp(r'[A-Z]'))) {
      setState(() {
        passwordStrength = .75;

        strengthText = "Good Password";

        strengthColor = Colors.amber;
      });
    } else {
      setState(() {
        passwordStrength = 1;

        strengthText = "Strong Password";

        strengthColor = Colors.green;
      });
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,

      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,

                end: Alignment.bottomCenter,

                colors: [Color(0xff071B52), Color(0xff0A2E73)],
              ),
            ),
          ),

          Positioned.fill(
            child: Opacity(
              opacity: .10,

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
                    const SizedBox(height: 20),

                    Hero(
                      tag: "logo",

                      child: Image.asset("assets/logo.png", height: 110),
                    ),

                    const SizedBox(height: 18),

                    const Text(
                      "Create Account",

                      style: TextStyle(
                        color: Colors.white,

                        fontSize: 34,

                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 8),

                    const Text(
                      "Join SafeCity and build safer communities.",

                      textAlign: TextAlign.center,

                      style: TextStyle(color: Colors.white70, fontSize: 15),
                    ),

                    const SizedBox(height: 35),

                    Container(
                      padding: const EdgeInsets.all(22),

                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(.12),

                        borderRadius: BorderRadius.circular(30),

                        border: Border.all(color: Colors.white24),
                      ),

                      child: Column(
                        children: [
                          // =======================
                          // Full Name
                          // =======================
                          TextFormField(
                            controller: fullNameController,
                            textCapitalization: TextCapitalization.words,
                            decoration: fieldDecoration(
                              label: "Full Name",
                              icon: Icons.person_outline,
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return "Please enter your full name";
                              }

                              if (value.trim().length < 3) {
                                return "Name must be at least 3 characters";
                              }

                              return null;
                            },
                          ),

                          const SizedBox(height: 18),

                          // =======================
                          // Email
                          // =======================
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

                          const SizedBox(height: 18),

                          // =======================
                          // Phone Number
                          // =======================
                          TextFormField(
                            controller: phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: fieldDecoration(
                              label: "Phone Number",
                              icon: Icons.phone_outlined,
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return "Please enter phone number";
                              }

                              if (value.trim().length != 11) {
                                return "Phone number must be 11 digits";
                              }

                              return null;
                            },
                          ),

                          const SizedBox(height: 18),

                          // =======================
                          // Password
                          // =======================
                          TextFormField(
                            controller: passwordController,
                            obscureText: obscurePassword,
                            onChanged: checkPassword,
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

                              if (value.length < 8) {
                                return "Password must be at least 8 characters";
                              }

                              return null;
                            },
                          ),

                          const SizedBox(height: 10),

                          ClipRRect(
                            borderRadius: BorderRadius.circular(30),
                            child: LinearProgressIndicator(
                              value: passwordStrength,
                              minHeight: 8,
                              color: strengthColor,
                              backgroundColor: Colors.grey.shade300,
                            ),
                          ),

                          const SizedBox(height: 8),

                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              strengthText,
                              style: TextStyle(
                                color: strengthColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),

                          const SizedBox(height: 18),

                          // =======================
                          // Confirm Password
                          // =======================
                          TextFormField(
                            controller: confirmPasswordController,
                            obscureText: obscureConfirmPassword,
                            decoration: fieldDecoration(
                              label: "Confirm Password",
                              icon: Icons.lock_outline,
                              suffix: IconButton(
                                icon: Icon(
                                  obscureConfirmPassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: const Color(0xff0A2E73),
                                ),
                                onPressed: () {
                                  setState(() {
                                    obscureConfirmPassword =
                                        !obscureConfirmPassword;
                                  });
                                },
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return "Confirm your password";
                              }

                              if (value != passwordController.text) {
                                return "Passwords do not match";
                              }

                              return null;
                            },
                          ),

                          const SizedBox(height: 20),

                          // =======================
                          // Terms & Conditions
                          // =======================
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Checkbox(
                                value: agreeTerms,
                                activeColor: const Color(0xff66BB6A),
                                onChanged: (value) {
                                  setState(() {
                                    agreeTerms = value!;
                                  });
                                },
                              ),

                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: RichText(
                                    text: const TextSpan(
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                      ),
                                      children: [
                                        TextSpan(text: "I agree to the "),

                                        TextSpan(
                                          text: "Terms & Conditions",
                                          style: TextStyle(
                                            color: Color(0xff66BB6A),
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),

                                        TextSpan(text: " and Privacy Policy"),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 25),
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

                                if (!agreeTerms) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      backgroundColor: Colors.red,
                                      content: Text(
                                        "Please accept Terms & Conditions",
                                      ),
                                    ),
                                  );
                                  return;
                                }

                                setState(() {
                                  isLoading = true;
                                });

                                try {
                                  UserCredential userCredential = await _auth
                                      .createUserWithEmailAndPassword(
                                        email: emailController.text.trim(),
                                        password: passwordController.text
                                            .trim(),
                                      );

                                  await _firestore
                                      .collection("users")
                                      .doc(userCredential.user!.uid)
                                      .set({
                                        "uid": userCredential.user!.uid,

                                        "fullName": fullNameController.text
                                            .trim(),

                                        "email": emailController.text.trim(),

                                        "phone": phoneController.text.trim(),

                                        "createdAt": Timestamp.now(),
                                      });

                                  if (!context.mounted) return;

                                  showDialog(
                                    context: context,
                                    barrierDismissible: false,
                                    builder: (_) => AlertDialog(
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      title: const Row(
                                        children: [
                                          Icon(
                                            Icons.check_circle,
                                            color: Colors.green,
                                          ),
                                          SizedBox(width: 10),
                                          Text("Success"),
                                        ],
                                      ),
                                      content: const Text(
                                        "Your account has been created successfully.",
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () {
                                            Navigator.pop(context);

                                            Navigator.pushAndRemoveUntil(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    const HomeScreen(),
                                              ),
                                              (route) => false,
                                            );
                                          },
                                          child: const Text("Continue"),
                                        ),
                                      ],
                                    ),
                                  );
                                } on FirebaseAuthException catch (e) {
                                  String message;

                                  switch (e.code) {
                                    case "email-already-in-use":
                                      message =
                                          "This email is already registered.";
                                      break;

                                    case "invalid-email":
                                      message = "Invalid email address.";
                                      break;

                                    case "weak-password":
                                      message = "Password is too weak.";
                                      break;

                                    default:
                                      message = e.message ?? "Signup failed.";
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
                                      height: 24,
                                      width: 24,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 3,
                                      ),
                                    )
                                  : const Text(
                                      "CREATE ACCOUNT",
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1,
                                      ),
                                    ),
                            ),
                          ),

                          const SizedBox(height: 25),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                "Already have an account?",
                                style: TextStyle(color: Colors.white70),
                              ),

                              TextButton(
                                onPressed: () {
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const LoginScreen(),
                                    ),
                                  );
                                },
                                child: const Text(
                                  "Login",
                                  style: TextStyle(
                                    color: Color(0xff66BB6A),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 18),

                          const Divider(color: Colors.white24),

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
