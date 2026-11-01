import 'package:flutter/material.dart';

/// Emerald Mint / Botanical Fresh Color Palette
/// Clean, calming, premium, natural light UI.
class AppColors {
  // 1. Primary Brand & Accent Colors
  /// Primary Accent (Brand Green): Fresh Olive Lime
  /// Used for: Primary buttons, active tabs, progress rings, checkmarks.
  static const Color primary = Color(0xFF7EAA31);

  /// Accent Glow / Bright Lime: Sprout Lime
  /// Used for: Highlights, gradients, badges.
  static const Color accentGlow = Color(0xFFA9C34A);

  /// Deep Contrast Green: Forest Olive
  /// Used for: Outlined button text, dark contrast details, headers.
  static const Color deepContrast = Color(0xFF53751F);

  /// Secondary Accent (Cyan Blue): Soft Sky Blue
  static const Color secondaryAccent = Color(0xFF58AFCB);

  // Aliases for compatibility
  static const Color primaryDark = Color(0xFF53751F);
  static const Color primaryLight = Color(0xFFA9C34A);
  static const Color primaryContainer = Color(0xFFE5F2D0); // Gentle Sprout Tint
  static const Color accent = Color(0xFF7EAA31);

  // 2. Canvas & Background Colors
  /// Solid Background Fallback: Ivory Soft White
  static const Color background = Color(0xFFF8FBF4);

  /// Surface: Clean Pure Card Surface
  static const Color surface = Color(0xFFFFFFFF);

  /// Surface Light: Subtle mint-tinted surface for inputs/cards
  static const Color surfaceLight = Color(0xFFF1F6EE);
  static const Color surfaceMuted = Color(0xFFE7EFE3);

  /// Dividers and Borders
  static const Color divider = Color(0xFFD6E3DC);
  static const Color border = Color(0xFFC7D7CE);

  // Background Gradient Stops (Top-Left to Bottom-Right)
  static const Color gradientTopLeft = Color(0xFFE1F7EF);     // Soft Mint Mist
  static const Color gradientMiddle = Color(0xFFF8FBF4);      // Ivory Soft White
  static const Color gradientBottomRight = Color(0xFFF2F6DD); // Warm Honeydew Lime

  /// Natural Botanical Canvas Linear Gradient
  static const LinearGradient canvasGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      gradientTopLeft,
      gradientMiddle,
      gradientBottomRight,
    ],
    stops: [0.0, 0.5, 1.0],
  );

  // 3. Typography & Text Colors
  /// Primary Text (Titles, Headings, Numbers): Deep Charcoal Ink (Weight: 700 to 900)
  static const Color textPrimary = Color(0xFF101413);

  /// Secondary Text (Subtitles, Descriptions, Meta Info): Slate Sage (Weight: 500)
  static const Color textSecondary = Color(0xFF6F7C78);

  /// Muted / Placeholder Text (Hints, Disabled Items, Time slots): Light Silver Pine (Weight: 500-600)
  static const Color textMuted = Color(0xFF9EABA6);

  // Status & Badges
  static const Color paid = Color(0xFF53751F);
  static const Color paidContainer = Color(0xFFE7F3D5);
  static const Color unpaid = Color(0xFFC62828);
  static const Color unpaidContainer = Color(0xFFFFEBEE);
  static const Color partial = Color(0xFFD97706);
  static const Color partialContainer = Color(0xFFFEF3C7);
  static const Color overdue = Color(0xFFB71C1C);
}
