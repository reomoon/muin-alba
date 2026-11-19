import 'package:material_ui/material_ui.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_session.dart';
import 'core/env.dart';
import 'core/messenger.dart';
import 'core/router.dart';
import 'core/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!Env.hasSupabase) {
    runApp(const _MissingEnvApp());
    return;
  }

  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabasePublishableKey,
  );

  if (Env.hasNaverMap) {
    await FlutterNaverMap().init(
      clientId: Env.naverMapClientId,
      onAuthFailed: (ex) => debugPrint('네이버 지도 인증 실패: $ex'),
    );
  }

  AppSession.instance = AppSession(Supabase.instance.client);
  runApp(MuinAlbaApp(router: buildRouter(AppSession.instance)));
}

class MuinAlbaApp extends StatelessWidget {
  const MuinAlbaApp({super.key, required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '우리동네무인알바',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: router,
      scaffoldMessengerKey: rootMessengerKey,
      locale: const Locale('ko'),
      supportedLocales: const [Locale('ko')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
    );
  }
}

/// app/.env 가 없거나 비어 있을 때 보여 주는 안내
class _MissingEnvApp extends StatelessWidget {
  const _MissingEnvApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'app/.env 에 SUPABASE_URL 과 SUPABASE_PUBLISHABLE_KEY 를 넣고\n'
              'VS Code 실행 버튼(우리동네무인알바)으로 다시 실행해 주세요.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
