import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/ai_failure.dart';
import '../../core/ai/api_key_store.dart';
import '../../core/ai/model_catalog.dart';
import '../../core/ai/model_router.dart';
import '../../core/ai/openai_compat_client.dart';
import '../../core/ai/prompts.dart';
import '../../core/search/search_models.dart';
import '../../core/search/search_router.dart';
import '../../core/theme/extensions.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/pressable.dart';
import '../model_picker/model_pill.dart';
import '../model_picker/model_selection.dart';
import '../research/attachment_bar.dart';
import '../research/research_pipeline.dart';
import 'trace_mapper.dart';
import '../research/research_trace_view.dart';
import '../../core/theme/motion.dart';
import '../shell/app_shell.dart';

/// One-shot text seed for the Ask composer — Home's Ask mode writes it, the
/// screen consumes it once into `_input` and clears it.
final askSeedProvider = NotifierProvider<AskSeedNotifier, String?>(
  AskSeedNotifier.new,
);

class AskSeedNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  /// Sets (or clears, with null) the pending seed text.
  void set(String? v) => state = v;
}

/// The Ask tab — a research chat. Composer carries +/attachments, the
/// "Search ▾" and "Agentic ▾" override chips, the model pill, and a send
/// button. Assistant answers may carry a [ResearchTrace] rendered above the
/// serif answer text with an Answer/Links tab switch.
class PlaygroundScreen extends ConsumerStatefulWidget {
  const PlaygroundScreen({super.key});

  @override
  ConsumerState<PlaygroundScreen> createState() => _PlaygroundScreenState();
}

class _Msg {
  _Msg.user(this.text, {this.attachments = const []})
    : isUser = true,
      spec = null,
      rerouted = null,
      visionSwap = null,
      trace = null,
      sources = const [];
  _Msg.assistant()
    : isUser = false,
      text = '',
      trace = null,
      sources = const [],
      attachments = const [];

  final bool isUser;
  String text;
  ModelSpec? spec;
  AiProvider? rerouted;
  ModelSpec? visionSwap;
  ResearchTrace? trace;
  List<SearchHit> sources;
  final List<Attachment> attachments;
  var setSpec = false;
  String reasoning = '';
  Stopwatch? thinkClock;
  bool get thinking => thinkClock != null && text.isEmpty;

  _Msg copy() => _Msg.user(text, attachments: attachments)
    ..trace = trace
    ..sources = sources;
}

class _PlaygroundScreenState extends ConsumerState<PlaygroundScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _messages = [];
  final List<Attachment> _attachments = [];
  bool _sending = false;
  SearchOverride _searchOv = SearchOverride.auto;
  AgenticMode _agentic = AgenticMode.search; // default: 1-round search

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    final images = List<Attachment>.from(_attachments);
    if ((text.isEmpty && images.isEmpty) || _sending) return;
    _input.clear();
    setState(() => _attachments.clear());

    final keys = ref.read(configuredKeysProvider).value ?? const {};
    final alive = ref.read(aliveModelsProvider).value ?? const {};
    final sel = ref.read(modelSelectionProvider);
    var plan = const ModelRouter().plan(
      tier: sel.preset,
      keys: keys,
      aliveIds: alive,
      speed: sel.speed,
      customModelId: sel.customModelId,
    );
    if (plan.candidates.isEmpty) {
      _append(
        _Msg.assistant()
          ..text = 'No provider key configured — open Settings and add one.',
      );
      return;
    }

    // ---- Vision routing: images need a vision-capable model ----
    ModelSpec? visionSwap;
    if (images.isNotEmpty && !plan.candidates.first.supportsVision) {
      final v = plan.candidates.where((c) => c.supportsVision).firstOrNull;
      if (v != null) {
        visionSwap = plan.candidates.first;
        plan = RoutePlan(candidates: [v, ...plan.candidates]);
      }
    }

    setState(() {
      _sending = true;
      _messages.add(
        _Msg.user(text.isEmpty ? '(image)' : text, attachments: images),
      );
      _messages.add(_Msg.assistant());
    });
    _scrollToBottom();

    final assistant = _messages.last;

    // ---- Agentic search round (skipped when off or no keys) ----
    final searchKeys = ref.read(searchKeysProvider).value ?? const {};
    List<SearchHit> sources = const [];
    if (_agentic != AgenticMode.off) {
      assistant.trace = ResearchTrace();
      final pipeline = const ResearchPipeline();
      try {
        await for (final e in pipeline.run(
          question: text,
          router: const ModelRouter(),
          plan: plan,
          aiKeys: keys,
          searchKeys: searchKeys,
          override: _searchOv,
          mode: _agentic,
        )) {
          if (e is PipelineDone) {
            sources = e.sources;
            assistant.trace!.finishedAt = DateTime.now();
            assistant.sources = e.sources;
          }
          applyTraceEvent(assistant.trace!, e);
          setState(() {});
        }
      } catch (_) {
        /* search failure → answer without it */
      }
    }
    assistant.trace?.finishedAt = DateTime.now();

    // ---- Synthesize ----
    final List<ChatMessage> history;
    if (sources.isNotEmpty) {
      final block = ResearchPipeline.sourceBlock(sources);
      history = [
        const ChatMessage(role: 'system', content: synthSystem),
        ChatMessage.text('user', '$block\nQUESTION: $text'),
      ];
    } else {
      history = [
        ChatMessage.text(
          'system',
          'You are the Receipts demo agent. Answer briefly.',
        ),
        for (final m in _messages.where((m) => m.isUser))
          m.attachments.isEmpty
              ? ChatMessage.text('user', m.text)
              : ChatMessage(
                  role: 'user',
                  content: [
                    {'type': 'text', 'text': m.text},
                    for (final a in m.attachments)
                      {
                        'type': 'image_url',
                        'image_url': {'url': a.dataUri},
                      },
                  ],
                ),
      ];
    }

    var answered = false;
    for (var i = 0; i < plan.candidates.length && !answered; i++) {
      final spec = plan.candidates[i];
      final key = keys[spec.provider];
      if (key == null) continue;
      // Skip non-vision candidates when images are attached.
      if (images.isNotEmpty && !spec.supportsVision) continue;
      final client = OpenAiCompatClient(
        baseUrl: spec.provider.baseUrl,
        apiKey: key,
        extraHeaders: spec.provider.extraHeaders,
      );
      var gotToken = false;
      try {
        await for (final chunk in client.streamRich(
          model: spec.id,
          messages: history,
        )) {
          gotToken = true;
          answered = true;
          _updateLast(
            spec,
            i > 0 ? plan.candidates[0].provider : null,
            visionSwap: visionSwap,
          );
          if (chunk.reasoning.isNotEmpty) {
            _messages.last.reasoning += chunk.reasoning;
            _messages.last.thinkClock ??= Stopwatch()..start();
          }
          if (chunk.text.isNotEmpty) {
            _messages.last.text += chunk.text;
            _messages.last.thinkClock?.stop();
          }
          _scrollToBottom();
        }
      } on AiFailure {
        if (gotToken) rethrow;
      }
    }
    if (!answered) {
      _messages.last.text = 'Every provider failed. Check keys/network.';
    }
    // Never let a citation survive that doesn't map to a retrieved source.
    _messages.last.text = ResearchPipeline.scrubAnswer(
      _messages.last.text,
      sources,
    );
    setState(() => _sending = false);
  }

  void _updateLast(
    ModelSpec spec,
    AiProvider? rerouted, {
    ModelSpec? visionSwap,
  }) {
    final m = _Msg.assistant()
      ..spec = spec
      ..rerouted = rerouted
      ..visionSwap = visionSwap;
    final last = _messages.last;
    m
      ..text = last.text
      ..trace = last.trace
      ..sources = last.sources;
    setState(() => _messages[_messages.length - 1] = m);
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
    // Consume a Home-sent Ask seed into the input field (once).
    final seed = ref.watch(askSeedProvider);
    if (seed != null) {
      _input.text = seed;
      _input.selection = TextSelection.collapsed(offset: seed.length);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(askSeedProvider.notifier).set(null);
      });
    }
    return Scaffold(
      appBar: AppBar(
        leading: const Padding(
          padding: EdgeInsets.only(left: 8),
          child: MenuAvatar(size: 30),
        ),
        title: const Text('Ask'),
        actions: [
          // Arena is a first-class destination now — jump straight to it.
          IconButton(
            tooltip: 'Compare in Arena',
            icon: const Icon(Icons.groups_rounded, size: 20),
            onPressed: () => ref.read(navIndexProvider.notifier).set(5),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Text(
                      'Ask anything — search or the pill decides.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
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
              child: Column(
                children: [
                  AttachmentBar(attachments: _attachments),
                  Row(
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
                          decoration: const InputDecoration(hintText: 'Ask'),
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
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    Icons.arrow_upward_rounded,
                                    color: theme.colorScheme.onPrimary,
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Search / Agentic override chips.
                  Row(
                    children: [
                      _ChipMenu<SearchOverride>(
                        label: 'Search',
                        value: _searchOv,
                        items: const [
                          (SearchOverride.auto, 'Auto'),
                          (SearchOverride.tavily, 'Tavily'),
                          (SearchOverride.exa, 'Exa'),
                          (SearchOverride.off, 'Off'),
                        ],
                        onPick: (v) => setState(() => _searchOv = v),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      _ChipMenu<AgenticMode>(
                        label: 'Agentic',
                        value: _agentic,
                        items: const [
                          (AgenticMode.off, 'Off'),
                          (AgenticMode.search, 'Search'),
                          (AgenticMode.deep, 'Deep'),
                        ],
                        onPick: (v) => setState(() => _agentic = v),
                      ),
                      if (_attachments.isNotEmpty) ...[
                        const SizedBox(width: AppSpacing.xs),
                        Icon(
                          Icons.visibility_outlined,
                          size: 14,
                          color: theme.colorScheme.primary,
                        ),
                        Text(
                          ' vision',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ],
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

/// Small dropdown-style chip (Search ▾ / Agentic ▾).
class _ChipMenu<T> extends StatelessWidget {
  const _ChipMenu({
    required this.label,
    required this.value,
    required this.items,
    required this.onPick,
  });

  final String label;
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final picked = items.firstWhere((i) => i.$1 == value).$2;
    return PopupMenuButton<T>(
      onSelected: onPick,
      itemBuilder: (_) => [
        for (final (v, l) in items) PopupMenuItem(value: v, child: Text(l)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: value != items.first.$1
                ? theme.colorScheme.primary.withValues(alpha: 0.6)
                : theme.colorScheme.outline,
          ),
        ),
        child: Text(
          '$label · $picked ▾',
          style: theme.textTheme.labelSmall?.copyWith(
            color: value != items.first.$1
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Chat bubble — user images grid above text; assistant may show the
/// research trace + serif answer + provider chip.
class _Bubble extends StatefulWidget {
  const _Bubble({required this.msg});
  final _Msg msg;

  @override
  State<_Bubble> createState() => _BubbleState();
}

class _BubbleState extends State<_Bubble> {
  var _tab = 0; // 0 Answer · 1 Links

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tints = theme.extension<ProviderTints>() ?? const ProviderTints();
    final msg = widget.msg;
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (msg.attachments.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final a in msg.attachments)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          File(a.file.path),
                          width: 110,
                          height: 110,
                          fit: BoxFit.cover,
                        ),
                      ),
                  ],
                ),
              if (msg.text != '(image)')
                Text(msg.text, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      );
    }
    final tint = msg.spec != null ? tints.forId(msg.spec!.provider.id) : null;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm, right: 24),
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Research trace above the answer.
            if (msg.trace != null)
              ResearchTraceView(trace: msg.trace!, running: msg.text.isEmpty),
            if (msg.spec != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 8, color: tint),
                    const SizedBox(width: 4),
                    Text(
                      '${msg.spec!.provider.label} · ${msg.spec!.displayName}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (msg.visionSwap != null)
                      Text(
                        ' · eye → ${msg.spec!.displayName}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: tint,
                        ),
                      ),
                    if (msg.rerouted != null)
                      Text(
                        ' · rerouted from ${msg.rerouted!.label}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.tertiary,
                        ),
                      ),
                  ],
                ),
              ),
            // Answer/Links tabs when there are sources.
            if (msg.sources.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    for (final (i, l) in const [(0, 'Answer'), (1, 'Links')])
                      GestureDetector(
                        onTap: () => setState(() => _tab = i),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 14),
                          child: Column(
                            children: [
                              Text(
                                l,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: _tab == i
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              AnimatedContainer(
                                duration: AppMotion.fast,
                                height: 2,
                                width: 18,
                                color: _tab == i
                                    ? theme.colorScheme.primary
                                    : Colors.transparent,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (_tab == 0) ...[
              _MsgThinking(msg: msg),
              Text(
                msg.text.isEmpty ? '…' : msg.text,
                style: AppTypography.display(
                  theme.colorScheme.onSurface,
                  size: 15,
                ).copyWith(height: 1.45, fontWeight: FontWeight.w400),
              ),
            ] else
              Column(
                children: [for (final h in msg.sources) SourceRow(hit: h)],
              ),
          ],
        ),
      ),
    );
  }
}

/// Thinking block bound to a playground message (duck-typed impl of the
/// shared widget's interface).
/// Adapter: playground _Msg → the shared ThinkableMsg duck type.
class _MsgThinking extends StatelessWidget implements ThinkableMsg {
  const _MsgThinking({required this.msg});
  final _Msg msg;

  @override
  Widget build(BuildContext context) => ThinkingBlock(msg: this);

  @override
  String get reasoning => msg.reasoning;
  @override
  Stopwatch? get thinkClock => msg.thinkClock;
  @override
  bool get thinking => msg.thinking;
}
