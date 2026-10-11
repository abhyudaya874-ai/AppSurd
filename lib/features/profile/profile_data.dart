import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive_ce.dart';

/// Local-only account card — no auth, no backend. Display name + optional
/// GitHub username (for the contributions heatmap) + optional avatar image
/// path, all persisted in receipts_settings.
class Profile {
  const Profile({this.name = '', this.githubUser = '', this.avatarPath});

  final String name;
  final String githubUser;
  final String? avatarPath;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  Profile copyWith({String? name, String? githubUser, String? avatarPath}) =>
      Profile(
        name: name ?? this.name,
        githubUser: githubUser ?? this.githubUser,
        avatarPath: avatarPath ?? this.avatarPath,
      );
}

final profileProvider = NotifierProvider<ProfileNotifier, Profile>(
  ProfileNotifier.new,
);

class ProfileNotifier extends Notifier<Profile> {
  static const _boxName = 'receipts_settings';
  static const _key = 'profile';

  @override
  Profile build() {
    _load();
    return const Profile();
  }

  Future<void> _load() async {
    final box = await Hive.openBox(_boxName);
    final raw = box.get(_key);
    if (raw is Map) {
      state = Profile(
        name: raw['name'] as String? ?? '',
        githubUser: raw['github'] as String? ?? '',
        avatarPath: raw['avatar'] as String?,
      );
    }
  }

  Future<void> save(Profile p) async {
    state = p;
    final box = await Hive.openBox(_boxName);
    await box.put(_key, {
      'name': p.name,
      'github': p.githubUser,
      'avatar': p.avatarPath,
    });
  }
}
