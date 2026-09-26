import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/dimens.dart';

/// How a row of tab labels fits a fixed tab bar [width] wide.
///
/// A fixed [TabBar] gives each tab an equal share and a 46dp height, and fades
/// whatever does not fit: at a large text scale a label was cut off mid-word
/// sideways, and clipped top and bottom, with nothing to say so. `fit` is
/// false when the labels will not sit side by side (the bar should then
/// scroll, so every label is read whole); `height` is a tab tall enough for
/// the label at the current text scale.
({bool fit, double height}) measureTabLabels(
  BuildContext context,
  List<String> labels,
  double width,
) {
  final style =
      TabBarTheme.of(context).labelStyle ??
      Theme.of(context).textTheme.titleSmall;
  final share = width / labels.length - kTabLabelPadding.horizontal;
  var fit = true;
  var tallest = 0.0;
  for (final label in labels) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    if (painter.width > share) fit = false;
    tallest = math.max(tallest, painter.height);
    painter.dispose();
  }
  return (
    fit: fit,
    height: math.max(kTextTabBarHeight, tallest + Dimens.space3 * 2),
  );
}
