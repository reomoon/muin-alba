import 'package:supabase_flutter/supabase_flutter.dart';

/// 사용자에게 그대로 보여 줄 수 있는 오류
class UserFacingError implements Exception {
  const UserFacingError(this.message, {this.openSettings = false});
  final String message;
  final bool openSettings; // 설정 화면으로 보내야 하는 경우 (위치 권한 등)

  @override
  String toString() => message;
}

/// 어떤 오류든 사용자에게 보여 줄 문장으로 바꿉니다.
String friendlyError(Object e) {
  if (e is UserFacingError) return e.message;
  if (e is FunctionException) {
    final d = e.details;
    if (d is Map && d['error'] is String) return d['error'] as String;
    if (e.status == 404) return '서버 기능이 아직 배포되지 않았어요.';
    return '서버에서 문제가 생겼어요. (${e.status})';
  }
  if (e is AuthException) return '로그인 문제: ${e.message}';
  if (e is PostgrestException) return '저장하지 못했어요. (${e.message})';
  return '문제가 생겼어요. 인터넷 연결을 확인하고 다시 시도해 주세요.';
}
