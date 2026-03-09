import 'package:flutter/material.dart';

import '../services/preferences_service.dart';
import '../theme.dart';

class GuestModeBanner extends StatelessWidget {
  final String? subtitle;

  const GuestModeBanner({super.key, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: PreferencesService.isAuthenticated(),
      builder: (context, snapshot) {
        if (snapshot.data == true) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        final colors = theme.extension<AppColors>()!;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppTheme.primaryColor.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.person_outline,
                color: AppTheme.primaryColor,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Guest Mode',
                      style: TextStyle(
                        color: colors.textHeadline,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle ??
                          'Create an account to sync history and unlock account-only features.',
                      style: TextStyle(
                        color: colors.textBody,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => Navigator.pushNamed(context, '/auth'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Create Account'),
              ),
            ],
          ),
        );
      },
    );
  }
}
