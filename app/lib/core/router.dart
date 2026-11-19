import 'package:go_router/go_router.dart';

import '../features/auth/login_screen.dart';
import '../features/home/home_screen.dart';
import '../features/neighborhood/neighborhood_screen.dart';
import '../features/profile/onboarding_screen.dart';
import '../features/profile/role_screen.dart';
import '../features/splash/splash_screen.dart';
import 'app_session.dart';
import 'models.dart';

/// 지금 상태에서 반드시 거쳐야 하는 화면 (없으면 null = 자유롭게 이동 가능)
///   로딩 → 로그인 → 처음 설정 → 역할 선택 → (알바생 모드면) 동네 인증 → 홈
String? gateLocation({
  required bool loading,
  required bool signedIn,
  required Profile? profile,
  required AppMode mode,
  required Neighborhood? neighborhood,
  required DateTime now,
}) {
  if (loading) return '/splash';
  if (!signedIn) return '/login';
  if (profile == null) return '/splash'; // 불러오기 실패 → 다시 시도 화면
  if (profile.onboardedAt == null) return '/onboarding';
  if (!profile.isOwner && !profile.isWorker) return '/role';
  if (mode == AppMode.worker && !(neighborhood?.isValidAt(now) ?? false)) return '/neighborhood';
  return null;
}

GoRouter buildRouter(AppSession session) {
  // 다 끝난 사용자가 이 화면들에 있으면 홈으로 보냄
  const entryScreens = {'/splash', '/login', '/onboarding'};

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: session,
    redirect: (context, state) {
      final here = state.matchedLocation;
      final gate = gateLocation(
        loading: session.loading,
        signedIn: session.signedIn,
        profile: session.profile,
        mode: session.mode,
        neighborhood: session.neighborhood,
        now: DateTime.now(),
      );
      if (gate != null) return here == gate ? null : gate;
      if (entryScreens.contains(here)) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingScreen()),
      GoRoute(path: '/role', builder: (context, state) => const RoleScreen()),
      GoRoute(path: '/neighborhood', builder: (context, state) => const NeighborhoodScreen()),
      GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
    ],
  );
}
