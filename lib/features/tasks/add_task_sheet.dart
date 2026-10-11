import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/spacing.dart';
import 'tasks_provider.dart';

/// Bottom sheet for creating a task — title plus an optional "what counts as
/// proof?" hint that goes to the verifier so it can judge evidence fit.
class AddTaskSheet extends ConsumerStatefulWidget {
  const AddTaskSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const AddTaskSheet(),
    );
  }

  @override
  ConsumerState<AddTaskSheet> createState() => _AddTaskSheetState();
}

class _AddTaskSheetState extends ConsumerState<AddTaskSheet> {
  final _title = TextEditingController();
  final _proof = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _proof.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty || _saving) return;
    setState(() => _saving = true);
    await ref.read(tasksProvider.notifier).addTask(
          title: title,
          description: _proof.text.trim(),
        );
    if (mounted) Navigator.of(context).pop();
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
          Text('New task', style: theme.textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _title,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'What are you committing to?',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _proof,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'What counts as proof? (optional)',
              helperText:
                  'e.g. "a link to the published page" — the verifier uses this',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: _save,
            child: Text(_saving ? 'Adding…' : 'Add task'),
          ),
        ],
      ),
    );
  }
}
