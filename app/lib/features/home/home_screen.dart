import 'package:material_ui/material_ui.dart';

import '../../core/app_session.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../profile/my_info_view.dart';

/// 홈: 모드별 하단 탭
///   알바생: 공고 · 내 근무 · 알림 · 내 정보
///   사장님: 매장 · 근무기록 · 커뮤니티 · 알림 · 내 정보
/// 아직 만들지 않은 탭은 몇 단계에서 생기는지 안내합니다.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _Tab {
  const _Tab(this.label, this.icon, this.selectedIcon, this.body);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget body;
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  AppMode? _lastMode;

  List<_Tab> _tabsFor(AppMode mode, AppSession session) {
    if (mode == AppMode.worker) {
      return [
        _Tab('공고', Icons.work_outline, Icons.work, _JobsTab(dong: session.neighborhood?.dong)),
        const _Tab('내 근무', Icons.event_available_outlined, Icons.event_available,
            _ComingSoon(title: '내 근무', text: '확정된 근무지와 오늘 근무는\n4단계에서 만들어요')),
        const _Tab('알림', Icons.notifications_none, Icons.notifications,
            _ComingSoon(title: '알림', text: '지원·매칭·근무 알림은\n5단계에서 만들어요')),
        const _Tab('내 정보', Icons.person_outline, Icons.person, MyInfoView()),
      ];
    }
    return const [
      _Tab('매장', Icons.storefront_outlined, Icons.storefront,
          _ComingSoon(title: '내 매장', text: '매장 등록과 공고 올리기는\n3단계에서 만들어요')),
      _Tab('근무기록', Icons.event_note_outlined, Icons.event_note,
          _ComingSoon(title: '근무기록', text: '날짜별 근무와 사진 확인은\n4단계에서 만들어요')),
      _Tab('커뮤니티', Icons.groups_outlined, Icons.groups,
          _ComingSoon(title: '사장님 커뮤니티', text: '사장님 게시판은\n6단계에서 만들어요')),
      _Tab('알림', Icons.notifications_none, Icons.notifications,
          _ComingSoon(title: '알림', text: '지원 도착·근무 완료 알림은\n5단계에서 만들어요')),
      _Tab('내 정보', Icons.person_outline, Icons.person, MyInfoView()),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final session = AppSession.instance;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final mode = session.mode;
        final tabs = _tabsFor(mode, session);
        // 모드를 바꾸면 '내 정보' 탭에 그대로 머무름
        if (_lastMode != null && _lastMode != mode) _index = tabs.length - 1;
        _lastMode = mode;
        if (_index >= tabs.length) _index = 0;

        return Scaffold(
          body: SafeArea(child: tabs[_index].body),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              for (final t in tabs)
                NavigationDestination(
                  icon: Icon(t.icon),
                  selectedIcon: Icon(t.selectedIcon, color: AppColors.brand),
                  label: t.label,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _JobsTab extends StatelessWidget {
  const _JobsTab({required this.dong});

  final String? dong;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(
            children: [
              const Icon(Icons.place, color: AppColors.brand),
              const SizedBox(width: 4),
              Text(dong ?? '내 동네', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        const Expanded(
          child: _ComingSoon(title: null, text: '내 동네 1km 안의 공고 지도는\n3단계에서 만들어요'),
        ),
      ],
    );
  }
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon({required this.title, required this.text});

  final String? title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text(title!, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          ),
        Expanded(
          child: Center(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, height: 1.6, color: AppColors.meta),
            ),
          ),
        ),
      ],
    );
  }
}
