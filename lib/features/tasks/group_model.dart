import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:uuid/uuid.dart';

/// A task grouping — name + color dot. Defaults seed on first run; users can
/// add more from the composer's group chip (color picker sheet).
class Group {
  const Group({required this.id, required this.name, required this.color});

  final String id;
  final String name;
  final Color color;

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'color': color.toARGB32()};

  factory Group.fromJson(Map<String, dynamic> json) => Group(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        color: Color((json['color'] as num?)?.toInt() ?? 0xFF8B9097),
      );
}

/// Persisted list of groups (seeded once with three defaults).
final groupsProvider = NotifierProvider<GroupsNotifier, List<Group>>(
    GroupsNotifier.new);

class GroupsNotifier extends Notifier<List<Group>> {
  static const _boxName = 'receipts_settings';
  static const _key = 'groups';

  @override
  List<Group> build() {
    _load();
    return const [
      Group(id: 'personal', name: 'Personal', color: Color(0xFF4FD8E0)),
      Group(id: 'college', name: 'College', color: Color(0xFFFBBF24)),
      Group(id: 'work', name: 'Work', color: Color(0xFFB794F6)),
    ];
  }

  Future<void> _load() async {
    final box = await Hive.openBox(_boxName);
    final raw = box.get(_key);
    if (raw is List && raw.isNotEmpty) {
      state = [
        for (final g in raw)
          Group.fromJson(Map<String, dynamic>.from(g as Map)),
      ];
    }
  }

  Future<void> addGroup(String name, Color color) async {
    final g = Group(id: const Uuid().v4(), name: name, color: color);
    state = [...state, g];
    final box = await Hive.openBox(_boxName);
    await box.put(_key, [for (final x in state) x.toJson()]);
  }
}
