import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/privacy_settings.dart';

/// 锁屏页面
class LockScreen extends StatefulWidget {
  final Widget child;

  const LockScreen({super.key, required this.child});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with WidgetsBindingObserver {
  bool _locked = false;
  bool _loading = false;
  String? _error;
  final _pwdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkLock();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pwdController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && PrivacySettings().enabled) {
      PrivacySettings().lock();
      if (mounted) setState(() => _locked = true);
    }
  }

  void _checkLock() {
    final ps = PrivacySettings();
    _locked = ps.enabled && !ps.authenticated;
    if (!_locked) _pwdController.clear();
  }

  Future<void> _unlock() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final ps = PrivacySettings();

    // 先试生物识别
    if (ps.useBiometric && await PrivacySettings.canUseBiometric()) {
      final ok = await PrivacySettings.authenticateBiometric();
      if (ok) {
        ps.authenticated = true;
        if (mounted) setState(() => _locked = false);
        if (mounted) setState(() => _loading = false);
        return;
      }
    }

    // 生物识别失败或不可用，用密码
    if (ps.hasPassword) {
      // 等待用户输入密码
      if (mounted) setState(() => _loading = false);
      return;
    }

    if (mounted) setState(() => _loading = false);
  }

  void _submitPassword() {
    final pwd = _pwdController.text.trim();
    if (pwd.isEmpty) return;

    if (PrivacySettings().verifyPassword(pwd)) {
      PrivacySettings().authenticated = true;
      setState(() {
        _locked = false;
        _error = null;
      });
      _pwdController.clear();
    } else {
      setState(() => _error = '密码错误');
      _pwdController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_locked) return widget.child;

    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline,
                  size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              const Text('应用已锁定',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text('验证身份以解锁',
                  style: TextStyle(
                      fontSize: 14,
                      color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 32),

              // 生物识别按钮
              if (PrivacySettings().useBiometric)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _unlock,
                    icon: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2))
                        : const Icon(Icons.fingerprint),
                    label: Text(_loading ? '验证中...' : '使用面容/指纹解锁'),
                  ),
                ),

              if (PrivacySettings().useBiometric && PrivacySettings().hasPassword)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('或', style: TextStyle(fontSize: 13)),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                ),

              // 密码输入
              if (PrivacySettings().hasPassword) ...[
                TextField(
                  controller: _pwdController,
                  obscureText: true,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: '请输入密码',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    errorText: _error,
                    prefixIcon: const Icon(Icons.lock_outline, size: 18),
                  ),
                  onSubmitted: (_) => _submitPassword(),
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(r'\s')),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _submitPassword,
                    child: const Text('解锁'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
