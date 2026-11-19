import 'package:material_ui/material_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme.dart';

/// 우리 앱 심볼: 파란 지도 핀 안의 가게 (시안 로그인 화면과 같은 모양)
class BrandSymbol extends StatelessWidget {
  const BrandSymbol({super.key, this.size = 76, this.color = AppColors.brand});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final hex = (color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return SvgPicture.string(
      _svg('#$hex'),
      width: size,
      height: size,
      semanticsLabel: '우리동네무인알바',
    );
  }

  static String _svg(String fill) => '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 72 72">
  <path d="M36 67s-23-19.4-23-37.5a23 23 0 0 1 46 0C59 47.6 36 67 36 67z" fill="$fill"/>
  <g fill="none" stroke="#FFFFFF" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">
    <path d="M24 26l3.5-7h17l3.5 7"/>
    <path d="M24 26a4 4 0 0 0 8 0a4 4 0 0 0 8 0a4 4 0 0 0 8 0"/>
    <path d="M26.5 31v9.5h19V31"/>
    <path d="M33 40.5v-5h6v5"/>
  </g>
</svg>''';
}
