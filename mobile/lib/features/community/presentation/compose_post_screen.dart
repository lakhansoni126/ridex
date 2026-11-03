import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/api/api_client.dart';
import '../../../shared/widgets/glass.dart';
import 'community_feed_screen.dart';

class ComposePostScreen extends ConsumerStatefulWidget {
  const ComposePostScreen({super.key});

  @override
  ConsumerState<ComposePostScreen> createState() => _ComposePostScreenState();
}

class _ComposePostScreenState extends ConsumerState<ComposePostScreen> {
  final _caption = TextEditingController();
  File? _image;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      imageQuality: 85,
    );
    if (file != null) {
      setState(() => _image = File(file.path));
    }
  }

  Future<void> _submit() async {
    if (_image == null) {
      setState(() => _error = 'Add a photo to publish');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(postsRepositoryProvider).createPost(
            caption: _caption.text.trim().isEmpty ? null : _caption.text.trim(),
            images: _image == null ? const [] : [_image!],
          );
      ref.invalidate(communityFeedProvider);
      if (mounted) context.pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      appBar: GlassAppBar(
        title: 'New post',
        actions: [
          TextButton(
            onPressed: _busy ? null : _submit,
            child: const Text('POST', style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      body: SingleChildScrollView(
        child: Column(
          children: [
            GlassContainer(
              variant: GlassVariant.intense,
              child: TextField(
                controller: _caption,
                maxLines: 5,
                style: const TextStyle(color: AppTheme.textPrimary),
                cursorColor: AppTheme.accent,
                decoration: const InputDecoration(
                  hintText: 'Share a moment from the road…',
                  hintStyle: TextStyle(color: AppTheme.textSecondary),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_image != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(_image!, height: 220, fit: BoxFit.cover),
              ),
            const SizedBox(height: 16),
            GlassButton(
              label: _image == null ? 'ADD PHOTO' : 'CHANGE PHOTO',
              style: GlassButtonStyle.secondary,
              icon: Icons.photo_outlined,
              onPressed: _pickImage,
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: AppTheme.accent)),
            ],
            const SizedBox(height: 24),
            GlassButton(
              label: 'PUBLISH',
              busy: _busy,
              onPressed: _busy ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}
