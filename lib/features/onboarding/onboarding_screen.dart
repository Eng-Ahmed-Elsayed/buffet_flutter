import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/widgets/brand_backdrop.dart';
import '../../shared/widgets/brand_lockup.dart';
import '../../shared/widgets/exit_confirmation.dart';
import '../../shared/widgets/language_toggle.dart';
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
    // Each photograph with the part of it the portrait card keeps: the cup
    // sits right of centre in the first two.
    final slides = [
      (
        'assets/images/onboarding/order.jpg',
        const Alignment(0.3, 0),
        l10n.onboardingOrderTitle,
        l10n.onboardingOrderBody,
      ),
      (
        'assets/images/onboarding/ready.jpg',
        const Alignment(-0.05, 0),
        l10n.onboardingReadyTitle,
        l10n.onboardingReadyBody,
      ),
      (
        'assets/images/onboarding/own.jpg',
        const Alignment(0.2, -0.3),
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
                      const BrandLockup(width: Dimens.lockupBar),
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
                        image: slides[i].$1,
                        focus: slides[i].$2,
                        title: slides[i].$3,
                        body: slides[i].$4,
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
                  // twice. It is hidden but keeps its space, so the photograph
                  // stays the same size on every slide rather than growing
                  // into the gap. Hidden, it is neither tappable nor read out.
                  const SizedBox(height: Dimens.space3),
                  Visibility(
                    visible: !last,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: OutlinedButton(
                      onPressed: _finish,
                      child: Text(l10n.signIn),
                    ),
                  ),
                  // The app opens in Arabic whatever the device language, and
                  // this is the first screen anyone sees: without the switch
                  // here, someone who cannot read Arabic met three slides they
                  // could not read before reaching the one on sign-in.
                  const SizedBox(height: Dimens.space3),
                  const LanguageToggle(),
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

/// One slide, as the design draws it: a photograph filling the card, the
/// title and text over its foot on a fade, so white text reads over any
/// picture (white on [BrandColors.photoScrim] holds 8.4:1 at worst). Real,
/// licensed photographs, never generated ones (D3).
class _Slide extends StatelessWidget {
  const _Slide({
    required this.image,
    required this.focus,
    required this.title,
    required this.body,
  });

  /// An asset under assets/images/onboarding/.
  final String image;

  /// Which part of the photograph the card keeps when it crops it. An
  /// `Alignment`, not a directional one, deliberately: a photograph is not
  /// mirrored in Arabic, so the cup stays where the camera put it.
  final Alignment focus;

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(Dimens.radiusLg),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Decorative: the title and text say what the slide is about.
          Image.asset(
            image,
            fit: BoxFit.cover,
            alignment: focus,
            excludeFromSemantics: true,
          ),
          // Scrolls rather than overflowing when a large text scale makes the
          // copy taller than the card; the fade grows with it.
          LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // A fixed band that fades the photograph in, then a solid
                    // box under every line of text: the text never sits on
                    // anything see-through, however tall a large text scale
                    // makes it.
                    SizedBox(
                      height: Dimens.space8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              BrandColors.photoScrim.withAlpha(0),
                              BrandColors.photoScrim,
                            ],
                          ),
                        ),
                      ),
                    ),
                    ColoredBox(
                      color: BrandColors.photoScrim,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          Dimens.space5,
                          0,
                          Dimens.space5,
                          Dimens.space5,
                        ),
                        child: Column(
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
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
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
