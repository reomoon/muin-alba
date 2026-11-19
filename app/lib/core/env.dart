/// 빌드할 때 `--dart-define-from-file=.env` 로 넣는 값들.
/// 실제 값은 app/.env 에만 적고 git 에는 올리지 않습니다 (예시: app/.env.example).
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const naverMapClientId = String.fromEnvironment('NAVER_MAP_CLIENT_ID');

  static bool get hasSupabase => supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
  static bool get hasNaverMap => naverMapClientId.isNotEmpty;

  /// 소셜 로그인 후 앱으로 돌아오는 주소.
  /// AndroidManifest 의 intent-filter, Supabase Redirect URLs 와 같아야 합니다.
  static const authRedirect = 'com.muinalba.app://login-callback';

  /// 약관 버전 (약관이 바뀌면 올리고 다시 동의받음)
  static const termsVersion = '2026-11-18';
}
