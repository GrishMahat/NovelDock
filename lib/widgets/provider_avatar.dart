import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/models.dart';
import '../core/providers/registry.dart';

/// Provider avatar with icon from the registry (platform-aware), falling back
/// to a letter avatar when no icon is cached.
class ProviderAvatar extends ConsumerWidget {
  final ProviderMeta provider;
  final double radius;

  const ProviderAvatar({super.key, required this.provider, this.radius = 20});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registryAsync = ref.watch(registryManagerProvider);

    return registryAsync.when(
      loading: () => _letterAvatar(),
      error: (_, _) => _letterAvatar(),
      data: (registry) {
        final iconFile = registry.loadCachedProviderIcon(provider.id);
        if (iconFile != null) {
          return CircleAvatar(
            radius: radius,
            backgroundImage: FileImage(iconFile),
            backgroundColor: Colors.transparent,
            onBackgroundImageError: (_, _) {},
          );
        }
        return _letterAvatar();
      },
    );
  }

  Widget _letterAvatar() {
    final color = Color(
      provider.name.hashCode.toUnsigned(32) | 0xFF000000,
    ).withValues(alpha: 0.7);

    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: 0.2),
      child: Text(
        provider.name.isNotEmpty ? provider.name[0].toUpperCase() : '?',
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }
}
