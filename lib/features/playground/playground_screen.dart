import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/ai_failure.dart';
import '../../core/ai/api_key_store.dart';
import '../../core/ai/model_catalog.dart';
import '../../core/ai/model_router.dart';
import '../../core/ai/openai_compat_client.dart';
import '../../core/theme/extensions.dart';
import '../../core/theme/spacing.dart';
import '../../core/widgets/pressable.dart';
import '../model_picker/model_pill.dart';
import '../model_picker/model_selection.dart';

/// Phase-2 proving ground: a composer (pill + input + send) that streams a
/// reply from whatever the router picks. Every bubble shows the provider chip
/// so routing decisions are visible. Replaced by the real verification flow
/// in later phases but kept as a debug surface.
class PlaygroundScreen extends ConsumerStatefulWidget {
  const PlaygroundScreen({super.key});

  @override
  ConsumerState<PlaygroundScreen> createState() => _PlaygroundScreenState();
}

class _Msg {
  _Msg.user(this.text)
      : isUser = true,
        spec = null,
        rerouted = null;
  _Msg.assistant({this.spec, this.rerouted})
      : isUser = false,
        text = '';

  final bool isUser;
  String text;
  final ModelSpec? spec;
  final AiProvider? rerouted;
}

class _PlaygroundScreenState extends ConsumerState<PlaygroundScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _messages = [];
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    _input.clear();
    final keys = ref.read(configuredKeysProvider).value ?? const {};
    final alive = ref.read(aliveModelsProvider).value ?? const {};
    final sel = ref.read(modelSelectionProvider);
    final plan = const ModelRouter().plan(
      tier: sel.preset,
      keys: keys,
      aliveIds: alive,
      speed: sel.speed,
      customModelId: sel.customModelId,
    );
    if (plan.candidates.isEmpty) {
      _append(_Msg.assistant()..text = 'No provider key configured — open Settings and add one.');
      return;
    }

    setState(() {
      _sending = true;
      _messages.add(_Msg.user(text));
      _messages.add(_Msg.assistant());
    });
    _scrollToBottom();

    final history = [
      ChatMessage.text(
          'system', 'You are the Receipts demo agent. Answer briefly.'),
      for (final m in _messages.where((m) => m.isUser))
        ChatMessage.text('user', m.text),
    ];

    // Try each candidate in order until one streams successfully.
    var answered = false;
    for (var i = 0; i < plan.candidates.length && !answered; i++) {
      final spec = plan.candidates[i];
      final key = keys[spec.provider];
      if (key == null) continue;
      final client = OpenAiCompatClient(
        baseUrl: spec.provider.baseUrl,
        apiKey: key,
        extraHeaders: spec.provider.extraHeaders,
      );
      var gotToken = false;
      try {
        await for (final token in client.stream(
          model: spec.id,
          messages: history,
        )) {
          gotToken = true;
          answered = true;
          _messages.last.text += token;
          _setMsg(spec, i > 0 ? plan.candidates.first.provider : null);
          _scrollToBottom();
        }
      } on AiFailure {
        if (gotToken) rethrow;
        // Nothing streamed — fall through to the next candidate.
      }
    }
    if (!answered) {
      _messages.last.text = 'Every provider failed. Check keys/network.';
    }
    setState(() => _sending = false);
  }

  void _setMsg(ModelSpec spec, AiProvider? rerouted) {
    final msg = _Msg.assistant(spec: spec, rerouted: rerouted);
    msg.text = _messages.last.text;
    setState(() => _messages[_messages.length - 1] = msg);
  }

  void _append(_Msg m) => setState(() => _messages.add(m));

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Agent playground')),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Text(
                      'Ask anything — the pill decides who answers.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) => _Bubble(msg: _messages[i]),
                  ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: ModelPill(),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration:
                          const InputDecoration(hintText: 'Message'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Pressable(
                      onTap: _send,
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: theme.colorScheme.primary,
                        child: _sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))
                            : Icon(Icons.arrow_upward_rounded,
                                color: theme.colorScheme.onPrimary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Chat bubble with the answering model's provider chip + "rerouted via X".
class _Bubble extends StatelessWidget {
  const _Bubble({required this.msg});
  final _Msg msg;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tints = theme.extension<ProviderTints>() ?? const ProviderTints();
    if (msg.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm, left: 48),
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(msg.text, style: theme.textTheme.bodyMedium),
        ),
      );
    }
    final tint =
        msg.spec != null ? tints.forId(msg.spec!.provider.id) : null;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm, right: 48),
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (msg.spec != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.circle, size: 8, color: tint),
                  const SizedBox(width: 4),
                  Text(
                    '${msg.spec!.provider.label} · ${msg.spec!.displayName}',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  if (msg.rerouted != null)
                    Text(
                      '  · rerouted from ${msg.rerouted!.label}',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.tertiary),
                    ),
                ]),
              ),
            Text(
              msg.text.isEmpty ? '…' : msg.text,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
