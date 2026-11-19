import 'package:material_ui/material_ui.dart';

import '../../core/app_session.dart';
import '../../core/theme.dart';
import '../../core/widgets/brand_symbol.dart';

/// C1 스플래시: 로그인·내 정보를 확인하는 동안 보이는 화면
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = AppSession.instance;
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: session,
          builder: (context, _) {
            final error = session.loadError;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BrandSymbol(size: 88),
                    const SizedBox(height: 16),
                    const Text('우리동네무인알바', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 28),
                    if (error == null)
                      const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3))
                    else ...[
                      Text(error, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.sub)),
                      const SizedBox(height: 16),
                      FilledButton(onPressed: session.reload, child: const Text('다시 시도')),
                      const SizedBox(height: 8),
                      TextButton(onPressed: session.signOut, child: const Text('로그아웃')),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
