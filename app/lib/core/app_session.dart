import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';
import 'models.dart';

/// 로그인 상태 + 내 프로필 + 내 동네 인증 + 지금 모드(알바생/사장님)를 들고 있는 곳.
/// 값이 바뀌면 notifyListeners() → 화면과 라우터가 다시 그려집니다.
class AppSession extends ChangeNotifier {
  AppSession(this._client) {
    _authSub = _client.auth.onAuthStateChange.listen((state) {
      if (state.event != AuthChangeEvent.tokenRefreshed) reload();
    });
    reload();
  }

  static late AppSession instance;

  final SupabaseClient _client;
  late final StreamSubscription<AuthState> _authSub;

  bool loading = true;
  String? loadError;
  Profile? profile;
  Neighborhood? neighborhood;
  int neighborhoodValidDays = 30;
  AppMode mode = AppMode.worker;

  bool get signedIn => _client.auth.currentSession != null;
  String? get userId => _client.auth.currentUser?.id;

  int _reloadSeq = 0;

  /// 서버에서 내 정보를 다시 읽어 옵니다.
  Future<void> reload() async {
    final seq = ++_reloadSeq;
    if (!signedIn) {
      profile = null;
      neighborhood = null;
      loadError = null;
      loading = false;
      notifyListeners();
      return;
    }

    loading = profile == null; // 처음 한 번만 로딩 화면
    loadError = null;
    notifyListeners();

    try {
      final uid = userId!;
      final rows = await Future.wait([
        _client.from('profiles').select().eq('id', uid).maybeSingle(),
        _client
            .from('worker_neighborhoods')
            .select('region_code, region_name, verified_at')
            .eq('user_id', uid)
            .maybeSingle(),
        _client.from('app_config').select('value').eq('key', 'neighborhood_valid_days').maybeSingle(),
      ]);
      if (seq != _reloadSeq) return;

      final p = rows[0];
      final n = rows[1];
      final c = rows[2];
      if (c != null) neighborhoodValidDays = (c['value'] as num).toInt();

      profile = p == null ? null : Profile.fromMap(p);
      if (n == null) {
        neighborhood = null;
      } else {
        final verifiedAt = DateTime.parse(n['verified_at'] as String);
        neighborhood = Neighborhood(
          regionCode: n['region_code'] as String,
          regionName: n['region_name'] as String,
          verifiedAt: verifiedAt,
          expiresAt: verifiedAt.add(Duration(days: neighborhoodValidDays)),
        );
      }
      if (profile == null) {
        loadError = '프로필을 찾지 못했어요. 다시 시도해 주세요.';
      } else {
        _fixMode();
      }
    } catch (e) {
      if (seq != _reloadSeq) return;
      debugPrint('AppSession.reload failed: $e');
      loadError = '내 정보를 불러오지 못했어요. 인터넷 연결을 확인해 주세요.';
    }
    loading = false;
    notifyListeners();
  }

  /// 역할에 없는 모드면 있는 쪽으로 맞춤
  void _fixMode() {
    final p = profile!;
    if (mode == AppMode.worker && !p.isWorker && p.isOwner) mode = AppMode.owner;
    if (mode == AppMode.owner && !p.isOwner && p.isWorker) mode = AppMode.worker;
  }

  void switchMode(AppMode next) {
    if (mode == next) return;
    mode = next;
    notifyListeners();
  }

  // ── 로그인 ─────────────────────────────────────────────────────────
  Future<void> signInWith(OAuthProvider provider) async {
    await _client.auth.signInWithOAuth(
      provider,
      redirectTo: Env.authRedirect,
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  }

  Future<void> signOut() => _client.auth.signOut();

  // ── 처음 설정 (닉네임 + 약관 동의) ─────────────────────────────────
  Future<void> completeOnboarding({required String nickname, required bool marketing}) async {
    final consents = [
      {'consent_type': 'terms', 'version': Env.termsVersion},
      {'consent_type': 'privacy', 'version': Env.termsVersion},
      {'consent_type': 'location', 'version': Env.termsVersion},
      if (marketing) {'consent_type': 'marketing', 'version': Env.termsVersion},
    ];
    try {
      await _client.from('user_consents').insert(consents);
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow; // 이미 동의한 기록이 있으면 그대로 진행
    }
    await _client.from('profiles').update({
      'nickname': nickname,
      'onboarded_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', userId!);
    await reload();
  }

  // ── 역할 ───────────────────────────────────────────────────────────
  Future<void> saveRoles({required bool owner, required bool worker}) async {
    await _client.from('profiles').update({'is_owner': owner, 'is_worker': worker}).eq('id', userId!);
    mode = worker ? AppMode.worker : AppMode.owner;
    await reload();
  }

  // ── 동네 인증 (Edge Function 'neighborhood') ───────────────────────
  /// confirm=false: 이 위치의 동네만 확인 / confirm=true: 인증 저장
  Future<RegionCheck> checkNeighborhood(double lat, double lng, {required bool confirm}) async {
    final res = await _client.functions.invoke(
      'neighborhood',
      body: {'lat': lat, 'lng': lng, 'confirm': confirm},
    );
    final data = Map<String, dynamic>.from(res.data as Map);
    final region = RegionCheck.fromMap(Map<String, dynamic>.from(data['region'] as Map));
    if (confirm) await reload();
    return region;
  }

  // ── 회원 탈퇴 (Edge Function 'delete-account') ─────────────────────
  Future<void> deleteAccount() async {
    await _client.functions.invoke('delete-account');
    // 서버에서 계정이 지워졌으니 이 기기의 로그인 정보만 지웁니다.
    await _client.auth.signOut(scope: SignOutScope.local);
  }

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }
}
