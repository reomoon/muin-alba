// 앱에서 쓰는 데이터 모양 (DB 테이블과 같은 이름)

enum AppMode { worker, owner }

class Profile {
  const Profile({
    required this.id,
    required this.nickname,
    required this.isOwner,
    required this.isWorker,
    this.avatarUrl,
    this.onboardedAt,
    this.ratingAvg = 0,
    this.ratingCount = 0,
  });

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        id: m['id'] as String,
        nickname: (m['nickname'] as String?) ?? '',
        avatarUrl: m['avatar_url'] as String?,
        isOwner: (m['is_owner'] as bool?) ?? false,
        isWorker: (m['is_worker'] as bool?) ?? false,
        onboardedAt: m['onboarded_at'] == null ? null : DateTime.parse(m['onboarded_at'] as String),
        ratingAvg: (m['rating_avg'] as num?)?.toDouble() ?? 0,
        ratingCount: (m['rating_count'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final String nickname;
  final String? avatarUrl;
  final bool isOwner;
  final bool isWorker;
  final DateTime? onboardedAt;
  final double ratingAvg;
  final int ratingCount;
}

class Neighborhood {
  const Neighborhood({
    required this.regionCode,
    required this.regionName,
    required this.verifiedAt,
    required this.expiresAt,
  });

  final String regionCode;
  final String regionName; // 예: 서울특별시 강남구 역삼1동
  final DateTime verifiedAt;
  final DateTime expiresAt;

  bool isValidAt(DateTime now) => now.isBefore(expiresAt);
  bool get isValid => isValidAt(DateTime.now());

  /// '서울특별시 강남구 역삼1동' → '역삼1동'
  String get dong => regionName.split(' ').last;

  int get daysLeft => expiresAt.difference(DateTime.now()).inDays;
}

/// Edge Function 'neighborhood' 의 동네 확인 결과
class RegionCheck {
  const RegionCheck({required this.name, required this.dong, required this.sigungu});

  factory RegionCheck.fromMap(Map<String, dynamic> m) => RegionCheck(
        name: m['name'] as String,
        dong: m['dong'] as String,
        sigungu: m['sigungu'] as String,
      );

  final String name;
  final String dong;
  final String sigungu;
}
