import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import 'package:receipts/features/tasks/task_model.dart';
import 'package:receipts/features/tasks/tasks_provider.dart';

void main() {
  // Plain (non-widget) test: real async zone, real disk I/O.
  test('tasks provider: add → persist → attempts → verdict', () async {
    Hive.init('/tmp/receipts_flow_test_hive');
    await (await Hive.openBox('receipts_tasks')).clear();

    final container = ProviderContainer();
    addTearDown(container.dispose);

    final task = await container
        .read(tasksProvider.notifier)
        .addTask(title: 'Ship the demo build', description: 'a public URL');
    expect(task.title, 'Ship the demo build');

    // Survives "restart" — reload state from disk.
    final reloaded = await container.read(tasksProvider.future);
    expect(reloaded.any((t) => t.id == task.id), isTrue);

    await container
        .read(tasksProvider.notifier)
        .addAttempt(
          task.id,
          EvidenceAttempt(
            id: 'a1',
            type: EvidenceType.url,
            payload: 'https://example.com',
            submittedAt: DateTime.now(),
          ),
        );
    Task? after = container.read(taskByIdProvider(task.id));
    expect(after!.status, TaskStatus.verifying);
    expect(after.attempts.length, 1);

    await container
        .read(tasksProvider.notifier)
        .attachVerdict(
          task.id,
          {'verdict': 'pass'},
          status: TaskStatus.done,
          integrityDelta: 10,
        );
    after = container.read<Task?>(taskByIdProvider(task.id));
    expect(after!.status, TaskStatus.done);
    expect(container.read(integrityScoreProvider), 60);
  });
}
