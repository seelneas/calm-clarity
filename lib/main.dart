import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'theme.dart';
import 'layout/app_layout.dart';
import 'screens/onboarding_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/admin_console_screen.dart';
import 'screens/voice_recording_screen.dart';
import 'screens/entry_detail_screen.dart';
import 'screens/reset_password_screen.dart';
import 'screens/settings_screen.dart';

import 'services/preferences_service.dart';
import 'services/notification_service.dart';
import 'services/auth_service.dart';

import 'providers/journal_provider.dart';
import 'providers/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.initialize();
  final showOnboarding = await PreferencesService.shouldShowOnboarding();
  final isAuthenticated = await PreferencesService.isAuthenticated();
  if (isAuthenticated) {
    await AuthService.syncCurrentUserProfile();
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => JournalProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: CalmClarityApp(
        showOnboarding: showOnboarding,
        isAuthenticated: isAuthenticated,
      ),
    ),
  );
}

class CalmClarityApp extends StatelessWidget {
  final bool showOnboarding;
  final bool isAuthenticated;
  const CalmClarityApp({
    super.key,
    required this.showOnboarding,
    required this.isAuthenticated,
  });

  ({bool isResetRoute, String token}) _resolveWebResetRoute() {
    if (!kIsWeb) {
      return (isResetRoute: false, token: '');
    }

    final uri = Uri.base;
    final queryToken =
        uri.queryParameters['reset_token'] ??
        uri.queryParameters['token'] ??
        '';
    if (queryToken.isNotEmpty) {
      return (isResetRoute: true, token: queryToken);
    }

    if (uri.path == '/reset-password') {
      return (isResetRoute: true, token: uri.queryParameters['token'] ?? '');
    }

    final fragment = uri.fragment;
    if (fragment.isNotEmpty) {
      final normalized = fragment.startsWith('/') ? fragment : '/$fragment';
      final fragmentUri = Uri.parse(normalized);
      final fragmentToken =
          fragmentUri.queryParameters['reset_token'] ??
          fragmentUri.queryParameters['token'] ??
          '';
      if (fragmentToken.isNotEmpty) {
        return (isResetRoute: true, token: fragmentToken);
      }
      if (fragmentUri.path == '/reset-password') {
        return (
          isResetRoute: true,
          token: fragmentUri.queryParameters['token'] ?? '',
        );
      }
    }

    return (isResetRoute: false, token: '');
  }

  @override
  Widget build(BuildContext context) {
    final launchReset = _resolveWebResetRoute();
    final initial = launchReset.isResetRoute
        ? '/reset-password'
        : (isAuthenticated ? '/home' : '/onboarding');

    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          title: 'Calm Clarity',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.getDarkTheme(themeProvider.fontScale),
          darkTheme: AppTheme.getDarkTheme(themeProvider.fontScale),
          themeMode: ThemeMode.dark,
          initialRoute: initial,
          routes: {
            '/onboarding': (context) => const OnboardingScreen(),
            '/auth': (context) => const AuthScreen(),
            '/home': (context) => const AppLayout(),
            '/voice_recording': (context) => const VoiceRecordingScreen(),
            '/settings': (context) => const SettingsScreen(),
            '/admin': (context) => const AdminConsoleScreen(),
          },
          onGenerateRoute: (settings) {
            if (settings.name == '/entry_detail') {
              final entryId = settings.arguments as String;
              return MaterialPageRoute(
                builder: (_) => EntryDetailScreen(entryId: entryId),
              );
            }
            if ((settings.name ?? '').startsWith('/reset-password')) {
              final routeUri = Uri.parse(settings.name ?? '/reset-password');
              final tokenFromRoute = routeUri.queryParameters['token'] ?? '';
              final args = settings.arguments;
              final initialToken = args is String && args.isNotEmpty
                  ? args
                  : (tokenFromRoute.isNotEmpty
                        ? tokenFromRoute
                        : launchReset.token);
              return MaterialPageRoute(
                builder: (_) => ResetPasswordScreen(initialToken: initialToken),
              );
            }
            return null;
          },
        );
      },
    );
  }
}
