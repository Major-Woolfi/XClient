import 'package:flutter/widgets.dart';

/// Шрифты, которые поставляет XClient, объявленные в его `pubspec.yaml`.
enum FontFamily {
  twEmoji('Twemoji'),
  jetBrainsMono('JetBrainsMono');

  final String value;

  const FontFamily(this.value);
}

extension FontFamilyTextStyle on TextStyle {
  TextStyle get toJetBrainsMono =>
      copyWith(fontFamily: FontFamily.jetBrainsMono.value);
}

