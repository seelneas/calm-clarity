import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../services/preferences_service.dart';
import '../services/auth_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();
  final _signupNameController = TextEditingController();
  final _signupEmailController = TextEditingController();
  final _signupPasswordController = TextEditingController();
  final _signupConfirmController = TextEditingController();
  bool _loginObscure = true;
  bool _signupObscure = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _signupNameController.dispose();
    _signupEmailController.dispose();
    _signupPasswordController.dispose();
    _signupConfirmController.dispose();
    super.dispose();
  }

  Future<void> _continueWithoutAccount() async {
    await PreferencesService.setOnboardingShowed();
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  Future<void> _handleLogin() async {
    final email = _loginEmailController.text.trim();
    final password = _loginPasswordController.text.trim();
    if (email.isEmpty || password.isEmpty) {
      _showFeedback('Please fill in all fields', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    final result = await AuthService.login(email, password);
    if (mounted) setState(() => _isLoading = false);

    if (result['success']) {
      await PreferencesService.setOnboardingShowed();
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/home');
      }
    } else {
      if (mounted) {
        _showFeedback(result['message'], isError: true);
      }
    }
  }

  Future<void> _handleSignup() async {
    final name = _signupNameController.text.trim();
    final email = _signupEmailController.text.trim();
    final password = _signupPasswordController.text.trim();
    final confirm = _signupConfirmController.text.trim();

    if (name.isEmpty || email.isEmpty || password.isEmpty || confirm.isEmpty) {
      _showFeedback('Please fill in all fields', isError: true);
      return;
    }
    if (password != confirm) {
      _showFeedback('Passwords do not match', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    final result = await AuthService.signup(name, email, password);
    if (mounted) setState(() => _isLoading = false);

    if (result['success']) {
      await PreferencesService.setOnboardingShowed();
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/home');
      }
    } else {
      if (mounted) {
        _showFeedback(result['message'], isError: true);
      }
    }
  }

  Future<void> _handleSocialLogin() async {
    setState(() => _isLoading = true);

    final result = await AuthService.signInWithGoogle();

    if (mounted) setState(() => _isLoading = false);

    if (result['success']) {
      await PreferencesService.setOnboardingShowed();
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/home');
      }
    } else {
      if (mounted) {
        _showFeedback(
          result['message'] ?? 'Google Sign-In failed',
          isError: true,
        );
      }
    }
  }

  void _showFeedback(String message, {bool isError = false}) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final accent = isError ? Colors.redAccent : AppTheme.primaryColor;
    final icon = isError ? Icons.error_outline : Icons.check_circle_outline;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(icon, color: accent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: colors.textBody,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 40),
            // Logo / Branding
            Icon(Icons.spa_outlined, size: 56, color: AppTheme.primaryColor),
            const SizedBox(height: 12),
            Text(
              'Calm Clarity',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Your mindful journaling companion',
              style: TextStyle(color: Colors.blueGrey, fontSize: 14),
            ),
            const SizedBox(height: 32),

            // Tab Bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: AppTheme.primaryColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: theme.colorScheme.onPrimary,
                unselectedLabelColor: Colors.blueGrey,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(text: 'Sign In'),
                  Tab(text: 'Sign Up'),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Tab Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [_buildLoginTab(theme), _buildSignupTab(theme)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTextField(
            controller: _loginEmailController,
            label: 'Email',
            icon: Icons.email_outlined,
            theme: theme,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _loginPasswordController,
            label: 'Password',
            icon: Icons.lock_outline,
            theme: theme,
            obscure: _loginObscure,
            suffixIcon: IconButton(
              icon: Icon(
                _loginObscure ? Icons.visibility_off : Icons.visibility,
                color: Colors.blueGrey,
                size: 20,
              ),
              onPressed: () => setState(() => _loginObscure = !_loginObscure),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _showForgotPasswordDialog(context),
              child: const Text(
                'Forgot Password?',
                style: TextStyle(color: AppTheme.primaryColor, fontSize: 13),
              ),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _isLoading ? null : _handleLogin,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 54),
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: theme.colorScheme.onSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: _isLoading
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.onSurface,
                    ),
                  )
                : const Text(
                    'Sign In',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
          ),
          const SizedBox(height: 24),
          _buildSocialDivider(),
          const SizedBox(height: 20),
          _buildSocialButton(
            buttonText: 'Sign in with Google',
            icon: Icons.g_mobiledata,
          ),
          const SizedBox(height: 24),
          Center(
            child: TextButton(
              onPressed: _continueWithoutAccount,
              child: const Text(
                'Continue without an account',
                style: TextStyle(
                  color: Colors.blueGrey,
                  fontSize: 14,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSignupTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTextField(
            controller: _signupNameController,
            label: 'Full Name',
            icon: Icons.person_outline,
            theme: theme,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _signupEmailController,
            label: 'Email',
            icon: Icons.email_outlined,
            theme: theme,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _signupPasswordController,
            label: 'Password',
            icon: Icons.lock_outline,
            theme: theme,
            obscure: _signupObscure,
            suffixIcon: IconButton(
              icon: Icon(
                _signupObscure ? Icons.visibility_off : Icons.visibility,
                color: Colors.blueGrey,
                size: 20,
              ),
              onPressed: () => setState(() => _signupObscure = !_signupObscure),
            ),
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _signupConfirmController,
            label: 'Confirm Password',
            icon: Icons.lock_outline,
            theme: theme,
            obscure: true,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _isLoading ? null : _handleSignup,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 54),
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: theme.colorScheme.onSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: _isLoading
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.onSurface,
                    ),
                  )
                : const Text(
                    'Create Account',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
          ),
          const SizedBox(height: 24),
          _buildSocialDivider(),
          const SizedBox(height: 20),
          _buildSocialButton(
            buttonText: 'Sign up with Google',
            icon: Icons.g_mobiledata,
          ),
          const SizedBox(height: 24),
          Center(
            child: TextButton(
              onPressed: _continueWithoutAccount,
              child: const Text(
                'Continue without an account',
                style: TextStyle(
                  color: Colors.blueGrey,
                  fontSize: 14,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showForgotPasswordDialog(BuildContext context) {
    final emailController = TextEditingController(
      text: _loginEmailController.text,
    );
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          final dialogTheme = Theme.of(context);
          return AlertDialog(
            backgroundColor: AppTheme.cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              'Reset Password',
              style: TextStyle(
                color: dialogTheme.colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Enter your email address to receive a password reset link.',
                  style: TextStyle(color: Colors.blueGrey, fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailController,
                  style: TextStyle(color: dialogTheme.colorScheme.onSurface),
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    labelStyle: TextStyle(color: Colors.blueGrey),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.blueGrey),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: AppTheme.primaryColor),
                    ),
                  ),
                ),
                if (isSubmitting) ...[
                  const SizedBox(height: 24),
                  const CircularProgressIndicator(color: AppTheme.primaryColor),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.blueGrey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        final email = emailController.text.trim();
                        if (email.isEmpty || !email.contains('@')) {
                          _showFeedback(
                            'Please enter a valid email address',
                            isError: true,
                          );
                          return;
                        }

                        setState(() => isSubmitting = true);
                        final result = await AuthService.forgotPassword(email);
                        final resetToken = (result['reset_token'] ?? '').toString();
                        final resetLink = (result['reset_link'] ?? '').toString();
                        final delivery = (result['delivery'] ?? '').toString();

                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          _showFeedback(
                            result['message'] ??
                                'If an account exists, an email was sent.',
                            isError: !(result['success'] == true),
                          );

                          if (resetLink.isNotEmpty) {
                            await Clipboard.setData(
                              ClipboardData(text: resetLink),
                            );
                            if (!mounted || !ctx.mounted) return;
                            _showFeedback(
                              'Reset link copied to clipboard.',
                            );
                          }

                          if (result['success'] && delivery == 'dev_link') {
                            final tokenToUse = resetToken;
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: const Text(
                                  'Dev mode: use the provided token/link to set your new password.',
                                ),
                                behavior: SnackBarBehavior.floating,
                                backgroundColor: AppTheme.primaryColor,
                                action: SnackBarAction(
                                  label: 'Open Reset',
                                  textColor: Colors.white,
                                  onPressed: () {
                                    Navigator.pushNamed(
                                      this.context,
                                      '/reset-password',
                                      arguments: tokenToUse,
                                    );
                                  },
                                ),
                              ),
                            );
                          }
                        }
                      },
                child: Text(
                  'Send Reset Link',
                  style: TextStyle(color: dialogTheme.colorScheme.onPrimary),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required ThemeData theme,
    bool obscure = false,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: TextStyle(color: theme.colorScheme.onSurface),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.blueGrey, fontSize: 14),
        prefixIcon: Icon(icon, color: AppTheme.primaryColor, size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: theme.cardColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: AppTheme.primaryColor,
            width: 1.5,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
    );
  }

  Widget _buildSocialDivider() {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.blueGrey.withValues(alpha: 0.2))),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            'OR CONTINUE WITH',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.blueGrey,
              letterSpacing: 2.0,
            ),
          ),
        ),
        Expanded(child: Divider(color: Colors.blueGrey.withValues(alpha: 0.2))),
      ],
    );
  }

  Widget _buildSocialButton({
    required String buttonText,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    return OutlinedButton.icon(
      onPressed: _isLoading ? null : _handleSocialLogin,
      icon: Icon(icon, color: theme.colorScheme.onSurface, size: 24),
      label: Text(
        buttonText,
        style: TextStyle(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 52),
        backgroundColor: theme.colorScheme.surface,
        side: BorderSide(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.12),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
