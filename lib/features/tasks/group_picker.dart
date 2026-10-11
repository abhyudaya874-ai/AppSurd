import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'group_model.dart';

/// Shared "pick a group" flow used by the Home composer and Create Task:
/// bottom sheet of Inbox + existing groups + New group (name + colour).
/// Returns the chosen group id, or null for Inbox; unchanged when dismissed.
Future<String?> pickGroupSheet(BuildContext context, WidgetRef ref) async {
  final groups = ref.read(groupsProvider);
  final picked = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: Icon(Icons.inbox_outlined,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          title: const Text('Inbox'),
          onTap: () => Navigator.pop(context, ''),
        ),
        for (final g in groups)
          ListTile(
            leading: Container(
              width: 12,
              height: 12,
              decoration:
                  BoxDecoration(color: g.color, shape: BoxShape.circle),
            ),
            title: Text(g.name),
            onTap: () => Navigator.pop(context, g.id),
          ),
        ListTile(
          leading: const Icon(Icons.add),
          title: const Text('New group'),
          onTap: () => Navigator.pop(context, 'new'),
        ),
      ]),
    ),
  );
  if (picked == null) return null; // dismissed — keep current choice
  if (picked == 'new') {
    if (!context.mounted) return null;
    final g = await newGroupSheet(context, ref);
    return g?.id; // null = user bailed on creation
  }
  return picked.isEmpty ? '' : picked;
}

/// Name + colour picker; creates the group via [groupsProvider] and returns
/// it so the caller can select it immediately.
Future<Group?> newGroupSheet(BuildContext context, WidgetRef ref) async {
  final ctrl = TextEditingController();
  const palette = [
    Color(0xFF4FD8E0), Color(0xFFFBBF24), Color(0xFFB794F6),
    Color(0xFF4ADE80), Color(0xFFFF6B6B), Color(0xFF60A5FA),
  ];
  Color picked = palette[0];
  final ok = await showModalBottomSheet<Group>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, set) => Padding(
        padding: EdgeInsets.only(
            left: 20, right: 20, top: 8,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('New group',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Group name'),
          ),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (final c in palette)
              GestureDetector(
                onTap: () => set(() => picked = c),
                child: Container(
                  width: 34,
                  height: 34,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: picked == c
                        ? Border.all(color: Colors.white, width: 2.5)
                        : null,
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              await ref.read(groupsProvider.notifier).addGroup(name, picked);
              if (context.mounted) {
                Navigator.pop(
                    context,
                    ref.read(groupsProvider).lastWhere(
                        (g) => g.name == name));
              }
            },
            child: const Text('Create'),
          ),
        ]),
      ),
    ),
  );
  return ok;
}
