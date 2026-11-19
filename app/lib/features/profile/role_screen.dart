import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_session.dart';
import '../../core/errors.dart';
import '../../core/messenger.dart';
import '../../core/theme.dart';

/// C4 역할 선택: 사장님 / 알바생 (둘 다 가능)
class RoleScreen extends StatefulWidget {
  const RoleScreen({super.key});

  @override
  State<RoleScreen> createState() => _RoleScreenState();
}

class _RoleScreenState extends State<RoleScreen> {
  late bool _owner;
  late bool _worker;
  late final bool _editing; // 이미 역할이 있으면 '역할 바꾸기'
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final p = AppSession.instance.profile;
    _owner = p?.isOwner ?? false;
    _worker = p?.isWorker ?? false;
    _editing = _owner || _worker;
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await AppSession.instance.saveRoles(owner: _owner, worker: _worker);
      if (mounted) context.go('/home');
    } catch (e) {
      showMessage(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _editing ? AppBar() : null,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '어떻게 쓰실 건가요?',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.4),
              ),
              const SizedBox(height: 8),
              const Text(
                '둘 다 골라도 돼요. 나중에 내 정보에서 언제든 바꿀 수 있어요.',
                style: TextStyle(fontSize: 15, height: 1.6, color: AppColors.sub),
              ),
              const SizedBox(height: 28),
              _RoleCard(
                selected: _owner,
                icon: Icons.storefront_outlined,
                title: '사장님',
                sub: '무인매장을 운영해요',
                points: const ['동네 알바 공고 올리기', '근무 사진·체크리스트 확인', '월별 근무 시간 합계'],
                onTap: () => setState(() => _owner = !_owner),
              ),
              const SizedBox(height: 14),
              _RoleCard(
                selected: _worker,
                icon: Icons.person_outline,
                title: '알바생',
                sub: '집 근처에서 일하고 싶어요',
                points: const ['내 동네 1km 안 공고 보기', '하루 1시간, 시간 자유 공고도 있어요', '근무할수록 평점이 쌓여요'],
                onTap: () => setState(() => _worker = !_worker),
              ),
              const Spacer(),
              FilledButton(
                onPressed: (_busy || (!_owner && !_worker)) ? null : _save,
                child: Text(_editing ? '저장' : '다음'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.sub,
    required this.points,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String sub;
  final List<String> points;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.brandSoft : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: selected ? AppColors.brand : AppColors.line, width: selected ? 2 : 1.5),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: selected ? AppColors.brand : const Color(0xFFF1F3F6),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(icon, color: selected ? Colors.white : AppColors.sub, size: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text(sub, style: const TextStyle(fontSize: 14, color: AppColors.sub)),
                        ],
                      ),
                    ),
                    Icon(
                      selected ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: selected ? AppColors.brand : const Color(0xFFCDD2D9),
                      size: 26,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.only(left: 62),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final p in points)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(p, style: const TextStyle(fontSize: 14, color: AppColors.ink2)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
