import 'package:flutter/material.dart';

import '../theme.dart';
import 'preferences_service.dart';

class AccountAccessService {
  static Future<bool> requireAccount(
    BuildContext context, {
    required String featureLabel,
    String? message,
  }) async {
    final isAuthenticated = await PreferencesService.isAuthenticated();
    if (isAuthenticated) {
      return true;
    }

    if (!context.mounted) {
      return false;
    }

    final shouldOpenAuth =
        await showDialog<bool>(
          context: context,
          builder: (ctx) {
            final theme = Theme.of(ctx);
            final colors = theme.extension<AppColors>()!;

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
              backgroundColor: colors.cardBackground,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(color: colors.subtleBorder),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.lock_outline,
                            color: AppTheme.primaryColor,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Create an account to continue',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: colors.textHeadline,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      message ??
                          '$featureLabel is available when you sign in. Your entries, AI insights, and settings stay synced across devices.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: colors.textBody,
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Sign In / Create Account'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Continue in Guest Mode'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ) ??
        false;

    if (!shouldOpenAuth || !context.mounted) {
      return false;
    }

    await Navigator.pushNamed(context, '/auth');
    return false;
  }
}
