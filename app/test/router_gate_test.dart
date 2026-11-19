import 'package:flutter_test/flutter_test.dart';
import 'package:muinalba/core/models.dart';
import 'package:muinalba/core/router.dart';

void main() {
  final now = DateTime(2026, 11, 18, 12);

  Profile profile({bool onboarded = true, bool owner = false, bool worker = true}) => Profile(
        id: 'u1',
        nickname: '테스트',
        isOwner: owner,
        isWorker: worker,
        onboardedAt: onboarded ? now.subtract(const Duration(days: 1)) : null,
      );

  Neighborhood neighborhood({required int daysAgo}) {
    final verifiedAt = now.subtract(Duration(days: daysAgo));
    return Neighborhood(
      regionCode: '1168064000',
      regionName: '서울특별시 강남구 역삼1동',
      verifiedAt: verifiedAt,
      expiresAt: verifiedAt.add(const Duration(days: 30)),
    );
  }

  String? gate({
    bool loading = false,
    bool signedIn = true,
    Profile? p,
    AppMode mode = AppMode.worker,
    Neighborhood? n,
  }) =>
      gateLocation(loading: loading, signedIn: signedIn, profile: p, mode: mode, neighborhood: n, now: now);

  test('로딩 중이면 스플래시', () => expect(gate(loading: true), '/splash'));
  test('로그인 전이면 로그인', () => expect(gate(signedIn: false), '/login'));
  test('처음 설정 전이면 처음 설정', () => expect(gate(p: profile(onboarded: false)), '/onboarding'));
  test('역할이 없으면 역할 선택', () => expect(gate(p: profile(worker: false)), '/role'));
  test('알바생인데 동네 인증이 없으면 동네 인증', () => expect(gate(p: profile()), '/neighborhood'));
  test('동네 인증이 만료되면 다시 동네 인증', () => expect(gate(p: profile(), n: neighborhood(daysAgo: 31)), '/neighborhood'));
  test('동네 인증이 유효하면 자유', () => expect(gate(p: profile(), n: neighborhood(daysAgo: 3)), isNull));
  test('사장님 모드는 동네 인증 없이 자유',
      () => expect(gate(p: profile(owner: true, worker: false), mode: AppMode.owner), isNull));
  test('동네 이름 줄이기', () => expect(neighborhood(daysAgo: 0).dong, '역삼1동'));
}
