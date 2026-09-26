/// Radii, spacing and touch-target sizes from §2.3, fitted to the Figma design
/// (measured from the 2x exports in `design/figma/`).
///
/// A literal in a widget is a bug even when it looks right — it is how a design
/// system drifts. Every number a widget uses comes from here.
abstract final class Dimens {
  // Radii. Buttons and chips are pills (`StadiumBorder`), so they need no token.
  static const radiusSm = 10.0;

  /// Cards and inputs. Figma's measure ~13dp at 1x; 14 is indistinguishable.
  static const radius = 14.0;
  static const radiusLg = 18.0;

  // Spacing — a 4px scale, named by role, so "gap between a heading and its
  // section" is one decision made once.
  static const space1 = 4.0;
  static const space2 = 8.0;
  static const space3 = 12.0;
  static const space4 = 16.0;
  static const space5 = 24.0;
  static const space6 = 32.0;
  static const space7 = 48.0;
  static const space8 = 64.0;

  /// The page's side margin. The design holds content 20dp in from each edge
  /// on every screen — on the 4px grid, but not one of the steps above.
  static const gutter = 20.0;

  /// The top bar, and the bottom nav bar with its labels.
  static const topBarHeight = 64.0;
  static const navBarHeight = 80.0;

  /// Minimum interactive target (§2.5). The web standard here is 44px;
  /// Material's 48dp default satisfies it, but anything hand-sized must not
  /// fall below this.
  static const minTarget = 44.0;

  /// Border widths. A selected control reads as selected by weight as well as
  /// by colour — colour is never the only signal (§2.5).
  static const borderHairline = 1.0;
  static const borderSelected = 2.0;

  /// The grab handle on a bottom sheet.
  static const handleWidth = 40.0;
  static const handleHeight = 4.0;
  static const handleRadius = 2.0;

  /// The stock meter on a material row.
  static const meterHeight = 6.0;
  static const meterRadius = 3.0;

  /// Standard height for a primary control and an input: the design's 55dp,
  /// comfortably above [minTarget].
  static const controlHeight = 55.0;

  /// Arabic needs more leading than the Material default (§2.4). Latin text
  /// takes the design's tighter leading instead — see `AppTheme.forLocale`.
  static const lineHeight = 1.7;

  /// The spinner a button shows in place of its label while it works.
  static const spinnerSize = 20.0;
  static const spinnerStroke = 2.4;

  /// A small leading icon, as on a banner.
  static const iconSm = 20.0;

  /// The smallest icon: a mark inside a line of small text.
  static const iconMicro = 14.0;

  /// A feature glyph heading a sheet.
  static const iconFeature = 40.0;

  /// Item pictures: a material's thumbnail, a Review line, a menu row, and
  /// the Drink Details hero.
  static const imageThumb = 44.0;
  static const imageReview = 56.0;
  static const imageMenu = 64.0;
  static const imageHero = 160.0;

  /// An icon inline with small label text: a clock, a note, a pin.
  static const iconInline = 16.0;

  /// A chip's least height: a label, not a control.
  static const chipMinHeight = 30.0;

  /// A trailing chevron on a row.
  static const iconXs = 18.0;

  /// The dot marking an unread notification.
  static const unreadDot = 8.0;

  /// The bell's unread badge: how far it sits past the glyph's corner, and
  /// its figure, smaller than any text style because it lives inside a 24dp
  /// icon.
  static const badgeOffset = 2.0;
  static const badgeText = 10.0;

  /// The most of a material card's width its balance may take before it
  /// wraps; the name has the rest.
  static const balanceMaxFraction = 0.45;

  /// The large glyph on an empty or error state, and on a first-launch slide.
  static const iconHero = 72.0;
  static const iconSlide = 96.0;

  /// The brand lockup's width: the splash, where it is the whole screen; the
  /// sign-in and lock screens; and a top bar or the first-launch header.
  static const lockupSplash = 250.0;
  static const lockupEntry = 160.0;
  static const lockupBar = 120.0;

  /// The most of the screen a stack of notices above a list may take (the
  /// staff queue's shortage, stale and self-order notices). Past it they
  /// scroll, so the list they sit above is never squeezed out at 320dp.
  static const noticeAreaMaxFraction = 0.4;
}
