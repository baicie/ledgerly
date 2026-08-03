import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

class FamilyInvitePage extends ConsumerStatefulWidget {
  const FamilyInvitePage({super.key});

  @override
  ConsumerState<FamilyInvitePage> createState() => _FamilyInvitePageState();
}

class _FamilyInvitePageState extends ConsumerState<FamilyInvitePage> {
  final _email = TextEditingController();
  var _busy = false;
  String? _message;
  List<Map<String, dynamic>> _invites = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<String?> _remoteBookId() async {
    return ref.read(authRepositoryProvider).currentSession?.bookId;
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final bookId = await _remoteBookId();
      if (bookId == null) {
        setState(() => _message = '尚未登录同步，无法加载邀请');
        return;
      }
      final list = await ref.read(syncApiProvider).listInvites(bookId: bookId);
      setState(() {
        _invites = list;
        _message = null;
      });
    } catch (e) {
      setState(() => _message = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _invite() async {
    setState(() => _busy = true);
    try {
      final bookId = await _remoteBookId();
      if (bookId == null) return;
      await ref.read(syncApiProvider).createInvite(
            bookId: bookId,
            email: _email.text.trim(),
          );
      _email.clear();
      await _load();
    } catch (e) {
      setState(() => _message = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('家庭共享')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _email,
              decoration: const InputDecoration(
                labelText: '邀请邮箱',
                hintText: 'member@example.com',
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy ? null : _invite,
              child: Text(_busy ? '处理中…' : '发送邀请'),
            ),
            if (_message != null) ...[
              const SizedBox(height: 8),
              Text(_message!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 16),
            Text('已发出邀请', style: Theme.of(context).textTheme.titleMedium),
            Expanded(
              child: ListView.builder(
                itemCount: _invites.length,
                itemBuilder: (context, i) {
                  final inv = _invites[i];
                  return ListTile(
                    title: Text('${inv['email']}'),
                    subtitle: Text('角色 ${inv['role']} · token ${inv['token']}'),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
