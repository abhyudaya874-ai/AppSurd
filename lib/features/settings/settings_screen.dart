import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/ai_failure.dart';
import '../../core/ai/api_key_store.dart';
import '../../core/ai/model_catalog.dart';
import '../../core/ai/model_router.dart';
import '../../core/ai/openai_compat_client.dart';
import '../../core/theme/extensions.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/spacing.dart';
import '../../core/widgets/fade_slide_in.dart';
import '../tasks/tasks_provider.dart';
import '../voice/voice_engines.dart';
import '../../core/search/search_router.dart';

/// Settings: paste a key per provider (stored in flutter_secure_storage),
/// "Test key" validates it against GET /models, demo-mode toggle lives here
/// too, plus a plain-English privacy note for the judges.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          FadeSlideIn(
            child: Text('AI providers',
                style: theme.textTheme.titleLarge),
          ),
          const SizedBox(height: AppSpacing.xs),
          FadeSlideIn(
            index: 1,
            child: Text(
              'Keys are stored on-device in secure storage and only ever sent '
              'to their own provider. Leave blank to keep a provider locked.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (var i = 0; i < AiProvider.values.length; i++)
            FadeSlideIn(
              index: 2 + i,
              child: _ProviderKeyTile(provider: AiProvider.values[i]),
            ),
          const SizedBox(height: AppSpacing.lg),
          FadeSlideIn(
            index: 5,
            child: OutlinedButton.icon(
              onPressed: () => ref.invalidate(aliveModelsProvider),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh model lists'),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          FadeSlideIn(
            index: 6,
            child: _EnginePickerTile(),
          ),
          const SizedBox(height: AppSpacing.xl),
          FadeSlideIn(
            index: 7,
            child: Text('Web search',
                style: theme.textTheme.titleLarge),
          ),
          const SizedBox(height: AppSpacing.xs),
          FadeSlideIn(
            index: 8,
            child: Text(
              'Search keys let Ask fetch live sources. Only the query text '
              'is sent to Tavily/Exa — never images or evidence.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          _SearchKeyTile(engine: 'tavily', label: 'Tavily'),
          _SearchKeyTile(engine: 'exa', label: 'Exa'),
          const SizedBox(height: AppSpacing.xl),
          FadeSlideIn(
            index: 7,
            child: _DemoModeTile(),
          ),
          const SizedBox(height: AppSpacing.xl),
          FadeSlideIn(
            index: 8,
            child: Text(
              'About — Receipts keeps everything on this device. Evidence you '
              'submit is sent only to the selected AI provider for verification. '
              'Voice audio is deleted after transcription and never uploaded '
              'unless you pick the Groq cloud engine (it is labelled). '
              'No accounts, no analytics, no cloud sync.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// One provider row: tinted name, obscured key field, save + test actions.
class _ProviderKeyTile extends ConsumerStatefulWidget {
  const _ProviderKeyTile({required this.provider});
  final AiProvider provider;

  @override
  ConsumerState<_ProviderKeyTile> createState() => _ProviderKeyTileState();
}

enum _TestState { idle, testing, ok, failed }

class _ProviderKeyTileState extends ConsumerState<_ProviderKeyTile> {
  final _controller = TextEditingController();
  _TestState _test = _TestState.idle;
  bool _loaded = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ref
        .read(configuredKeysProvider.notifier)
        .save(widget.provider, _controller.text.trim());
    setState(() => _test = _TestState.idle);
  }

  Future<void> _testKey() async {
    setState(() => _test = _TestState.testing);
    final key = _controller.text.trim().isNotEmpty
        ? _controller.text.trim()
        : await ref.read(apiKeyStoreProvider).read(widget.provider);
    if (key == null || key.isEmpty) {
      setState(() => _test = _TestState.failed);
      return;
    }
    try {
      final client = OpenAiCompatClient(
        baseUrl: widget.provider.baseUrl,
        apiKey: key,
        extraHeaders: widget.provider.extraHeaders,
      );
      await client.listModelIds();
      if (mounted) setState(() => _test = _TestState.ok);
      ref.invalidate(aliveModelsProvider);
    } on AiFailure {
      if (mounted) setState(() => _test = _TestState.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint =
        (theme.extension<ProviderTints>() ?? const ProviderTints()).forId(widget.provider.id);
    final configured =
        ref.watch(configuredKeysProvider).value?.containsKey(widget.provider) ??
            false;

    // Prefill hint once keys load (never echo the actual key).
    if (!_loaded && configured) {
      _loaded = true;
      _controller.text = '';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 10,
                height: 10,
                decoration:
                    BoxDecoration(color: tint, shape: BoxShape.circle),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(widget.provider.label, style: theme.textTheme.titleMedium),
              const Spacer(),
              AnimatedSwitcher(
                duration: AppMotion.fast,
                child: switch (_test) {
                  _TestState.idle => configured
                      ? Icon(Icons.check_circle_outline,
                          key: const ValueKey('c'),
                          size: 18,
                          color: theme.colorScheme.primary)
                      : const SizedBox.shrink(key: ValueKey('n')),
                  _TestState.testing => const SizedBox(
                      key: ValueKey('t'),
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  _TestState.ok => Icon(Icons.check_circle,
                      key: const ValueKey('ok'),
                      size: 18,
                      color: theme.colorScheme.primary),
                  _TestState.failed => Icon(Icons.error_outline,
                      key: const ValueKey('f'),
                      size: 18,
                      color: theme.colorScheme.error),
                },
              ),
            ]),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _controller,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                isDense: true,
                hintText: configured ? '••••••••  (saved)' : 'paste API key',
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(children: [
              TextButton(onPressed: _save, child: const Text('Save')),
              const SizedBox(width: AppSpacing.xs),
              TextButton(onPressed: _testKey, child: const Text('Test key')),
              const Spacer(),
              AnimatedSwitcher(
                duration: AppMotion.fast,
                child: switch (_test) {
                  _TestState.ok => Text('key works',
                      key: const ValueKey('okt'),
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.primary)),
                  _TestState.failed => Text('rejected or unreachable',
                      key: const ValueKey('ft'),
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.error)),
                  _ => const SizedBox.shrink(),
                },
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Demo Mode toggle — seeds canned tasks/evidence (wired in phase 3).
class _DemoModeTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final demoOn = ref.watch(demoModeProvider);
    return SwitchListTile(
      value: demoOn,
      onChanged: (v) =>
          ref.read(demoModeProvider.notifier).setEnabled(v),
      title: const Text('Demo mode'),
      subtitle: const Text('Seed example tasks + canned evidence for the pitch'),
      contentPadding: EdgeInsets.zero,
    );
  }
}

/// Whether demo mode is on — the tasks feature seeds demo data from this.
final demoModeProvider = NotifierProvider<DemoModeNotifier, bool>(
    DemoModeNotifier.new);

/// Persists the demo-mode flag in the settings box and seeds example tasks.
class DemoModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  /// Toggling on seeds three labelled demo tasks covering the pitch paths:
  /// a good-URL pass, a weak-evidence fail, and a lazy-text roast.
  Future<void> setEnabled(bool value) async {
    state = value;
    if (!value) return;
    final notifier = ref.read(tasksProvider.notifier);
    final existing = ref.read(tasksProvider).value ?? const [];
    if (existing.any((t) => t.isDemo)) return; // seed once
    final demos = [
      ('Ship the landing page', 'a public URL that loads'),
      ('Go to the gym', 'a photo or note with specifics'),
      ('Read 20 pages', 'a summary that proves you read it'),
    ];
    for (final (title, proof) in demos) {
      final t = await notifier.addTask(title: title, description: proof);
      await notifier.updateTask(t.copyWith(isDemo: true));
    }
  }
}

/// Transcription engine picker — Whisper on-device / System / Groq cloud,
/// with unavailable engines dimmed (Whisper dims until its model downloads,
/// Groq dims without a key). Selected choice persists.
class _EnginePickerTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final choice = ref.watch(engineChoiceProvider);
    final engines = ref.watch(engineListProvider).value ?? const [];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Transcription engine', style: theme.textTheme.titleLarge),
      const SizedBox(height: AppSpacing.xs),
      Text(
        'Mic audio is deleted right after transcription — it only leaves '
        'the device if you pick the cloud engine below.',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
      const SizedBox(height: AppSpacing.sm),
      for (final (engine, avail) in engines)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          enabled: avail,
          leading: Icon(
            engine.info.id == 'whisper'
                ? Icons.memory
                : engine.info.id == 'groq'
                    ? Icons.cloud_outlined
                    : Icons.mic,
            size: 20,
            color: avail
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          title: Text(engine.info.label,
              style: theme.textTheme.bodyMedium),
          subtitle: engine.info.id == 'groq'
              ? const Text('Audio is uploaded — cloud engine',
                  style: TextStyle(fontSize: 11))
              : null,
          trailing: EngineChoice.values.firstWhere(
                      (c) => c.name == engine.info.id,
                      orElse: () => EngineChoice.system) ==
                  choice
              ? Icon(Icons.check_circle,
                  size: 18, color: theme.colorScheme.primary)
              : Icon(Icons.circle_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant),
          onTap: avail
              ? () => ref.read(engineChoiceProvider.notifier).set(
                  EngineChoice.values.firstWhere(
                      (c) => c.name == engine.info.id,
                      orElse: () => EngineChoice.system))
              : null,
        ),
    ]);
  }
}

/// Search-provider key tile — same save/test pattern as the AI providers.
class _SearchKeyTile extends ConsumerStatefulWidget {
  const _SearchKeyTile({required this.engine, required this.label});
  final String engine;
  final String label;

  @override
  ConsumerState<_SearchKeyTile> createState() => _SearchKeyTileState();
}

class _SearchKeyTileState extends ConsumerState<_SearchKeyTile> {
  final _controller = TextEditingController();
  _TestState _test = _TestState.idle;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final configured = ref
            .watch(searchKeysProvider)
            .value
            ?[widget.engine]
            ?.isNotEmpty ??
        false;
    return Card(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(children: [
            Text(widget.label, style: theme.textTheme.titleMedium),
            const Spacer(),
            AnimatedSwitcher(
              duration: AppMotion.fast,
              child: switch (_test) {
                _TestState.testing => const SizedBox(
                    key: ValueKey('t'),
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                _TestState.ok => Icon(Icons.check_circle,
                    key: const ValueKey('ok'),
                    size: 18,
                    color: theme.colorScheme.primary),
                _TestState.failed => Icon(Icons.error_outline,
                    key: const ValueKey('f'),
                    size: 18,
                    color: theme.colorScheme.error),
                _TestState.idle => configured
                    ? Icon(Icons.check_circle_outline,
                        key: const ValueKey('c'),
                        size: 18,
                        color: theme.colorScheme.primary)
                    : const SizedBox.shrink(key: ValueKey('n')),
              },
            ),
          ]),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _controller,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(
              isDense: true,
              hintText:
                  configured ? '••••••••  (saved)' : 'paste API key',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(children: [
            TextButton(
              onPressed: () async {
                await ref
                    .read(searchKeysProvider.notifier)
                    .save(widget.engine, _controller.text.trim());
              },
              child: const Text('Save'),
            ),
            TextButton(
              onPressed: () async {
                setState(() => _test = _TestState.testing);
                final ok = await ref
                    .read(searchKeysProvider.notifier)
                    .testKey(widget.engine);
                if (mounted) {
                  setState(() =>
                      _test = ok ? _TestState.ok : _TestState.failed);
                }
              },
              child: const Text('Test key'),
            ),
          ]),
        ]),
      ),
    );
  }
}
