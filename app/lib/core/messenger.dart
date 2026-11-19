import 'package:material_ui/material_ui.dart';

/// 화면이 바뀌어도(예: 탈퇴 후 로그인 화면) 안내 문구를 띄울 수 있도록 앱 전체에 하나만 둡니다.
final rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

void showMessage(String text) {
  rootMessengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}
