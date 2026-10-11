import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/extensions.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/responsive.dart';
import '../../core/widgets/animated_app_icon.dart';
import '../../core/widgets/app_chip.dart';
import '../../core/widgets/fade_slide_in.dart';
import '../../core/widgets/integrity_chip.dart';
import '../../core/widgets/pressable.dart';
import '../model_picker/model_pill.dart';
import '../model_picker/resolved_model.dart';
import '../tasks/composer_hero.dart';
import '../tasks/create_task_screen.dart';
import '../tasks/group_model.dart';
import '../tasks/group_picker.dart';
import '../voice/voice_overlay.dart';

/// Home tab — a Perplexity-style input surface ONLY: brand mark + integrity
/// chip, section label, serif headline, the composer card and suggestion
/// chips. The task list moved to the Tasks tab; sending flies the text into
/// Create Task instead of adding inline.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _ctrl = TextEditingController();
  String? _groupId; // null = Inbox

  static const _suggestions = [
    'Finish an assignment',
    'Push a commit',
    'Read 20 pages',
    'Gym session',
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Fly the typed text into the full editor. Returning `true` means the
  /// task was saved — only then do we clear the composer (backing out keeps
  /// the draft, per spec).
  Future<void> _openEditor() async {
    final title = _ctrl.text.trim();
    if (title.isEmpty) return;
    FocusScope.of(context).unfocus();
    final saved = await Navigator.of(context)
        .push<bool>(createTaskRoute(title, initialGroupId: _groupId));
    if (saved == true) _ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final barGap = 110.0 + MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      body: SafeArea(
        child: ConstrainedContent(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              barGap,
            ),
            children: [
              // Header: mark + name + integrity chip.
              Row(
                children: [
                  const AnimatedAppIcon(
                    type: AppIconType.receipt,
                    active: true,
                    size: 22,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'Receipts',
                    style: AppTypography.grotesk(theme.colorScheme.onSurface)
                        .copyWith(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  const IntegrityChip(),
                ],
              ),
              const SizedBox(height: AppSpacing.xxl),

              // Label + serif headline.
              FadeSlideIn(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'HOME',
                      style: AppTypography.sectionLabel(
                        theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'What will you prove today?',
                      style: AppTypography.display(
                        theme.colorScheme.onSurface,
                        size: 32,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Composer card.
              FadeSlideIn(index: 1, child: _buildComposer(theme)),
              const SizedBox(height: AppSpacing.md),

              // Suggestion chips.
              SizedBox(
                height: 34,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (var i = 0; i < _suggestions.length; i++)
                      FadeSlideIn(
                        index: 2 + i,
                        stagger: const Duration(milliseconds: 60),
                        child: Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.xs),
                          child: AppChip(
                            label: _suggestions[i],
                            onTap: () {
                              _ctrl.text = _suggestions[i];
                              _ctrl.selection = TextSelection.collapsed(
                                offset: _ctrl.text.length,
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComposer(ThemeData theme) {
    final tints = theme.extension<ProviderTints>() ?? const ProviderTints();
    final resolved = ref.watch(resolvedModelProvider);
    final tint = resolved != null
        ? tints.forId(resolved.provider.id)
        : theme.colorScheme.primary;
    final group = ref
        .watch(groupsProvider)
        .where((g) => g.id == _groupId)
        .firstOrNull;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Column(
        children: [
          // The Hero source — its text flies into Create Task's title field.
          Hero(
            tag: kComposerHeroTag,
            flightShuttleBuilder: composerTextShuttle,
            child: Material(
              type: MaterialType.transparency,
              child: TextField(
                controller: _ctrl,
                minLines: 1,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _openEditor(),
                decoration: const InputDecoration(
                  hintText: 'Add a task…',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                ),
                style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              AppChip(
                label: group?.name ?? 'Inbox',
                trailing: Icon(
                  Icons.expand_more,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                onTap: () async {
                  final g = await pickGroupSheet(context, ref);
                  if (g != null) {
                    setState(() => _groupId = g.isEmpty ? null : g);
                  }
                },
              ),
              const SizedBox(width: AppSpacing.xs),
              const Flexible(child: ModelPill()),
              VoiceOrbButton(
                intent: VoiceIntent.task,
                onResult: (r) {
                  _ctrl.text = r.text;
                  _ctrl.selection = TextSelection.collapsed(
                    offset: r.text.length,
                  );
                },
              ),
              const SizedBox(width: AppSpacing.xs),
              Pressable(
                onTap: _openEditor,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.onSurface,
                    border: Border.all(color: tint.withValues(alpha: 0.6)),
                  ),
                  child: Icon(
                    Icons.arrow_upward_rounded,
                    color: theme.colorScheme.surface,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
