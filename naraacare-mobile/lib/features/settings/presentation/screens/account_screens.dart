import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/routing/routes.dart';
import 'package:naraacare/core/security/input_validators.dart';
import 'package:naraacare/core/security/screen_guard.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/features/auth/auth_providers.dart';
import 'package:naraacare/features/auth/presentation/auth_errors.dart';
import 'package:naraacare/features/auth/presentation/widgets/auth_scaffold.dart';
import 'package:naraacare/features/auth/presentation/widgets/password_rules.dart';
import 'package:naraacare/features/profile/presentation/username_form.dart';
import 'package:naraacare/features/profile/profile_providers.dart';
import 'package:naraacare/shared/widgets/nc_button.dart';
import 'package:naraacare/shared/widgets/nc_text_field.dart';
import 'package:naraacare/shared/widgets/nc_toast.dart';

/// ST3 Username: change it (once every 3 months, enforced by the API).
class UsernameScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final me = ref.watch(meProvider).value;
    return Scaffold(
      backgroundColor: nc.surface,
      appBar: AppBar(
        title: Text(l10n.usernameLabel),
        backgroundColor: nc.surface,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(nc.screenPadding),
        child: UsernameForm(
          initial: me?.username,
          onSaved: () {
            showNcToast(context, l10n.usernameSaved);
            context.pop();
          },
        ),
      ),
    );
  }
}

/// ST4 Account: email (read-only), change password, Delete Account (Figma
/// "Profile/ Settings/ Account", S15). Screenshots are blocked (OQ-50).
class AccountScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final me = ref.watch(meProvider).value;
    return ScreenGuard(
      child: Scaffold(
        backgroundColor: nc.surface,
        appBar: AppBar(title: Text(l10n.account), backgroundColor: nc.surface),
        body: ListView(
          padding: EdgeInsets.all(nc.screenPadding),
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.mail_outline),
              title: Text(l10n.emailLabel),
              subtitle: Text(me?.email ?? ''),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_outline),
              title: Text(l10n.changePassword),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Routes.changePassword),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.delete_outline, color: nc.error),
              title: Text(
                l10n.deleteAccount,
                style: TextStyle(color: nc.error),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Routes.deleteAccount),
            ),
          ],
        ),
      ),
    );
  }
}

/// Change password from Account (POST /auth/password/change). Other
/// sessions are signed out by the API; this one stays signed in.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _password.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authApiProvider)
          .changePassword(
            currentPassword: _current.text,
            newPassword: _password.text,
            confirmPassword: _confirm.text,
          );
      if (!mounted) return;
      showNcToast(context, l10n.passwordUpdated);
      context.pop();
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = featureErrorMessage(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    return ScreenGuard(
      child: Scaffold(
        backgroundColor: nc.surface,
        appBar: AppBar(
          title: Text(l10n.changePassword),
          backgroundColor: nc.surface,
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.all(nc.screenPadding),
          child: AutofillGroup(
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  NcTextField(
                    controller: _current,
                    validator: InputValidators.passwordLogin,
                    maxLength: 128,
                    label: l10n.currentPasswordLabel,
                    hint: l10n.currentPasswordHint,
                    secret: true,
                    autofillHints: const [AutofillHints.password],
                  ),
                  const SizedBox(height: NcSpace.cardGap),
                  NcTextField(
                    controller: _password,
                    validator: InputValidators.password,
                    maxLength: 128,
                    label: l10n.newPasswordLabel,
                    hint: l10n.newPasswordHint,
                    secret: true,
                    autofillHints: const [AutofillHints.newPassword],
                  ),
                  const SizedBox(height: NcSpace.cardGap),
                  NcTextField(
                    controller: _confirm,
                    validator: InputValidators.confirmPassword(
                      () => _password.text,
                    ),
                    maxLength: 128,
                    label: l10n.confirmPasswordLabel,
                    hint: l10n.confirmNewPasswordHint,
                    secret: true,
                    autofillHints: const [AutofillHints.newPassword],
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: NcSpace.cardGap),
                  PasswordRules(password: _password.text),
                  const SizedBox(height: NcSpace.sectionGap),
                  FormErrorText(_error),
                  NcButton(
                    label: l10n.saveButton,
                    loading: _busy,
                    onPressed: _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
