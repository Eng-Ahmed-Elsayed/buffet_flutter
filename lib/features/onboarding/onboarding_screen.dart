import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/widgets/brand_backdrop.dart';
import '../../shared/widgets/brand_lockup.dart';
import '../../shared/widgets/exit_confirmation.dart';
import '../../theme/brand_colors.dart';
import '../../theme/dimens.dart';
import '../../theme/motion.dart';
import 'onboarding_controller.dart';

/// The first-launch explainer: three slides on how the service works, shown
/// once per install before the first sign-in (D3 in `docs/figma-redesign.md`).
///
/// The design's layout — hero card, page dots, Next, Sign in, Skip — with the
/// design's coffee slogans replaced by what a new user actually needs to know,
/// and no stock photography. Skip, Sign in and the last slide's primary
/// button all end it the same way; the router then moves to sign-in.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _finish() =>
      unawaited(ref.read(onboardingControllerProvider.notifier).markSeen());

  void _next(int count) {
    if (_index >= count - 1) {
      _finish();
      return;
    }
    unawaited(
      _pages.nextPage(
        duration: Motion.of(context, Motion.slow),
        curve: Motion.easeOut,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final slides = [
      (
        Icons.local_cafe_outlined,
        l10n.onboardingOrderTitle,
        l10n.onboardingOrderBody,
      ),
      (
        Icons.notifications_active_outlined,
        l10n.onboardingReadyTitle,
        l10n.onboardingReadyBody,
      ),
      (
        Icons.inventory_2_outlined,
        l10n.onboardingOwnTitle,
        l10n.onboardingOwnBody,
      ),
    ];
    final last = _index == slides.length - 1;

    return ExitConfirmation(
      // Nothing sits beneath it: back would close the app on a first launch.
      child: Scaffold(
        body: BrandBackdrop(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: Dimens.gutter,
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const BrandLockup(width: 120),
                      const Spacer(),
                      // Ink, not the link blue: this row sits on the glow, where
                      // the link blue drops to about 4:1. Ink holds 6.5:1 even
                      // at the glow's peak.
                      TextButton(
                        onPressed: _finish,
                        style: TextButton.styleFrom(
                          foregroundColor: BrandColors.ink,
                        ),
                        child: Text(l10n.onboardingSkip),
                      ),
                    ],
                  ),
                  const SizedBox(height: Dimens.space4),
                  Expanded(
                    child: PageView.builder(
                      controller: _pages,
                      itemCount: slides.length,
                      onPageChanged: (i) => setState(() => _index = i),
                      itemBuilder: (context, i) => _Slide(
                        icon: slides[i].$1,
                        title: slides[i].$2,
                        body: slides[i].$3,
                      ),
                    ),
                  ),
                  const SizedBox(height: Dimens.space5),
                  _Dots(count: slides.length, index: _index),
                  const SizedBox(height: Dimens.space5),
                  FilledButton(
                    onPressed: () => _next(slides.length),
                    child: Text(last ? l10n.signIn : l10n.onboardingNext),
                  ),
                  // On the last slide the primary button already signs in;
                  // a second "Sign in" beneath it would be the same action
                  // twice.
                  if (!last) ...[
                    const SizedBox(height: Dimens.space3),
                    OutlinedButton(
                      onPressed: _finish,
                      child: Text(l10n.signIn),
                    ),
                  ],
                  const SizedBox(height: Dimens.space4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One slide: the design's hero card, with the brand gradient in place of a
/// photograph. White text holds 8.21:1 on [BrandColors.brand] and 6.11:1 on
/// [BrandColors.brandSecondary], the two ends of the gradient.
class _Slide extends StatelessWidget {
  const _Slide({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Dimens.radiusLg),
        gradient: const LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [BrandColors.brandSecondary, BrandColors.brand],
        ),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(Dimens.space5),
        // Scrolls rather than overflowing when a large text scale makes the
        // copy taller than the card.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      top: Dimens.space4,
                    ),
                    child: Icon(icon, size: 96, color: BrandColors.surface),
                  ),
                  const SizedBox(height: Dimens.space5),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: text.headlineMedium?.copyWith(
                          color: BrandColors.surface,
                        ),
                      ),
                      const SizedBox(height: Dimens.space2),
                      Text(
                        body,
                        style: text.bodyLarge?.copyWith(
                          color: BrandColors.surface,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The page dots: the current slide is a wide pill in the primary blue, the
/// others small dots in the icon blue (non-text UI, 3.88:1 on the page).
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Semantics(
      label: l10n.onboardingPage(index + 1, count),
      child: ExcludeSemantics(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < count; i++)
              AnimatedContainer(
                duration: Motion.of(context, Motion.base),
                curve: Motion.easeSoft,
                margin: const EdgeInsetsDirectional.symmetric(
                  horizontal: Dimens.space1,
                ),
                width: i == index ? Dimens.space5 : Dimens.space2,
                height: Dimens.space2,
                decoration: BoxDecoration(
                  color: i == index ? BrandColors.brand : BrandColors.iconBlue,
                  borderRadius: BorderRadius.circular(Dimens.space1),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
