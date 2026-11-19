import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_session.dart';
import '../../core/errors.dart';
import '../../core/messenger.dart';
import '../../core/models.dart';
import '../../core/theme.dart';

/// C6 내 정보: 프로필, 모드 전환, 동네 인증, 역할 바꾸기, 로그아웃, 회원 탈퇴
class MyInfoView extends StatefulWidget {
  const MyInfoView({super.key});

  @override
  State<MyInfoView> createState() => _MyInfoViewState();
}

class _MyInfoViewState extends State<MyInfoView> {
  bool _busy = false;

  Future<bool> _confirm(String title, String body, String action, {bool danger = false}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: danger ? TextButton.styleFrom(foregroundColor: AppColors.danger) : null,
            child: Text(action),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _signOut() async {
    if (!await _confirm('로그아웃', '로그아웃할까요?', '로그아웃')) return;
    await AppSession.instance.signOut();
  }

  Future<void> _deleteAccount() async {
    final ok = await _confirm(
      '회원 탈퇴',
      '탈퇴하면 프로필, 동네 인증, 내가 등록한 매장과 공고가 모두 지워지고 되돌릴 수 없어요.\n'
          '근무 중인 매칭은 종료돼요.',
      '탈퇴하기',
      danger: true,
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await AppSession.instance.deleteAccount();
      showMessage('탈퇴했어요. 그동안 이용해 주셔서 고마워요.');
    } catch (e) {
      showMessage(friendlyError(e));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = AppSession.instance;
    final p = session.profile;
    if (p == null) return const SizedBox.shrink();
    final n = session.neighborhood;
    final avatar = p.avatarUrl?.replaceFirst('http://', 'https://');
    final roles = [if (p.isOwner) '사장님', if (p.isWorker) '알바생'].join(' · ');

    return AbsorbPointer(
      absorbing: _busy,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          const Text('내 정보', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 20),
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.brandSoft,
                foregroundImage: avatar == null ? null : NetworkImage(avatar),
                child: Text(
                  p.nickname.isEmpty ? '?' : p.nickname.characters.first,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.brand),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.nickname, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(roles, style: const TextStyle(fontSize: 14, color: AppColors.sub)),
                  ],
                ),
              ),
            ],
          ),
          if (p.isOwner && p.isWorker) ...[
            const SizedBox(height: 20),
            SegmentedButton<AppMode>(
              segments: const [
                ButtonSegment(value: AppMode.worker, label: Text('알바생으로 보기'), icon: Icon(Icons.person_outline)),
                ButtonSegment(value: AppMode.owner, label: Text('사장님으로 보기'), icon: Icon(Icons.storefront_outlined)),
              ],
              selected: {session.mode},
              onSelectionChanged: (s) => session.switchMode(s.first),
            ),
          ],
          if (p.isWorker) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.line),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.place_outlined, color: AppColors.brand),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          n == null ? '동네 인증 전' : n.dong,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          n == null
                              ? '인증하면 근처 공고를 볼 수 있어요'
                              : n.isValid
                                  ? '인증 ${n.daysLeft}일 남음'
                                  : '인증 기간이 끝났어요',
                          style: const TextStyle(fontSize: 13, color: AppColors.meta),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.push('/neighborhood'),
                    child: Text(n == null ? '인증하기' : '다시 인증'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.swap_horiz),
            title: const Text('역할 바꾸기'),
            onTap: () => context.push('/role'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.logout),
            title: const Text('로그아웃'),
            onTap: _signOut,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_off_outlined, color: AppColors.danger),
            title: const Text('회원 탈퇴', style: TextStyle(color: AppColors.danger)),
            trailing: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : null,
            onTap: _deleteAccount,
          ),
        ],
      ),
    );
  }
}
