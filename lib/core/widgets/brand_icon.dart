import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../ai/brand_resolver.dart';
import '../ai/model_catalog.dart';

/// Brand logo + tiny provider badge at bottom-right, with a monogram
/// fallback when the brand isn't in assets/logos/ (never a wrong logo).
class BrandIcon extends StatelessWidget {
  const BrandIcon({
    super.key,
    required this.model,
    this.size = 24,
    this.showBadge = true,
  });

  final ModelSpec model;
  final double size;
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand =
        model.brand ?? BrandResolver.fromModel(model.id, model.provider);
    final providerBrand = BrandResolver.forProvider(model.provider);
    return SizedBox.square(
      dimension: size,
      child: Stack(children: [
        Positioned.fill(
          child: brand == null
              ? _Monogram(
                  letter: model.displayName.isNotEmpty
                      ? model.displayName[0].toUpperCase()
                      : '?',
                  tint: theme.colorScheme.onSurfaceVariant)
              : SvgPicture.asset(
                  'assets/logos/$brand.svg',
                  // Official-color brands render as-is; monochrome marks get
                  // tinted to the theme's primary text color.
                  colorFilter: _colored(brand)
                      ? null
                      : ColorFilter.mode(
                          theme.colorScheme.onSurface, BlendMode.srcIn),
                  placeholderBuilder: (_) => _Monogram(
                      letter: model.displayName[0].toUpperCase(),
                      tint: theme.colorScheme.onSurfaceVariant),
                ),
        ),
        if (showBadge)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: size * 0.45,
              height: size * 0.45,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.surface,
                border: Border.all(
                    color: theme.colorScheme.outline, width: 0.5),
              ),
              clipBehavior: Clip.antiAlias,
              child: SvgPicture.asset(
                'assets/logos/$providerBrand.svg',
                colorFilter: ColorFilter.mode(
                    theme.colorScheme.onSurface, BlendMode.srcIn),
              ),
            ),
          ),
      ]),
    );
  }

  static bool _colored(String brand) =>
      const {'nvidia', 'groq'}.contains(brand);
}

/// Circular monogram — the honest fallback for an unknown brand.
class _Monogram extends StatelessWidget {
  const _Monogram({required this.letter, required this.tint});
  final String letter;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: tint.withValues(alpha: 0.15),
      ),
      alignment: Alignment.center,
      child: Text(letter,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: tint)),
    );
  }
}
