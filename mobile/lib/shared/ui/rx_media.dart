import 'package:flutter/cupertino.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';

/// Current access token for authenticated media requests.
final mediaTokenProvider = FutureProvider<String?>((ref) {
  return ref.watch(tokenStoreProvider).readAccessToken();
});

String mediaUrl(String relativePath) =>
    '${ApiConfig.apiBaseUrl}${ApiConfig.apiPrefix}/media/$relativePath';

/// Network image from `/media/...` with the bearer token attached.
class RxMediaImage extends ConsumerWidget {
  const RxMediaImage({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.placeholderIcon = CupertinoIcons.photo,
  });

  final String path;
  final BoxFit fit;
  final IconData placeholderIcon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rx = context.rx;
    final placeholder = Container(
      color: rx.fill,
      alignment: Alignment.center,
      child: Icon(placeholderIcon, color: rx.tertiaryLabel, size: 28),
    );
    final token = ref.watch(mediaTokenProvider).valueOrNull;
    if (token == null) return placeholder;
    return Image.network(
      mediaUrl(path),
      fit: fit,
      headers: {'Authorization': 'Bearer $token'},
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, sync) {
        if (sync || frame != null) return child;
        return placeholder;
      },
      errorBuilder: (_, __, ___) => placeholder,
    );
  }
}

/// Circular avatar: photo when available, otherwise coloured initials.
class RxAvatar extends StatelessWidget {
  const RxAvatar({
    super.key,
    required this.name,
    this.avatarPath,
    this.size = 40,
  });

  final String name;
  final String? avatarPath;
  final double size;

  static const _palette = [
    Color(0xFFFF6B6B),
    Color(0xFFFF9F0A),
    Color(0xFF30D158),
    Color(0xFF40C8E0),
    Color(0xFF0A84FF),
    Color(0xFF5E5CE6),
    Color(0xFFBF5AF2),
    Color(0xFFFF375F),
  ];

  String get _initials {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final color = _palette[name.hashCode.abs() % _palette.length];
    final initials = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withOpacity(0.85), color],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        _initials,
        style: TextStyle(
          color: const Color(0xFFFFFFFF),
          fontSize: size * 0.38,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    return Semantics(
      label: '$name avatar',
      image: true,
      child: SizedBox(
        width: size,
        height: size,
        child: avatarPath == null || avatarPath!.isEmpty
            ? initials
            : ClipOval(child: RxMediaImage(path: avatarPath!)),
      ),
    );
  }
}

/// OpenStreetMap tiles, inverted for dark mode.
class RxTileLayer extends StatelessWidget {
  const RxTileLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = context.rx.isDark;
    return TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.ridex.ridex',
      maxNativeZoom: 19,
      tileBuilder: dark
          ? (context, tileWidget, tile) => ColorFiltered(
                colorFilter: const ColorFilter.matrix([
                  -0.9, 0, 0, 0, 235, //
                  0, -0.9, 0, 0, 235, //
                  0, 0, -0.9, 0, 235, //
                  0, 0, 0, 1, 0,
                ]),
                child: tileWidget,
              )
          : null,
    );
  }
}

/// Required OSM attribution, styled as a small iOS caption.
class RxMapAttribution extends StatelessWidget {
  const RxMapAttribution({super.key});

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return Align(
      alignment: Alignment.bottomLeft,
      child: Container(
        margin: const EdgeInsets.all(6),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: rx.card.withOpacity(0.75),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text('© OpenStreetMap', style: rx.caption2),
      ),
    );
  }
}

/// Floating translucent circular map control (recenter, close…).
class RxMapButton extends StatelessWidget {
  const RxMapButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String semanticLabel;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minSize: 44,
        onPressed: onPressed,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: rx.cardElevated.withOpacity(0.94),
            shape: BoxShape.circle,
            boxShadow: const [
              BoxShadow(
                  color: Color(0x29000000),
                  blurRadius: 12,
                  offset: Offset(0, 4)),
            ],
          ),
          child: Icon(icon,
              size: 20, color: active ? rx.accent : rx.label),
        ),
      ),
    );
  }
}
