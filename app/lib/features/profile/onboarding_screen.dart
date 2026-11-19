import 'package:material_ui/material_ui.dart';

import '../../core/app_session.dart';
import '../../core/errors.dart';
import '../../core/messenger.dart';
import '../../core/theme.dart';

/// C3 처음 설정: 닉네임 + 약관 동의 (위치기반서비스 약관 포함)
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _nickname = TextEditingController();
  bool _terms = false;
  bool _privacy = false;
  bool _location = false;
  bool _marketing = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _nickname.text = AppSession.instance.profile?.nickname ?? '';
  }

  @override
  void dispose() {
    _nickname.dispose();
    super.dispose();
  }

  bool get _requiredAgreed => _terms && _privacy && _location;
  bool get _allAgreed => _requiredAgreed && _marketing;
  bool get _nicknameOk {
    final n = _nickname.text.trim();
    return n.length >= 2 && n.length <= 20;
  }

  void _setAll(bool v) => setState(() {
        _terms = v;
        _privacy = v;
        _location = v;
        _marketing = v;
      });

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await AppSession.instance.completeOnboarding(
        nickname: _nickname.text.trim(),
        marketing: _marketing,
      );
    } catch (e) {
      showMessage(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showTerms(String title) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: const Text('정식 약관 전문은 출시 전에 이 자리에 들어가요.\n지금은 테스트용 화면이에요.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 32, 20, 20),
                children: [
                  const Text(
                    '반가워요!\n시작하기 전에 알려 주세요',
                    style: TextStyle(fontSize: 24, height: 1.35, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 28),
                  const Text('닉네임', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nickname,
                    maxLength: 20,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: '2~20자',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.line),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        CheckboxListTile(
                          value: _allAgreed,
                          onChanged: (v) => _setAll(v ?? false),
                          title: const Text('전체 동의', style: TextStyle(fontWeight: FontWeight.w800)),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                        const Divider(height: 1),
                        _ConsentRow(
                          label: '서비스 이용약관 (필수)',
                          value: _terms,
                          onChanged: (v) => setState(() => _terms = v),
                          onView: () => _showTerms('서비스 이용약관'),
                        ),
                        _ConsentRow(
                          label: '개인정보 수집·이용 (필수)',
                          value: _privacy,
                          onChanged: (v) => setState(() => _privacy = v),
                          onView: () => _showTerms('개인정보 수집·이용'),
                        ),
                        _ConsentRow(
                          label: '위치기반서비스 이용약관 (필수)',
                          sub: '동네 인증과 근무 위치 확인에 써요',
                          value: _location,
                          onChanged: (v) => setState(() => _location = v),
                          onView: () => _showTerms('위치기반서비스 이용약관'),
                        ),
                        _ConsentRow(
                          label: '이벤트·혜택 알림 받기 (선택)',
                          value: _marketing,
                          onChanged: (v) => setState(() => _marketing = v),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: FilledButton(
                onPressed: (_busy || !_nicknameOk || !_requiredAgreed) ? null : _submit,
                child: _busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Text('시작하기'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConsentRow extends StatelessWidget {
  const _ConsentRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.sub,
    this.onView,
  });

  final String label;
  final String? sub;
  final bool value;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onView;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: value,
      onChanged: (v) => onChanged(v ?? false),
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(label, style: const TextStyle(fontSize: 14)),
      subtitle: sub == null ? null : Text(sub!, style: const TextStyle(fontSize: 12, color: AppColors.meta)),
      secondary: onView == null ? null : TextButton(onPressed: onView, child: const Text('보기')),
    );
  }
}
