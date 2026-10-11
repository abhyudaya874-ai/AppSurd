import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/motion.dart';
import '../../core/widgets/pressable.dart';
import '../../core/theme/spacing.dart';

/// One attached image, downscaled + re-encoded (metadata stripped).
class Attachment {
  const Attachment({required this.dataUri, required this.file});
  final String dataUri; // base64 data URI for vision content parts
  final XFile file;
}

/// Shared image attachment row — thumbnails above the composer field with a
/// circular × badge, animated in/out, max 4, Hero full-screen preview.
/// Used by the Ask composer and the evidence sheet.
class AttachmentBar extends StatefulWidget {
  const AttachmentBar({super.key, required this.attachments});
  final List<Attachment> attachments;

  @override
  State<AttachmentBar> createState() => _AttachmentBarState();
}

class _AttachmentBarState extends State<AttachmentBar> {
  static const maxImages = 4;
  final _picker = ImagePicker();

  Future<void> _pick(ImageSource source) async {
    if (widget.attachments.length >= maxImages) return;
    final img = await _picker.pickImage(
      source: source,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 80, // downscale + re-encode strips metadata
    );
    if (img == null) return;
    final bytes = await File(img.path).readAsBytes();
    setState(() {
      widget.attachments.add(Attachment(
        file: img,
        dataUri:
            'data:image/jpeg;base64,${base64Encode(bytes)}',
      ));
    });
  }

  void _openMenu() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Photo library'),
            onTap: () {
              Navigator.pop(context);
              _pick(ImageSource.gallery);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Camera'),
            onTap: () {
              Navigator.pop(context);
              _pick(ImageSource.camera);
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AnimatedSize(
        duration: AppMotion.base,
        curve: AppMotion.standard,
        child: widget.attachments.isEmpty
            ? const SizedBox.shrink()
            : SizedBox(
                height: 72,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  children: [
                    for (final a in widget.attachments)
                      _Thumb(
                        attachment: a,
                        onRemove: () =>
                            setState(() => widget.attachments.remove(a)),
                      ),
                  ],
                ),
              ),
      ),
      // "+" attach button
      IconButton(
        visualDensity: VisualDensity.compact,
        tooltip: 'Attach image',
        onPressed: _openMenu,
        icon: Icon(Icons.add_photo_alternate_outlined,
            size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ]);
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.attachment, required this.onRemove});
  final Attachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: Stack(children: [
        Pressable(
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => _Preview(attachment: attachment),
          )),
          child: Hero(
            tag: attachment.dataUri.hashCode,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.file(
                File(attachment.file.path),
                width: 64,
                height: 64,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
        // Circular × badge at top-right.
        Positioned(
          top: -2,
          right: -2,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.error,
                border: Border.all(
                    color: theme.colorScheme.surface, width: 1.5),
              ),
              child: const Icon(Icons.close, size: 12, color: Colors.white),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.attachment});
  final Attachment attachment;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.transparent),
      body: Center(
        child: Hero(
          tag: attachment.dataUri.hashCode,
          child: InteractiveViewer(
            child: Image.file(File(attachment.file.path)),
          ),
        ),
      ),
    );
  }
}
