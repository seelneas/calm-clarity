import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/preferences_service.dart';
import '../services/auth_service.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isLoading = false;

  final List<OnboardingData> _pages = [
    OnboardingData(
      title: 'Talk freely – we’ll make sense of it.',
      description:
          'Your personal AI journal that turns rambling thoughts into clear insights.',
      icon: Icons.record_voice_over,
    ),
    OnboardingData(
      title: 'Clear Insights, No Rambling.',
      description:
          'Our AI extracts key takeaways and action items from your voice notes automatically.',
      icon: Icons.insights,
    ),
    OnboardingData(
      title: 'Your Calmest Self starts here.',
      description:
          'Track your mood patterns and build a clearer mind, one session at a time.',
      icon: Icons.auto_awesome,
    ),
  ];

  Future<void> _completeOnboarding() async {
    await PreferencesService.setOnboardingShowed();
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/auth');
    }
  }

  Future<void> _skipToHome() async {
    await PreferencesService.setOnboardingShowed();
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/home');
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
        final errorType = (result['error_type'] ?? '').toString().toLowerCase();
        final message = (result['message'] ?? 'Google Sign-In failed').toString();
        final mappedMessage = switch (errorType) {
          'email_verification_required' => 'Please verify your email before signing in.',
          'account_suspended' => 'Your account is suspended. Contact support for reactivation.',
          'account_locked' => 'Too many attempts. Try again shortly, then retry sign-in.',
          _ => message,
        };
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(mappedMessage),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Top Skip Button
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextButton(
                  onPressed: _completeOnboarding,
                  child: const Text(
                    'Skip',
                    style: TextStyle(
                      color: Colors.blueGrey,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),

            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (int page) {
                  setState(() {
                    _currentPage = page;
                  });
                },
                itemBuilder: (context, index) {
                  return SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 32),
                          // Illustration Placeholder
                          Container(
                            width: 180,
                            height: 180,
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withValues(
                                alpha: 0.05,
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Icon(
                                _pages[index].icon,
                                size: 100,
                                color: AppTheme.primaryColor.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          Text(
                            _pages[index].title,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _pages[index].description,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.blueGrey,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // Pagination Indicators
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _pages.length,
                (index) => _buildDot(index == _currentPage),
              ),
            ),

            const SizedBox(height: 32),

            // Bottom Action Area
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 16.0,
              ),
              child: Column(
                children: [
                  ElevatedButton(
                    onPressed: () {
                      if (_currentPage == _pages.length - 1) {
                        _completeOnboarding();
                      } else {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 56),
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: theme.colorScheme.onSurface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
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
                        : Text(
                            _currentPage == _pages.length - 1
                                ? 'Get Started'
                                : 'Next',
                          ),
                  ),
                  if (_currentPage == _pages.length - 1) ...[
                    const SizedBox(height: 16),
                    _buildSocialDivider(),
                    const SizedBox(height: 16),
                    _buildSocialButton(
                      context,
                      'Continue with Google',
                      Icons.g_mobiledata,
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _skipToHome,
                    child: const Text(
                      'Try without an account',
                      style: TextStyle(
                        color: Colors.blueGrey,
                        fontSize: 14,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDot(bool isActive) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: isActive ? 24 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: isActive
            ? AppTheme.primaryColor
            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(4),
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
            'OR SIGN IN WITH',
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

  Widget _buildSocialButton(BuildContext context, String label, IconData icon) {
    final theme = Theme.of(context);
    return OutlinedButton.icon(
      onPressed: _isLoading ? null : _handleSocialLogin,
      icon: Icon(icon, color: theme.colorScheme.onSurface, size: 24),
      label: Text(
        label,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

class OnboardingData {
  final String title;
  final String description;
  final IconData icon;

  OnboardingData({
    required this.title,
    required this.description,
    required this.icon,
  });
}
