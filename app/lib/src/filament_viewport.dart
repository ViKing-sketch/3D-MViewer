import 'package:flutter/material.dart';

import 'strings.dart';

/// Placeholder for the Filament platform view.
///
/// The real renderer is described in docs/rendering.md: a Kotlin/Swift
/// Filament view behind the platform channel `fbv/filament`, fed by GLB from
/// the package and ElementId from fbv_core. This widget keeps the layout slot
/// so the shell can be tested without the native renderer.
class FilamentViewport extends StatelessWidget {
  const FilamentViewport({
    super.key,
    required this.strings,
    required this.elementCount,
    required this.selectedName,
  });

  final S strings;
  final int elementCount;
  final String? selectedName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.view_in_ar_outlined, size: 36, color: scheme.primary),
            const SizedBox(height: 8),
            Text(strings.renderStub, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            Text(
              '${strings.elements}: $elementCount',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (selectedName != null)
              Text(selectedName!, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      ),
    );
  }
}
