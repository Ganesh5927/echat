import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:echat_storage/echat_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../application/local_profile_service.dart';
import 'echat_theme.dart';

typedef AvatarPicker = Future<List<int>?> Function();

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.profileService,
    required this.isTemporaryLocalMode,
    this.pickAvatar,
  });

  final LocalProfileService profileService;
  final bool isTemporaryLocalMode;
  final AvatarPicker? pickAvatar;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const int _maxAvatarBytes = 512 * 1024;
  static const int _maxAvatarDimension = 512;

  final TextEditingController _displayName = TextEditingController();
  late final Future<void> _loadFuture;
  Uint8List? _avatarBytes;
  bool _profileLoaded = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
  }

  @override
  void dispose() {
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final profile = await widget.profileService.load();
    if (!mounted) return;
    _displayName.text = profile?.displayName ?? '';
    _avatarBytes = profile?.avatarBytes;
    _profileLoaded = true;
  }

  Future<List<int>?> _pickGalleryAvatar() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
    return image?.readAsBytes();
  }

  Future<void> _chooseAvatar() async {
    try {
      final bytes = await (widget.pickAvatar ?? _pickGalleryAvatar)();
      if (!mounted || bytes == null) return;
      if (bytes.length > _maxAvatarBytes) {
        setState(() => _error = 'Choose an image smaller than 512 KB.');
        return;
      }
      final processed = await _processAvatar(bytes);
      if (!mounted) return;
      setState(() {
        _avatarBytes = processed;
        _error = null;
      });
    } on ProfileStoreException catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error.code == 'profile_avatar_too_large'
            ? 'Choose an image smaller than 512 KB.'
            : 'Choose a valid image file.',
      );
    } on Object {
      if (!mounted) return;
      setState(() => _error = 'The avatar image could not be selected.');
    }
  }

  Future<Uint8List> _processAvatar(List<int> bytes) async {
    final codec = await ui.instantiateImageCodec(
      Uint8List.fromList(bytes),
      targetWidth: _maxAvatarDimension,
      targetHeight: _maxAvatarDimension,
    );
    try {
      final frame = await codec.getNextFrame();
      try {
        if (frame.image.width > _maxAvatarDimension ||
            frame.image.height > _maxAvatarDimension) {
          throw const ProfileStoreException('invalid_profile_avatar');
        }
        final encoded = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (encoded == null) {
          throw const ProfileStoreException('invalid_profile_avatar');
        }
        if (encoded.lengthInBytes > _maxAvatarBytes) {
          throw const ProfileStoreException('profile_avatar_too_large');
        }
        return Uint8List.fromList(
          encoded.buffer.asUint8List(
            encoded.offsetInBytes,
            encoded.lengthInBytes,
          ),
        );
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  Future<void> _save() async {
    final name = _displayName.text.trim();
    if (name.isEmpty || name.length > 64) {
      setState(() => _error = 'Enter a display name of up to 64 characters.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.profileService.save(
        displayName: name,
        avatarBytes: _avatarBytes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile saved on this device.')),
      );
    } on ProfileStoreException catch (error) {
      if (!mounted) return;
      setState(
        () => _error = switch (error.code) {
          'profile_avatar_too_large' => 'Choose an image smaller than 512 KB.',
          _ => 'Profile could not be saved. Try again.',
        },
      );
    } on Object {
      if (!mounted) return;
      setState(() => _error = 'Profile could not be saved. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: EchatColors.background,
    appBar: AppBar(title: const Text('My Profile')),
    body: FutureBuilder<void>(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text('Local profile could not be loaded.'),
          );
        }
        if (!_profileLoaded) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: const EdgeInsets.all(EchatSpacing.lg),
          children: [
            Center(
              child: Column(
                children: [
                  Semantics(
                    label: _avatarBytes == null
                        ? 'No profile image selected'
                        : 'Profile image preview',
                    image: true,
                    child: CircleAvatar(
                      radius: 52,
                      backgroundColor: EchatColors.surfaceElevated,
                      backgroundImage: _avatarBytes == null
                          ? null
                          : MemoryImage(_avatarBytes!),
                      child: _avatarBytes == null
                          ? Icon(
                              Icons.person_rounded,
                              size: 48,
                              color: EchatColors.textSecondary,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: EchatSpacing.md),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: EchatSpacing.sm,
                    runSpacing: EchatSpacing.sm,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _chooseAvatar,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: Text(
                          _avatarBytes == null
                              ? 'Choose avatar'
                              : 'Change avatar',
                        ),
                      ),
                      if (_avatarBytes != null)
                        TextButton.icon(
                          onPressed: () => setState(() => _avatarBytes = null),
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: const Text('Remove avatar'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: EchatSpacing.xl),
            TextField(
              key: const Key('profile-display-name'),
              controller: _displayName,
              maxLength: 64,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Display name',
                hintText: 'Enter your name',
              ),
            ),
            const SizedBox(height: EchatSpacing.sm),
            Text(
              'This profile is stored locally on this device and is separate from your cryptographic device identity.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: EchatColors.textSecondary,
                height: 1.4,
              ),
            ),
            if (widget.isTemporaryLocalMode) ...[
              const SizedBox(height: EchatSpacing.md),
              Container(
                padding: const EdgeInsets.all(EchatSpacing.md),
                decoration: BoxDecoration(
                  color: EchatColors.warning.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: EchatColors.warning.withValues(alpha: 0.45),
                  ),
                ),
                child: Text(
                  echatTemporaryLocalModeDisclosure,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: EchatColors.warning,
                    height: 1.4,
                  ),
                ),
              ),
            ],
            if (_error case final message?) ...[
              const SizedBox(height: EchatSpacing.md),
              Semantics(
                liveRegion: true,
                child: Text(
                  message,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
            const SizedBox(height: EchatSpacing.xl),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving…' : 'Save profile'),
            ),
          ],
        );
      },
    ),
  );
}
