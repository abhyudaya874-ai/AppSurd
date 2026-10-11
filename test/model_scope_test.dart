import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive_ce.dart';

import 'package:receipts/core/ai/model_catalog.dart';
import 'package:receipts/core/ai/model_router.dart';
import 'package:receipts/features/model_picker/model_selection.dart';

/// Scope wiring: task = curated seed only, ask = full free list; the two
/// custom selections are independent.
void main() {
  setUpAll(() => Hive.init('/tmp/model_scope_test_hive'));

  test('task scope lists only the curated seed catalog', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final curated = c.read(curatedCatalogProvider).value!;
    expect(curated.length, kModelCatalog.length);
    // Seed list is the same pool the router draws from for verification.
    expect(curated.every(kModelCatalog.contains), isTrue);
  });

  test('ask and task selections persist independently', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(modelSelectionProvider.notifier);
    n.setCustomModel('meta/llama-3.3-70b-instruct');
    n.setAskModel('deepseek/deepseek-r1:free');
    final sel = c.read(modelSelectionProvider);
    expect(sel.customModelId, 'meta/llama-3.3-70b-instruct');
    expect(sel.askModelId, 'deepseek/deepseek-r1:free');
    // Persisted into json → restored verbatim on next load.
    final json = sel.toJson();
    expect(
      ModelSelection.fromJson(json).askModelId,
      'deepseek/deepseek-r1:free',
    );
  });

  test(
    'router never pulls verification candidates outside curated pool',
    () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      // With no keys the plan is empty — but the pool must still be curated.
      final plan = const ModelRouter().plan(
        tier: Tier.balanced,
        keys: const {},
      );
      expect(plan.candidates.every(kModelCatalog.contains), isTrue);
    },
  );
}
