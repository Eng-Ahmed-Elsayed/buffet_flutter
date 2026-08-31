import 'package:flutter/material.dart';

import '../../theme/brand_colors.dart';
import '../../theme/dimens.dart';

/// A label over a group of things.
///
/// Three near-identical private versions of this existed — one per screen that
/// needed to head a list. Consolidated so a section heading looks the same
/// wherever it appears.
///
/// [accent] draws the leading rule in a meaningful colour. It is the one place
/// a caller may pass [BrandColors.accent], and only for «من موادي» — the rule
/// there genuinely marks the user's own jar.
class SectionHeader extends StatelessWidget {
  const SectionHeader({required this.label, this.accent, super.key});

  final String label;

  /// Null for an ordinary heading; a colour draws a leading rule in it.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final colour = accent;
    final style = Theme.of(context).textTheme.labelLarge
        ?.copyWith(color: colour ?? BrandColors.ink);

    if (colour == null) {
      return Semantics(header: true, child: Text(label, style: style));
    }

    return Semantics(
      header: true,
      child: Row(
        children: [
          Container(
            width: Dimens.space1,
            height: Dimens.space4,
            decoration: BoxDecoration(
              color: colour,
              borderRadius: BorderRadius.circular(Dimens.radiusSm),
            ),
          ),
          const SizedBox(width: Dimens.space2),
          Text(label, style: style),
        ],
      ),
    );
  }
}
