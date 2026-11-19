import 'package:material_ui/material_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_session.dart';
import '../../core/errors.dart';
import '../../core/messenger.dart';
import '../../core/theme.dart';
import '../../core/widgets/brand_symbol.dart';

/// C2 로그인: 카카오 / 구글 (Supabase 소셜 로그인 → 브라우저 → 앱으로 복귀)
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;

  Future<void> _signIn(OAuthProvider provider) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await AppSession.instance.signInWith(provider);
    } catch (e) {
      showMessage(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          child: Column(
            children: [
              const BrandSymbol(),
              const SizedBox(height: 14),
              const Text(
                '우리동네무인알바',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5),
              ),
              const SizedBox(height: 10),
              const Text(
                '사장님은 믿을 만한 동네 이웃을,\n이웃은 집 앞 1시간 일거리를',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, height: 1.6, color: AppColors.sub),
              ),
              const SizedBox(height: 36),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
                decoration: BoxDecoration(color: AppColors.brandSoft, borderRadius: BorderRadius.circular(20)),
                child: const Column(
                  children: [
                    _Feature(icon: Icons.place_outlined, title: '집에서 1km 안의 공고만', sub: '걸어서 10분 거리 매장에서 일해요'),
                    SizedBox(height: 18),
                    _Feature(icon: Icons.photo_camera_outlined, title: '사진과 체크리스트로 근무 확인', sub: '사장님은 멀리서도 매장 상태를 봐요'),
                    SizedBox(height: 18),
                    _Feature(icon: Icons.schedule, title: '근무 시간은 자동으로 합계', sub: '월별 근무 기록을 한눈에 봐요'),
                  ],
                ),
              ),
              const Spacer(),
              _KakaoButton(onPressed: _busy ? null : () => _signIn(OAuthProvider.kakao)),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _signIn(OAuthProvider.google),
                icon: Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.line, width: 1.5),
                  ),
                  child: const Text('G', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                ),
                label: const Text('Google로 시작하기'),
              ),
              const SizedBox(height: 12),
              const Text(
                '처음이면 다음 화면에서 약관 동의 후 시작해요',
                style: TextStyle(fontSize: 12, color: AppColors.meta),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.title, required this.sub});

  final IconData icon;
  final String title;
  final String sub;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: AppColors.brand, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(sub, style: const TextStyle(fontSize: 13, color: AppColors.sub)),
            ],
          ),
        ),
      ],
    );
  }
}

class _KakaoButton extends StatelessWidget {
  const _KakaoButton({required this.onPressed});

  final VoidCallback? onPressed;

  static const _bubble = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#191919" d="M12 4C7 4 3 7.1 3 11c0 2.5 1.7 4.7 4.2 5.9L6.4 20.5l3.8-2.5c.6.1 1.2.1 1.8.1 5 0 9-3.1 9-7.1S17 4 12 4z"/></svg>''';

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.kakao,
        foregroundColor: const Color(0xFF191919),
        disabledBackgroundColor: AppColors.kakao.withValues(alpha: 0.5),
      ),
      icon: SvgPicture.string(_bubble, width: 20, height: 20),
      label: const Text('카카오로 시작하기'),
    );
  }
}
