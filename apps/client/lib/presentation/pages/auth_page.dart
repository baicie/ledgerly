import 'package:flutter/material.dart';

import '../../auth/auth_controller.dart';
import '../../config/api_endpoint_controller.dart';
import '../api_endpoint_editor.dart';

enum AuthMode { login, register }

const _maxEmailLength = 254;
const _maxDisplayNameLength = 80;
const _maxPasswordLength = 128;

class AuthPage extends StatefulWidget {
  const AuthPage({
    super.key,
    required this.controller,
    required this.endpointController,
  });

  final AuthController controller;
  final ApiEndpointController endpointController;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();
  var _mode = AuthMode.login;
  var _obscurePassword = true;
  var _editingEndpoint = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    if (_mode == AuthMode.login) {
      await widget.controller.login(
        email: _emailController.text,
        password: _passwordController.text,
      );
    } else {
      await widget.controller.register(
        email: _emailController.text,
        password: _passwordController.text,
        displayName: _displayNameController.text,
      );
    }
  }

  Future<void> _editEndpoint() async {
    final current = widget.endpointController.state.endpoint?.baseUrl;
    if (current == null) return;
    final selected = await showApiEndpointEditorDialog(
      context: context,
      controller: widget.endpointController,
      currentValue: current,
    );
    if (selected == null || selected == current || !mounted) return;

    setState(() => _editingEndpoint = true);
    try {
      await widget.endpointController.save(selected);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('API 地址保存失败，请稍后重试。')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _editingEndpoint = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.controller,
        widget.endpointController,
      ]),
      builder: (context, _) {
        final state = widget.controller.state;
        final busy =
            state.status == AuthStatus.authenticating || _editingEndpoint;
        final endpoint = widget.endpointController.state.endpoint;
        return Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 32,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 64,
                    ),
                    child: Center(
                      child: SizedBox(
                        width: 420,
                        child: AutofillGroup(
                          child: Form(
                            key: _formKey,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Icon(
                                  Icons.account_balance_wallet_outlined,
                                  size: 42,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  'Ledgerly',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 18),
                                Row(
                                  children: [
                                    const Icon(Icons.dns_outlined, size: 20),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'API 服务',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelMedium,
                                          ),
                                          Text(
                                            endpoint?.baseUrl ?? '',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      key: const Key('auth-api-edit'),
                                      tooltip: '更换 API 服务',
                                      onPressed: busy ? null : _editEndpoint,
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 28),
                                SegmentedButton<AuthMode>(
                                  segments: const [
                                    ButtonSegment(
                                      value: AuthMode.login,
                                      icon: Icon(Icons.login),
                                      label: Text('登录'),
                                    ),
                                    ButtonSegment(
                                      value: AuthMode.register,
                                      icon: Icon(Icons.person_add_outlined),
                                      label: Text('注册'),
                                    ),
                                  ],
                                  selected: {_mode},
                                  onSelectionChanged: busy
                                      ? null
                                      : (selection) {
                                          setState(() {
                                            _mode = selection.single;
                                          });
                                          widget.controller.clearMessage();
                                        },
                                ),
                                const SizedBox(height: 24),
                                TextFormField(
                                  key: const Key('auth-email'),
                                  controller: _emailController,
                                  enabled: !busy,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [AutofillHints.email],
                                  autocorrect: false,
                                  decoration: const InputDecoration(
                                    labelText: '邮箱',
                                    prefixIcon: Icon(Icons.mail_outline),
                                    border: OutlineInputBorder(),
                                  ),
                                  validator: (value) {
                                    final email = value?.trim() ?? '';
                                    if (email.length > _maxEmailLength) {
                                      return '邮箱不能超过 254 个字符';
                                    }
                                    final valid = RegExp(
                                      r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                    ).hasMatch(email);
                                    return valid ? null : '请输入有效邮箱';
                                  },
                                ),
                                if (_mode == AuthMode.register) ...[
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    key: const Key('auth-display-name'),
                                    controller: _displayNameController,
                                    enabled: !busy,
                                    textInputAction: TextInputAction.next,
                                    autofillHints: const [AutofillHints.name],
                                    decoration: const InputDecoration(
                                      labelText: '称呼',
                                      prefixIcon: Icon(Icons.person_outline),
                                      border: OutlineInputBorder(),
                                    ),
                                    validator: (value) {
                                      final length = value?.trim().length ?? 0;
                                      if (length < 1) {
                                        return '请输入称呼';
                                      }
                                      return length > _maxDisplayNameLength
                                          ? '称呼不能超过 80 个字符'
                                          : null;
                                    },
                                  ),
                                ],
                                const SizedBox(height: 14),
                                TextFormField(
                                  key: const Key('auth-password'),
                                  controller: _passwordController,
                                  enabled: !busy,
                                  obscureText: _obscurePassword,
                                  textInputAction: TextInputAction.done,
                                  autofillHints: [
                                    _mode == AuthMode.login
                                        ? AutofillHints.password
                                        : AutofillHints.newPassword,
                                  ],
                                  onFieldSubmitted: (_) => _submit(),
                                  decoration: InputDecoration(
                                    labelText: '密码',
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    border: const OutlineInputBorder(),
                                    suffixIcon: IconButton(
                                      tooltip:
                                          _obscurePassword ? '显示密码' : '隐藏密码',
                                      onPressed: busy
                                          ? null
                                          : () => setState(() {
                                                _obscurePassword =
                                                    !_obscurePassword;
                                              }),
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                      ),
                                    ),
                                  ),
                                  validator: (value) {
                                    final length = value?.length ?? 0;
                                    if (length < 8) {
                                      return '密码至少 8 位';
                                    }
                                    return length > _maxPasswordLength
                                        ? '密码不能超过 128 位'
                                        : null;
                                  },
                                ),
                                if (state.message != null) ...[
                                  const SizedBox(height: 14),
                                  Semantics(
                                    liveRegion: true,
                                    child: Text(
                                      state.message!,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color:
                                            Theme.of(context).colorScheme.error,
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 20),
                                FilledButton.icon(
                                  key: const Key('auth-submit'),
                                  onPressed: busy ? null : _submit,
                                  icon: busy
                                      ? const SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Icon(
                                          _mode == AuthMode.login
                                              ? Icons.login
                                              : Icons.person_add_outlined,
                                        ),
                                  label: Text(
                                    _mode == AuthMode.login ? '登录' : '注册并继续',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
