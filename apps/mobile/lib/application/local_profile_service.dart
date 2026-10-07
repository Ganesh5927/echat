import 'package:echat_storage/echat_storage.dart';

class LocalProfileService {
  LocalProfileService({required this._store});

  final EncryptedProfileStore _store;

  Future<StoredProfile?> load() => _store.load();

  Future<void> save({
    required String displayName,
    List<int>? avatarBytes,
  }) async {
    final normalizedName = displayName.trim();
    if (normalizedName.isEmpty ||
        normalizedName.length > EncryptedProfileStore.maxDisplayNameLength) {
      throw const ProfileStoreException('invalid_profile_display_name');
    }
    if (avatarBytes != null &&
        avatarBytes.length > EncryptedProfileStore.maxAvatarBytes) {
      throw const ProfileStoreException('profile_avatar_too_large');
    }
    await _store.save(
      StoredProfile(displayName: normalizedName, avatarBytes: avatarBytes),
    );
  }

  Future<void> clear() => _store.clear();
}
