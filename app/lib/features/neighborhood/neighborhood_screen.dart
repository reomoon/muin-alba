import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_session.dart';
import '../../core/env.dart';
import '../../core/errors.dart';
import '../../core/messenger.dart';
import '../../core/models.dart';
import '../../core/theme.dart';

/// W1 동네 인증: 현재 위치 → "역삼1동 맞나요?" → 인증 (반경 1km 공고 기준)
class NeighborhoodScreen extends StatefulWidget {
  const NeighborhoodScreen({super.key});

  @override
  State<NeighborhoodScreen> createState() => _NeighborhoodScreenState();
}

enum _Phase { locating, checking, ready, saving, error }

class _NeighborhoodScreenState extends State<NeighborhoodScreen> {
  _Phase _phase = _Phase.locating;
  Position? _position;
  RegionCheck? _region;
  String? _error;
  bool _errorOpensSettings = false;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  Future<void> _locate() async {
    setState(() {
      _phase = _Phase.locating;
      _error = null;
      _region = null;
    });
    try {
      final position = await _currentPosition();
      if (!mounted) return;
      setState(() {
        _position = position;
        _phase = _Phase.checking;
      });
      final region = await AppSession.instance.checkNeighborhood(
        position.latitude,
        position.longitude,
        confirm: false,
      );
      if (!mounted) return;
      setState(() {
        _region = region;
        _phase = _Phase.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = friendlyError(e);
        _errorOpensSettings = e is UserFacingError && e.openSettings;
      });
    }
  }

  Future<Position> _currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const UserFacingError('휴대폰 위치(GPS)가 꺼져 있어요. 켜고 다시 시도해 주세요.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const UserFacingError('위치 권한을 허용해야 동네를 인증할 수 있어요.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const UserFacingError('위치 권한이 꺼져 있어요. 설정에서 위치 권한을 허용해 주세요.', openSettings: true);
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
    // 가짜 위치 앱 차단 (개발 중 에뮬레이터 테스트는 허용)
    if (position.isMocked && kReleaseMode) {
      throw const UserFacingError('가짜 위치 앱이 켜져 있으면 인증할 수 없어요.');
    }
    return position;
  }

  Future<void> _confirm() async {
    final position = _position;
    if (position == null) return;
    setState(() => _phase = _Phase.saving);
    try {
      final region = await AppSession.instance.checkNeighborhood(
        position.latitude,
        position.longitude,
        confirm: true,
      );
      showMessage('${region.dong} 인증을 마쳤어요');
      if (mounted) context.go('/home');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = friendlyError(e);
        _errorOpensSettings = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = AppSession.instance;
    final profile = session.profile;
    final required = !(session.neighborhood?.isValid ?? false); // 인증이 없거나 만료 → 꼭 해야 함
    final canUseAsOwner = required && (profile?.isOwner ?? false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('동네 인증'),
        automaticallyImplyLeading: false,
        leading: required
            ? null
            : IconButton(
                tooltip: '뒤로',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
              ),
        actions: [
          if (required)
            TextButton(onPressed: session.signOut, child: const Text('로그아웃')),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _MapArea(position: _position)),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [BoxShadow(color: Color(0x14111827), blurRadius: 16, offset: Offset(0, -4))],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ..._statusContent(),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.verified_user_outlined, size: 20, color: AppColors.ink2),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '정확한 집 위치는 사장님께 보이지 않아요. 동네 이름만 보여요.',
                            style: TextStyle(fontSize: 13, height: 1.55, color: AppColors.ink2),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  ..._actions(),
                  if (canUseAsOwner)
                    Center(
                      child: TextButton(
                        onPressed: () {
                          session.switchMode(AppMode.owner);
                          context.go('/home');
                        },
                        child: const Text('지금은 사장님으로 쓰기'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _statusContent() {
    switch (_phase) {
      case _Phase.locating:
      case _Phase.checking:
        return [
          Text(
            _phase == _Phase.locating ? '현재 위치를 찾고 있어요' : '동네 이름을 확인하고 있어요',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ];
      case _Phase.ready:
      case _Phase.saving:
        final region = _region!;
        return [
          const Text('현재 위치', style: TextStyle(fontSize: 13, color: AppColors.meta)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(region.dong, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Expanded(child: Text(region.sigungu, style: const TextStyle(fontSize: 15, color: AppColors.sub))),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '이 위치에서 반경 1km 안의 공고를 보여 드려요.\n'
            '인증은 ${AppSession.instance.neighborhoodValidDays}일 동안 유지돼요.',
            style: const TextStyle(fontSize: 14, height: 1.6, color: AppColors.sub),
          ),
        ];
      case _Phase.error:
        return [
          const Text('동네를 확인하지 못했어요', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(_error ?? '', style: const TextStyle(fontSize: 14, height: 1.6, color: AppColors.sub)),
        ];
    }
  }

  List<Widget> _actions() {
    switch (_phase) {
      case _Phase.ready:
        return [
          FilledButton(onPressed: _confirm, child: Text('${_region!.dong}으로 인증하기')),
          const SizedBox(height: 4),
          Center(child: TextButton(onPressed: _locate, child: const Text('위치가 다르게 나와요'))),
        ];
      case _Phase.saving:
        return [
          const FilledButton(
            onPressed: null,
            child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
          ),
        ];
      case _Phase.error:
        return [
          if (_errorOpensSettings)
            FilledButton(
              onPressed: () async {
                await Geolocator.openAppSettings();
              },
              child: const Text('설정 열기'),
            )
          else
            FilledButton(onPressed: _locate, child: const Text('다시 시도')),
        ];
      case _Phase.locating:
      case _Phase.checking:
        return const [];
    }
  }
}

/// 지도: 내 위치 + 반경 1km. 지도 키가 없으면 안내 상자.
class _MapArea extends StatelessWidget {
  const _MapArea({required this.position});

  final Position? position;

  @override
  Widget build(BuildContext context) {
    final p = position;
    if (!Env.hasNaverMap) {
      return const _MapPlaceholder(text: 'app/.env 에 NAVER_MAP_CLIENT_ID 를 넣으면\n여기에 지도가 보여요');
    }
    if (p == null) {
      return const _MapPlaceholder(text: '위치를 찾는 중이에요');
    }
    final here = NLatLng(p.latitude, p.longitude);
    return NaverMap(
      key: ValueKey('${p.latitude},${p.longitude}'),
      options: NaverMapViewOptions(
        initialCameraPosition: NCameraPosition(target: here, zoom: 14),
      ),
      onMapReady: (controller) {
        controller.addOverlay(NCircleOverlay(
          id: 'radius',
          center: here,
          radius: 1000,
          color: AppColors.brand.withValues(alpha: 0.08),
          outlineColor: AppColors.brand,
          outlineWidth: 1.5,
        ));
        controller.addOverlay(NMarker(id: 'me', position: here));
      },
    );
  }
}

class _MapPlaceholder extends StatelessWidget {
  const _MapPlaceholder({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEEF1F5),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.sub, height: 1.6)),
    );
  }
}
