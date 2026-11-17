-- =====================================================================
-- 1단계 ⑥ 기준 데이터 (운영에도 필요한 값이라 seed 가 아니라 마이그레이션에 둡니다)
-- =====================================================================

-- ── 설정값 ── 바꿀 때: Supabase 대시보드 > Table Editor > app_config 에서 value 수정
insert into public.app_config (key, value, description) values
  ('paywall_enabled',         'false', '유료 기능 잠금 사용 여부. 베타 동안 false (모든 기능 열림)'),
  ('free_store_limit',        '1',     '구독 없이 공고·매칭을 쓸 수 있는 매장 수'),
  ('min_hourly_wage',         '10320', '최저시급(원). 2026년 기준. 매년 1월 1일에 새 금액으로 바꿔야 함'),
  ('neighborhood_radius_m',   '1000',  '알바생 인증 위치에서 공고를 보여 주는 반경(m)'),
  ('neighborhood_valid_days', '30',    '동네 인증 유효기간(일). 지나면 다시 인증'),
  ('checkin_radius_m',        '150',   '근무 시작·종료를 인정하는 매장 반경(m). 실내 GPS 오차 감안'),
  ('fixed_start_grace_min',   '30',    '시간 지정 공고의 미출근 판정 유예(분)'),
  ('photo_retention_days',    '90',    '근무 사진 보관 기간(일). 지나면 자동 삭제')
on conflict (key) do nothing;

-- ── 플랜별 기능 (기능 잠금 기준표) ──
-- free  : 공고·매칭만 (매장 free_store_limit 곳까지)
-- basic : 매장당 월 구독. 근무 인증·사진·체크리스트·근무 기록·리포트
insert into public.plan_features (plan, feature_key) values
  ('free',  'job_posting'),
  ('basic', 'job_posting'),
  ('basic', 'shift_tracking'),
  ('basic', 'photo_verification'),
  ('basic', 'checklist'),
  ('basic', 'work_history'),
  ('basic', 'monthly_report')
on conflict do nothing;

-- ── 업종별 기본 체크리스트 ──
insert into public.checklist_templates (category, items) values
  ('unmanned_cafe', '[
    {"title": "테이블·의자 닦기"},
    {"title": "바닥 쓸고 물걸레질"},
    {"title": "쓰레기통 비우기·분리수거"},
    {"title": "커피머신 주변 정리, 원두 보충"},
    {"title": "컵·빨대·냅킨 보충"},
    {"title": "키오스크·결제기 작동 확인"}
  ]'),
  ('ice_cream', '[
    {"title": "냉동고 온도·성에 확인"},
    {"title": "냉동고 유리문 닦기"},
    {"title": "진열 정리 (앞으로 당겨 채우기)"},
    {"title": "부족한 상품 보충", "requires_photo": true},
    {"title": "바닥 청소"},
    {"title": "쓰레기통 비우기"},
    {"title": "키오스크·결제기 작동 확인"}
  ]'),
  ('study_cafe', '[
    {"title": "좌석·책상 닦기, 두고 간 물건 확인"},
    {"title": "바닥 청소"},
    {"title": "휴게 공간·음료 코너 정리"},
    {"title": "쓰레기통 비우기·분리수거"},
    {"title": "화장실 청소·휴지 보충"},
    {"title": "출입 키오스크·좌석 배정기 확인"},
    {"title": "냉난방·조명 상태 확인"}
  ]'),
  ('laundry', '[
    {"title": "세탁기·건조기 안 이물질 확인"},
    {"title": "건조기 먼지 필터 청소"},
    {"title": "세제 자판기 잔량 확인"},
    {"title": "바닥·테이블 청소"},
    {"title": "쓰레기통 비우기"},
    {"title": "동전교환기·결제기 작동 확인"}
  ]'),
  ('convenience', '[
    {"title": "냉장·냉동 진열대 온도 확인"},
    {"title": "유통기한 임박 상품 확인"},
    {"title": "진열 정리, 부족한 상품 보충", "requires_photo": true},
    {"title": "바닥 청소"},
    {"title": "쓰레기통 비우기"},
    {"title": "키오스크·결제기 작동 확인"}
  ]'),
  ('photo_studio', '[
    {"title": "부스 안 소품 정리"},
    {"title": "거울·카메라 렌즈 닦기"},
    {"title": "인화지·잉크 잔량 확인"},
    {"title": "바닥 청소"},
    {"title": "쓰레기통 비우기"},
    {"title": "키오스크 작동 확인"}
  ]'),
  ('other', '[
    {"title": "바닥 청소"},
    {"title": "쓰레기통 비우기"},
    {"title": "진열·비품 정리"},
    {"title": "키오스크·결제기 작동 확인"}
  ]')
on conflict (category) do nothing;
