import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/ids.dart';
import '../providers.dart';

class AttachmentsPage extends ConsumerStatefulWidget {
  const AttachmentsPage({super.key});

  @override
  ConsumerState<AttachmentsPage> createState() => _AttachmentsPageState();
}

class _AttachmentsPageState extends ConsumerState<AttachmentsPage> {
  var _busy = false;
  String? _result;

  Future<void> _uploadDemo() async {
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final sync = ref.read(syncServiceProvider);
      await sync.ensureSession(
        email: 'local@ledgerly.dev',
        password: 'password123',
      );
      final api = ref.read(syncApiProvider);
      // Attachments require plus plan.
      await api.devUpgrade(plan: 'plus');
      final state =
          await ref.read(ledgerRepositoryProvider).syncState(defaultBookId);
      final bookId = state?.remoteBookId;
      if (bookId == null) {
        setState(() => _result = '尚未登录同步');
        return;
      }
      final bytes = Uint8List.fromList(List<int>.generate(64, (i) => i));
      final session = await api.createUploadSession(
        bookId: bookId,
        mimeType: 'application/octet-stream',
        size: bytes.length,
      );
      await api.putSignedUrl(
        uploadUrl: session['uploadUrl'] as String,
        bytes: bytes,
      );
      final done = await api.completeAttachment(
        bookId: bookId,
        attachmentId: session['attachmentId'] as String,
      );
      setState(() {
        _result =
            'ready\nattachmentId=${done['attachmentId']}\ndownloadUrl=${done['downloadUrl']}';
      });
    } catch (e) {
      setState(() => _result = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('附件上传')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('HMAC 签名直传本地对象存储：创建会话 → PUT → complete。'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _uploadDemo,
              child: Text(_busy ? '上传中…' : '上传演示文件'),
            ),
            const SizedBox(height: 16),
            if (_result != null) SelectableText(_result!),
          ],
        ),
      ),
    );
  }
}
