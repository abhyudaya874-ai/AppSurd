import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/search/search_models.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/spacing.dart';
import '../../core/widgets/animated_app_icon.dart';
import '../../core/widgets/fade_slide_in.dart';

/// Collapsible research trace: "Researched Ns ⌄" header, expanded tree with
/// steps → query rows (provider tag) → source rows (favicon + breadcrumb +
/// status chip) → "+N more". Auto-collapses when the answer starts.
class ResearchTraceView extends StatefulWidget {
  const ResearchTraceView({
    super.key,
    required this.trace,
    required this.running,
  });

  final ResearchTrace trace;
  final bool running;

  @override
  State<ResearchTraceView> createState() => _ResearchTraceViewState();
}

class _ResearchTraceViewState extends State<ResearchTraceView> {
  bool _open = true;
  bool _showAll = false;
  bool _autoCollapsed = false;

  @override
  void didUpdateWidget(ResearchTraceView old) {
    super.didUpdateWidget(old);
    // Auto-collapse once when the answer starts streaming.
    if (old.running && !widget.running && !_autoCollapsed) {
      _autoCollapsed = true;
      _open = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final secs = widget.trace.elapsed.inMilliseconds / 1000.0;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header — live timer while running.
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _open = !_open);
          },
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(children: [
              widget.running
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: accent))
                  : AnimatedAppIcon(
                      type: AppIconType.verified,
                      active: true,
                      size: 14,
                      color: accent),
              const SizedBox(width: AppSpacing.xs),
              Text(
                widget.running
                    ? 'Researching ${secs.toStringAsFixed(0)}s'
                    : 'Researched ${secs.toStringAsFixed(0)}s',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: accent),
              ),
              const Spacer(),
              AnimatedAppIcon(
                  type: AppIconType.chevron,
                  active: _open,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant),
            ]),
          ),
        ),
        AnimatedSize(
          duration: AppMotion.base,
          curve: AppMotion.standard,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.sm, 0, AppSpacing.sm, AppSpacing.sm),
                  child: Column(children: [
                    for (var i = 0; i < _visibleEvents.length; i++)
                      FadeSlideIn(
                        index: i,
                        stagger: const Duration(milliseconds: 30),
                        child: _TraceRow(event: _visibleEvents[i]),
                      ),
                    if (!_showAll && _hiddenCount > 0)
                      InkWell(
                        onTap: () => setState(() => _showAll = true),
                        child: Padding(
                          padding:
                              const EdgeInsets.only(top: AppSpacing.xxs),
                          child: Row(children: [
                            Icon(Icons.add,
                                size: 14, color: accent),
                            Text(' +$_hiddenCount more',
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(color: accent)),
                          ]),
                        ),
                      ),
                  ]),
                )
              : const SizedBox.shrink(),
        ),
      ]),
    );
  }

  List<TraceEvent> get _visibleEvents {
    if (_showAll) return widget.trace.events;
    return widget.trace.events.take(8).toList();
  }

  int get _hiddenCount =>
      (widget.trace.events.length - _visibleEvents.length).clamp(0, 999);
}

class _TraceRow extends StatelessWidget {
  const _TraceRow({required this.event});
  final TraceEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = event; // promote the public field to a local
    if (e is TraceStep) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Icon(_stepIcon(e.kind),
              size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.xs),
          Text(e.label, style: theme.textTheme.labelMedium),
        ]),
      );
    }
    if (e is TraceQuery) {
      return Padding(
        padding:
            const EdgeInsets.only(left: AppSpacing.md, top: 2, bottom: 2),
        child: Row(children: [
          Icon(Icons.search,
              size: 12, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(e.query.q,
                style: theme.textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          if (e.provider != null)
            Text(' ${e.provider}',
                style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.tertiary)),
        ]),
      );
    }
    if (e is TraceSource) {
      return SourceRow(hit: e.hit);
    }
    return const SizedBox.shrink();
  }

  IconData _stepIcon(String kind) => switch (kind) {
        'plan' => Icons.route_outlined,
        'search' => Icons.search,
        'read' => Icons.article_outlined,
        'write' => Icons.edit_outlined,
        _ => Icons.circle_outlined,
      };
}

/// Favicon + "host › path" + title + status chip; tap opens detail sheet.
class SourceRow extends StatelessWidget {
  const SourceRow({super.key, required this.hit});
  final SearchHit hit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chip = switch (hit.status) {
      HitStatus.verified => ('Verified', theme.colorScheme.primary),
      HitStatus.reachable => ('Reachable', theme.colorScheme.tertiary),
      HitStatus.dead => ('Dead', theme.colorScheme.error),
      HitStatus.unverified => (hit.provider,
          theme.colorScheme.onSurfaceVariant),
    };
    return InkWell(
      onTap: () => SourceSheet.show(context, hit),
      child: Padding(
        padding: const EdgeInsets.only(
            left: AppSpacing.md, top: 3, bottom: 3),
        child: Row(children: [
          // Favicon with monogram fallback.
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.network(
              hit.favicon,
              width: 14,
              height: 14,
              errorBuilder: (_, _, _) => Container(
                width: 14,
                height: 14,
                color: theme.colorScheme.surfaceContainerHighest,
                alignment: Alignment.center,
                child: Text(
                    hit.host.isNotEmpty ? hit.host[0].toUpperCase() : '?',
                    style: const TextStyle(fontSize: 8)),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${hit.breadcrumb} · ${hit.title}',
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: chip.$2.withValues(alpha: 0.5)),
            ),
            child: Text(chip.$1,
                style: TextStyle(
                    fontSize: 9, color: chip.$2, letterSpacing: 0.4)),
          ),
        ]),
      ),
    );
  }
}

/// Source detail bottom sheet — full URL + Open/Copy/Share.
class SourceSheet extends StatelessWidget {
  const SourceSheet({super.key, required this.hit});
  final SearchHit hit;

  static void show(BuildContext context, SearchHit hit) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SourceSheet(hit: hit),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(hit.title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(hit.url,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          if (hit.snippet.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(hit.snippet,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant),
                maxLines: 4,
                overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(children: [
            FilledButton.tonalIcon(
              onPressed: () => launchUrl(Uri.parse(hit.url),
                  mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Open'),
            ),
            const SizedBox(width: AppSpacing.sm),
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: hit.url));
                Navigator.pop(context);
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy'),
            ),
            TextButton.icon(
              onPressed: () {
                // Share plugin not added — copy is the portable path.
                Clipboard.setData(ClipboardData(text: hit.url));
              },
              icon: const Icon(Icons.ios_share, size: 16),
              label: const Text('Share'),
            ),
          ]),
        ]),
      ),
    );
  }
}
