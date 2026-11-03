import 'package:flutter/cupertino.dart';

import '../../core/theme/app_theme.dart';

/// One metric cell: big tabular value, unit and caption label.
class RxMetric extends StatelessWidget {
  const RxMetric({
    super.key,
    required this.value,
    required this.label,
    this.unit,
    this.icon,
    this.iconColor,
    this.valueSize = 22,
    this.alignment = CrossAxisAlignment.start,
  });

  final String value;
  final String label;
  final String? unit;
  final IconData? icon;
  final Color? iconColor;
  final double valueSize;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return Semantics(
      label: '$label: $value ${unit ?? ''}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: alignment,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: iconColor ?? rx.secondaryLabel),
                const SizedBox(width: 4),
              ],
              Text(label, style: rx.footnote),
            ],
          ),
          const SizedBox(height: 2),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: value, style: rx.numeric(valueSize)),
              if (unit != null)
                TextSpan(
                  text: ' $unit',
                  style: rx.subheadline
                      .copyWith(fontWeight: FontWeight.w500),
                ),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Card holding a 2-column grid of [RxMetric]s.
class RxMetricGrid extends StatelessWidget {
  const RxMetricGrid({super.key, required this.metrics});

  final List<RxMetric> metrics;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < metrics.length; i += 2) {
      rows.add(Row(
        children: [
          Expanded(child: metrics[i]),
          const SizedBox(width: RxSpace.m),
          Expanded(
            child: i + 1 < metrics.length
                ? metrics[i + 1]
                : const SizedBox.shrink(),
          ),
        ],
      ));
      if (i + 2 < metrics.length) {
        rows.add(const SizedBox(height: RxSpace.m));
      }
    }
    return Column(children: rows);
  }
}

String formatDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

String formatDistanceMeters(double? meters) {
  if (meters == null) return '—';
  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000).toStringAsFixed(meters < 10000 ? 1 : 0)} km';
}

/// "just now", "5 min ago", "2 h ago", "3 d ago".
String relativeTime(DateTime? t) {
  if (t == null) return 'never';
  final d = DateTime.now().difference(t.toLocal());
  if (d.inSeconds < 45) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inDays < 7) return '${d.inDays} d ago';
  return '${(d.inDays / 7).floor()} w ago';
}
