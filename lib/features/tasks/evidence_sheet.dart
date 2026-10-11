import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/motion.dart';
import '../../core/theme/spacing.dart';
import '../../core/widgets/pressable.dart';
import '../arena/arena_screen.dart';
import '../arena/arena_state.dart';
import '../model_picker/model_selection.dart';
import '../verification/verification_screen.dart';
import 'task_model.dart';
import 'tasks_provider.dart';

/// Evidence capture sheet: a sliding segmented control picks the proof type
/// (URL / screenshot / text / GitHub commit) and the input cross-fades to
/// match. Submits an [EvidenceAttempt] and pushes the verification screen.
class EvidenceSheet extends ConsumerStatefulWidget {
  const EvidenceSheet({super.key, required this.task});

  final Task task;

  static Future<void> show(BuildContext context, Task task) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => EvidenceSheet(task: task),
    );
  }

  @override
  ConsumerState<EvidenceSheet> createState() => _EvidenceSheetState();
}

class _EvidenceSheetState extends ConsumerState<EvidenceSheet> {
  EvidenceType _type = EvidenceType.url;
  final _urlCtrl = TextEditingController();
  final _textCtrl = TextEditingController();
  final _commitCtrl = TextEditingController();
  XFile? _image;
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _textCtrl.dispose();
    _commitCtrl.dispose();
    super.dispose();
  }

  String? _validate() {
    switch (_type) {
      case EvidenceType.url:
        final u = Uri.tryParse(_urlCtrl.text.trim());
        if (u == null || !u.hasScheme || u.host.isEmpty) {
          return 'Enter a full URL (https://…)';
        }
        return null;
      case EvidenceType.screenshot:
        return _image == null ? 'Pick a screenshot first' : null;
      case EvidenceType.text:
        return _textCtrl.text.trim().length < 20
            ? 'Tell the story properly — at least 20 characters'
            : null;
      case EvidenceType.commit:
        final u = _commitCtrl.text.trim();
        if (!RegExp(r'github\.com/[^/]+/[^/]+/(commit|pull)/')
            .hasMatch(u)) {
          return 'Paste a GitHub commit or PR URL';
        }
        return null;
    }
  }

  Future<void> _pickImage() async {
    // Downscale to ≤1280px at capture — smaller base64, faster upload.
    final img = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 85,
    );
    if (img != null) setState(() => _image = img);
  }

  Future<void> _submit() async {
    final err = _validate();
    setState(() => _error = err);
    if (err != null || _submitting) return;
    setState(() => _submitting = true);

    final payload = switch (_type) {
      EvidenceType.url => _urlCtrl.text.trim(),
      EvidenceType.screenshot => _image!.path,
      EvidenceType.text => _textCtrl.text.trim(),
      EvidenceType.commit => _commitCtrl.text.trim(),
    };
    final attempt = EvidenceAttempt(
      id: const Uuid().v4(),
      type: _type,
      payload: payload,
      submittedAt: DateTime.now(),
    );
    await ref
        .read(tasksProvider.notifier)
        .addAttempt(widget.task.id, attempt);
    if (!mounted) return;
    Navigator.of(context).pop();
    // Arena mode with a valid lineup goes to the jury; else single verifier.
    final arenaOn = ref.read(arenaReadyProvider);
    if (arenaOn) {
      final sel = ref.read(modelSelectionProvider);
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ArenaScreen(
          taskId: widget.task.id,
          attemptId: attempt.id,
          lineup: ref.read(arenaLineupProvider),
          strictness: sel.strictness,
        ),
      ));
    } else {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => VerificationScreen(
            taskId: widget.task.id, attemptId: attempt.id),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.sm,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Submit proof', style: theme.textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '"${widget.task.title}" — show, don\'t tell.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.md),
          _SegmentedControl(
            type: _type,
            onChanged: (t) => setState(() {
              _type = t;
              _error = null;
            }),
          ),
          const SizedBox(height: AppSpacing.md),
          AnimatedSize(
            duration: AppMotion.base,
            curve: AppMotion.standard,
            child: AnimatedSwitcher(
              duration: AppMotion.fast,
              child: switch (_type) {
                EvidenceType.url => _UrlInput(key: const ValueKey('u'), ctrl: _urlCtrl),
                EvidenceType.screenshot =>
                  _ShotInput(key: const ValueKey('s'), image: _image, onPick: _pickImage),
                EvidenceType.text =>
                  _TextInput(key: const ValueKey('t'), ctrl: _textCtrl),
                EvidenceType.commit =>
                  _CommitInput(key: const ValueKey('c'), ctrl: _commitCtrl),
              },
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(_error!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error)),
            ),
          const SizedBox(height: AppSpacing.md),
          Pressable(
            onTap: _submit,
            child: FilledButton(
              onPressed: _submit,
              child: Text(_submitting ? 'Sending…' : 'Verify it'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sliding segmented control — the indicator glides between four segments.
class _SegmentedControl extends StatelessWidget {
  const _SegmentedControl({required this.type, required this.onChanged});
  final EvidenceType type;
  final ValueChanged<EvidenceType> onChanged;

  static const _icons = {
    EvidenceType.url: Icons.link,
    EvidenceType.screenshot: Icons.image_outlined,
    EvidenceType.text: Icons.notes,
    EvidenceType.commit: Icons.commit,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const types = EvidenceType.values;
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth / types.length;
          return Stack(children: [
            AnimatedAlign(
              duration: AppMotion.base,
              curve: AppMotion.standard,
              alignment:
                  Alignment(-1 + 2 * type.index / (types.length - 1), 0),
              child: Container(
                width: w,
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.6)),
                ),
              ),
            ),
            Row(children: [
              for (final t in types)
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onChanged(t),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_icons[t],
                            size: 17,
                            color: t == type
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant),
                        Text(
                          switch (t) {
                            EvidenceType.url => 'URL',
                            EvidenceType.screenshot => 'Shot',
                            EvidenceType.text => 'Text',
                            EvidenceType.commit => 'Commit',
                          },
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: t == type
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ]),
          ]);
        },
      ),
    );
  }
}

class _UrlInput extends StatelessWidget {
  const _UrlInput({super.key, required this.ctrl});
  final TextEditingController ctrl;
  @override
  Widget build(BuildContext context) => TextField(
        controller: ctrl,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(
          hintText: 'https://… (the thing you shipped)',
          prefixIcon: Icon(Icons.link),
        ),
      );
}

class _ShotInput extends StatelessWidget {
  const _ShotInput(
      {super.key, required this.image, required this.onPick});
  final XFile? image;
  final VoidCallback onPick;
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      OutlinedButton.icon(
        onPressed: onPick,
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: Text(image == null ? 'Pick screenshot' : 'Change screenshot'),
      ),
      if (image != null)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: kIsWeb
                ? Image.network(image!.path, height: 140, fit: BoxFit.cover)
                : Image.file(File(image!.path),
                    height: 140, fit: BoxFit.cover),
          ),
        ),
    ]);
  }
}

class _TextInput extends StatelessWidget {
  const _TextInput({super.key, required this.ctrl});
  final TextEditingController ctrl;
  @override
  Widget build(BuildContext context) => TextField(
        controller: ctrl,
        minLines: 4,
        maxLines: 6,
        maxLength: 1200,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'Explain what you did, with specifics…',
        ),
      );
}

class _CommitInput extends StatelessWidget {
  const _CommitInput({super.key, required this.ctrl});
  final TextEditingController ctrl;
  @override
  Widget build(BuildContext context) => TextField(
        controller: ctrl,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(
          hintText: 'github.com/owner/repo/commit/sha',
          prefixIcon: Icon(Icons.commit),
        ),
      );
}
