import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/providers.dart';
import '../../../data/api/posts_repository.dart';
import '../../../shared/ui/ui.dart';
import 'community_feed_screen.dart';

class ComposePostScreen extends ConsumerStatefulWidget {
  const ComposePostScreen({super.key});

  @override
  ConsumerState<ComposePostScreen> createState() => _ComposePostScreenState();
}

class _ComposePostScreenState extends ConsumerState<ComposePostScreen> {
  static const _maxCaption = 2000;

  final _caption = TextEditingController();
  final _picker = ImagePicker();
  final List<File> _images = [];
  bool _busy = false;

  bool get _dirty => _images.isNotEmpty || _caption.text.trim().isNotEmpty;
  bool get _canPost => _images.isNotEmpty && !_busy;
  int get _remaining => PostsRepository.maxImages - _images.length;

  @override
  void initState() {
    super.initState();
    _caption.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _addPhotos() async {
    if (_remaining <= 0) {
      showRxToast(
          context, 'You can add up to ${PostsRepository.maxImages} photos',
          isError: true);
      return;
    }
    final source = await showRxActionSheet<ImageSource>(
      context,
      actions: const [
        RxSheetAction(label: 'Photo Library', value: ImageSource.gallery),
        RxSheetAction(label: 'Take Photo', value: ImageSource.camera),
      ],
    );
    if (source == null || !mounted) return;
    try {
      if (source == ImageSource.gallery) {
        final files = await _picker.pickMultiImage(
          maxWidth: 2048,
          imageQuality: 85,
        );
        if (!mounted || files.isEmpty) return;
        final room = _remaining;
        setState(() {
          _images.addAll(files.take(room).map((f) => File(f.path)));
        });
        if (files.length > room) {
          showRxToast(context,
              'Only the first ${PostsRepository.maxImages} photos were added');
        }
      } else {
        final file = await _picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 2048,
          imageQuality: 85,
        );
        if (!mounted || file == null) return;
        setState(() => _images.add(File(file.path)));
      }
      HapticFeedback.selectionClick();
    } on PlatformException catch (_) {
      if (mounted) {
        showRxToast(
          context,
          'RideX needs access to your photos or camera. Allow it in Settings.',
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) showRxError(context, e);
    }
  }

  Future<void> _cancel() async {
    if (_busy) return;
    if (_dirty) {
      final discard = await confirmRx(
        context,
        title: 'Discard post?',
        message: 'Your photos and caption will be lost.',
        confirmLabel: 'Discard',
      );
      if (!discard || !mounted) return;
    }
    context.pop();
  }

  Future<void> _post() async {
    if (!_canPost) {
      if (_images.isEmpty) {
        showRxToast(context, 'Add at least one photo', isError: true);
      }
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final caption = _caption.text.trim();
      final post = await ref.read(postsRepositoryProvider).createPost(
            caption: caption.isEmpty ? null : caption,
            images: List.of(_images),
          );
      ref.read(communityFeedProvider.notifier).prepend(post);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      showRxToast(context, 'Posted');
      context.pop();
    } catch (e) {
      if (mounted) showRxError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final length = _caption.text.characters.length;

    return PopScope(
      canPop: !_dirty && !_busy,
      onPopInvoked: (didPop) {
        if (!didPop) _cancel();
      },
      child: RxPage(
        title: 'New Post',
        leading: RxNavTextButton(label: 'Cancel', onPressed: _cancel),
        trailing: RxNavTextButton(
          label: 'Post',
          bold: true,
          busy: _busy,
          onPressed: _canPost ? _post : null,
        ),
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.symmetric(vertical: RxSpace.m),
          children: [
            // Photos
            SizedBox(
              height: 120,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: RxSpace.inset),
                children: [
                  for (var i = 0; i < _images.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: RxSpace.s),
                      child: _Thumb(
                        file: _images[i],
                        onRemove: _busy
                            ? null
                            : () => setState(() => _images.removeAt(i)),
                      ),
                    ),
                  if (_remaining > 0)
                    Semantics(
                      button: true,
                      label: 'Add photos',
                      child: RxPressable(
                        onTap: _busy ? () {} : _addPhotos,
                        child: Container(
                          width: 120,
                          decoration: BoxDecoration(
                            color: rx.card,
                            borderRadius: BorderRadius.circular(RxSpace.radius),
                            border: Border.all(color: rx.separator),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(CupertinoIcons.camera_fill,
                                  color: rx.accent, size: 28),
                              const SizedBox(height: 6),
                              Text(
                                _images.isEmpty
                                    ? 'Add Photos'
                                    : '$_remaining more',
                                style: rx.footnote.copyWith(color: rx.accent),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: RxSpace.l),

            // Caption
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: RxSpace.inset),
              child: RxTextField(
                controller: _caption,
                placeholder: 'Write a caption…',
                maxLines: 8,
                minLines: 4,
                maxLength: _maxCaption,
                textCapitalization: TextCapitalization.sentences,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  RxSpace.inset, 6, RxSpace.inset + 4, 0),
              child: Text(
                '$length / $_maxCaption',
                textAlign: TextAlign.right,
                style: rx.caption.copyWith(
                  color: length > _maxCaption * 0.9
                      ? rx.warning
                      : rx.secondaryLabel,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  RxSpace.inset, RxSpace.m, RxSpace.inset, 0),
              child: Text(
                'Posts are visible to everyone on RideX. Avoid sharing photos that show your home address or licence plates you don\'t want public.',
                style: rx.footnote,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.file, required this.onRemove});

  final File file;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(RxSpace.radius),
              child: Image.file(file, fit: BoxFit.cover, cacheWidth: 360),
            ),
          ),
          if (onRemove != null)
            Positioned(
              top: 0,
              right: 0,
              child: Semantics(
                button: true,
                label: 'Remove photo',
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  minSize: RxSpace.minTouch,
                  onPressed: onRemove,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: const Color(0xB3000000),
                      shape: BoxShape.circle,
                      border: Border.all(color: rx.card, width: 1.5),
                    ),
                    child: const Icon(CupertinoIcons.xmark,
                        size: 12, color: Color(0xFFFFFFFF)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
