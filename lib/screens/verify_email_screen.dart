import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme.dart';

class VerifyEmailScreen extends StatefulWidget {
  final String initialToken;

  const VerifyEmailScreen({super.key, this.initialToken = ''});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  late final TextEditingController _tokenController;
  final TextEditingController _emailController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _tokenController = TextEditingController(text: widget.initialToken);
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _verifyToken() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      _showFeedback('Please enter your verification token.', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);
    final result = await AuthService.verifyEmailToken(token);
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    _showFeedback(
      (result['message'] ?? 'Verification complete').toString(),
      isError: !(result['success'] == true),
    );

    if (result['success'] == true) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/auth');
    }
  }

  Future<void> _resendEmail() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showFeedback('Enter a valid email to resend verification.', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);
    final result = await AuthService.resendEmailVerification(email);
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    _showFeedback(
      (result['message'] ?? 'Verification email sent').toString(),
      isError: !(result['success'] == true),
    );
  }

  void _showFeedback(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : AppTheme.primaryColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Verify Email')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Icon(
                Icons.mark_email_read_outlined,
                size: 56,
                color: AppTheme.primaryColor,
              ),
              const SizedBox(height: 16),
              Text(
                'Confirm your email to continue',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Paste your verification token from email, then sign in again.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.blueGrey),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _tokenController,
                decoration: const InputDecoration(
                  labelText: 'Verification token',
                  prefixIcon: Icon(Icons.vpn_key_outlined),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _isSubmitting ? null : _verifyToken,
                child: _isSubmitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Verify Email'),
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 12),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email for resend',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _isSubmitting ? null : _resendEmail,
                child: const Text('Resend Verification Email'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _isSubmitting
                    ? null
                    : () => Navigator.pushReplacementNamed(context, '/auth'),
                child: const Text('Back to Sign In'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
