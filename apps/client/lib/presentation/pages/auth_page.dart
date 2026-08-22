import 'package:flutter/material.dart';

import '../../auth/auth_controller.dart';
import '../../config/api_endpoint_controller.dart';
import '../../l10n/l10n.dart';
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
          SnackBar(content: Text(l10nOf(context).apiAddressSaveFailed)),
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
                                            l10nOf(context).apiService,
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
                                      tooltip: l10nOf(context).changeApiService,
                                      onPressed: busy ? null : _editEndpoint,
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 28),
                                SegmentedButton<AuthMode>(
                                  segments: [
                                    ButtonSegment(
                                      value: AuthMode.login,
                                      icon: const Icon(Icons.login),
                                      label: Text(l10nOf(context).login),
                                    ),
                                    ButtonSegment(
                                      value: AuthMode.register,
                                      icon:
                                          const Icon(Icons.person_add_outlined),
                                      label: Text(l10nOf(context).register),
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
                                  decoration: InputDecoration(
                                    labelText: l10nOf(context).email,
                                    prefixIcon: Icon(Icons.mail_outline),
                                    border: OutlineInputBorder(),
                                  ),
                                  validator: (value) {
                                    final email = value?.trim() ?? '';
                                    if (email.length > _maxEmailLength) {
                                      return l10nOf(context).emailTooLong;
                                    }
                                    final valid = RegExp(
                                      r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                    ).hasMatch(email);
                                    return valid
                                        ? null
                                        : l10nOf(context).invalidEmail;
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
                                    decoration: InputDecoration(
                                      labelText: l10nOf(context).displayName,
                                      prefixIcon: Icon(Icons.person_outline),
                                      border: OutlineInputBorder(),
                                    ),
                                    validator: (value) {
                                      final length = value?.trim().length ?? 0;
                                      if (length < 1) {
                                        return l10nOf(context).enterDisplayName;
                                      }
                                      return length > _maxDisplayNameLength
                                          ? l10nOf(context).displayNameTooLong
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
                                    labelText: l10nOf(context).password,
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    border: const OutlineInputBorder(),
                                    suffixIcon: IconButton(
                                      tooltip: _obscurePassword
                                          ? l10nOf(context).showPassword
                                          : l10nOf(context).hidePassword,
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
                                      return l10nOf(context).passwordTooShort;
                                    }
                                    return length > _maxPasswordLength
                                        ? l10nOf(context).passwordTooLong
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
                                    _mode == AuthMode.login
                                        ? l10nOf(context).login
                                        : l10nOf(context).registerAndContinue,
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
