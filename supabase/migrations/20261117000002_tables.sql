-- =====================================================================
-- 1단계 ② 테이블
--  · 시각은 timestamptz(UTC 저장). 근무일(work_date)은 한국 시간 기준 날짜.
--  · 좌표는 geography(Point, 4326) = WGS84 경위도 (카카오·네이버 지도와 같은 좌표계)
--  · 지원 수락, 근무 시작·종료 같은 상태 변경은 3·4단계의 RPC 함수로만 합니다.
-- =====================================================================

-- ── 열거형 ───────────────────────────────────────────────────────────
create type public.store_category as enum (
  'unmanned_cafe',  -- 무인카페
  'ice_cream',      -- 아이스크림 할인점
  'study_cafe',     -- 스터디카페
  'laundry',        -- 코인세탁
  'convenience',    -- 무인 편의점·밀키트
  'photo_studio',   -- 셀프 사진관
  'other'           -- 기타
);
create type public.job_time_type       as enum ('flexible', 'fixed');                -- 시간 자유(협의) / 시간 지정
create type public.job_post_status     as enum ('open', 'matched', 'closed');        -- 모집 중 / 매칭 완료 / 마감
create type public.application_status  as enum ('pending', 'accepted', 'rejected', 'withdrawn');
create type public.assignment_status   as enum ('active', 'ended');                  -- 근무 중 / 근무 끝
create type public.shift_status        as enum ('in_progress', 'completed', 'missed');
create type public.shift_photo_kind    as enum ('before', 'after', 'item', 'issue'); -- 청소 전 / 후 / 체크 항목 / 특이사항
create type public.notification_type   as enum (
  'application_received',  -- 지원 도착   → 사장님
  'match_confirmed',       -- 매칭 확정   → 알바
  'application_rejected',  -- 지원 거절   → 알바
  'shift_completed',       -- 근무 완료   → 사장님
  'shift_missed',          -- 미출근      → 사장님·알바
  'community_comment'      -- 내 글 댓글  → 사장님
);
create type public.community_category  as enum ('question', 'tip', 'free');          -- 질문 / 팁 / 자유
create type public.report_target       as enum ('post', 'comment', 'user');
create type public.subscription_plan   as enum ('free', 'basic');
create type public.subscription_status as enum ('trialing', 'active', 'past_due', 'canceled');
create type public.consent_type        as enum ('terms', 'privacy', 'location', 'marketing');
create type public.location_log_action as enum ('collect', 'use', 'provide');        -- 수집 / 이용 / 제공

-- ── 공통 트리거 함수 ─────────────────────────────────────────────────
create or replace function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ── 설정값 (반경·보관기간·유료 잠금 등. 앱 배포 없이 값만 바꿀 수 있음) ──
create table public.app_config (
  key         text primary key,
  value       jsonb not null,
  description text not null default '',
  updated_at  timestamptz not null default now()
);

-- ── 사용자 ───────────────────────────────────────────────────────────
-- 프로필 카드: 로그인한 사용자 누구나 볼 수 있는 정보만 둡니다.
create table public.profiles (
  id               uuid primary key references auth.users (id) on delete cascade,
  nickname         text not null default '' check (char_length(nickname) <= 20),
  avatar_url       text,
  bio              text not null default '' check (char_length(bio) <= 300),
  is_owner         boolean not null default false,   -- 사장님 역할 사용
  is_worker        boolean not null default false,   -- 알바생 역할 사용 (둘 다 가능)
  onboarded_at     timestamptz,                      -- 닉네임·약관 동의 완료 시각
  -- 아래 4개는 트리거가 계산합니다 (사용자가 직접 수정 불가)
  rating_avg       numeric(2, 1) not null default 0,
  rating_count     integer not null default 0,
  completed_shifts integer not null default 0,
  missed_shifts    integer not null default 0,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

-- 약관·위치정보 동의 기록 (위치정보법상 동의 증빙)
create table public.user_consents (
  user_id      uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  consent_type public.consent_type not null,
  version      text not null,                 -- 약관 버전 (예: '2026-12-01')
  agreed_at    timestamptz not null default now(),
  withdrawn_at timestamptz,                   -- 동의 철회 시각
  primary key (user_id, consent_type, version)
);

-- 연락처: 본인과 '지금 매칭된 상대'만 볼 수 있습니다.
create table public.profile_private (
  user_id    uuid primary key default auth.uid() references public.profiles (id) on delete cascade,
  phone      text check (phone ~ '^01[016789][0-9]{7,8}$'),   -- 숫자만 (예: 01012345678)
  updated_at timestamptz not null default now()
);

-- 알바생 동네 인증: 집 근처 좌표라 본인만 볼 수 있습니다. 기록은 2단계 RPC로만.
create table public.worker_neighborhoods (
  user_id     uuid primary key references public.profiles (id) on delete cascade,
  location    extensions.geography(point, 4326) not null,
  region_code text not null,   -- 행정동 코드 10자리 (카카오 로컬 API 'H' 코드)
  region_name text not null,   -- 예: '서울특별시 강남구 역삼1동'
  verified_at timestamptz not null default now()
);
create index worker_neighborhoods_location_idx on public.worker_neighborhoods using gist (location);

-- ── 매장 ─────────────────────────────────────────────────────────────
create table public.stores (
  id             uuid primary key default gen_random_uuid(),
  owner_id       uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  name           text not null check (char_length(name) between 1 and 40),
  category       public.store_category not null,
  address        text not null check (char_length(address) <= 200),
  address_detail text not null default '' check (char_length(address_detail) <= 100),
  location       extensions.geography(point, 4326) not null,
  region_code    text not null,   -- 행정동 코드 (커뮤니티 동네 필터에도 사용)
  region_name    text not null,
  contact_phone  text check (contact_phone ~ '^0[0-9]{8,11}$'),  -- 선택. 넣으면 공고에 '전화문의' 버튼 표시
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index stores_owner_idx on public.stores (owner_id);
create index stores_location_idx on public.stores using gist (location);

-- 출입 방법·비밀번호·비품 위치: 사장님과 '근무 확정된 알바'만 볼 수 있습니다.
create table public.store_private (
  store_id    uuid primary key references public.stores (id) on delete cascade,
  access_note text not null default '' check (char_length(access_note) <= 1000),
  updated_at  timestamptz not null default now()
);

-- 공고 상단에 보이는 매장 사진 (최대 5장, 'store-photos' 공개 버킷)
create table public.store_photos (
  id           uuid primary key default gen_random_uuid(),
  store_id     uuid not null references public.stores (id) on delete cascade,
  storage_path text not null unique,            -- '{store_id}/{파일명}.jpg'
  sort_order   integer not null default 0,
  created_at   timestamptz not null default now()
);
create index store_photos_store_idx on public.store_photos (store_id, sort_order);

-- 업종별 기본 체크리스트 (매장 등록 시 매장 체크리스트로 복사됨)
create table public.checklist_templates (
  category public.store_category primary key,
  items    jsonb not null check (jsonb_typeof(items) = 'array')  -- [{"title": "...", "requires_photo": false}]
);

create table public.store_checklist_items (
  id             uuid primary key default gen_random_uuid(),
  store_id       uuid not null references public.stores (id) on delete cascade,
  title          text not null check (char_length(title) between 1 and 60),
  requires_photo boolean not null default false,   -- 이 항목은 사진 필수
  sort_order     integer not null default 0,
  is_active      boolean not null default true,    -- 삭제 대신 비활성 (지난 근무 기록 보존)
  created_at     timestamptz not null default now()
);
create index store_checklist_items_store_idx on public.store_checklist_items (store_id, sort_order);

-- ── 공고 · 지원 · 매칭 ──────────────────────────────────────────────
create table public.job_posts (
  id           uuid primary key default gen_random_uuid(),
  store_id     uuid not null references public.stores (id) on delete cascade,
  title        text not null check (char_length(title) between 1 and 60),
  description  text not null default '' check (char_length(description) <= 2000),
  hourly_wage  integer not null check (hourly_wage > 0),      -- 최저시급 검사는 트리거
  work_minutes integer not null default 60 check (work_minutes between 10 and 240),
  time_type    public.job_time_type not null,
  window_start time not null,  -- 지정: 근무 시작 시각 / 자유: 가능 시간대 시작
  window_end   time,           -- 자유: 가능 시간대 끝 (시작보다 이르면 다음 날로 봄) / 지정: null
  work_days    smallint[] not null default '{1,2,3,4,5,6,7}',  -- ISO 요일 1=월 … 7=일
  start_date   date not null default ((now() at time zone 'Asia/Seoul')::date),
  end_date     date,
  status       public.job_post_status not null default 'open',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint job_posts_window_chk check (
    (time_type = 'fixed' and window_end is null)
    or (time_type = 'flexible' and window_end is not null and window_end <> window_start)
  ),
  constraint job_posts_days_chk check (
    cardinality(work_days) between 1 and 7
    and work_days <@ '{1,2,3,4,5,6,7}'::smallint[]
  ),
  constraint job_posts_dates_chk check (end_date is null or end_date >= start_date)
);
create index job_posts_store_idx on public.job_posts (store_id);
create index job_posts_open_idx on public.job_posts (store_id) where status = 'open';

-- 관심(하트) 공고
create table public.job_post_bookmarks (
  user_id     uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  job_post_id uuid not null references public.job_posts (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (user_id, job_post_id)
);
create index job_post_bookmarks_post_idx on public.job_post_bookmarks (job_post_id);

create table public.applications (
  id          uuid primary key default gen_random_uuid(),
  job_post_id uuid not null references public.job_posts (id) on delete cascade,
  worker_id   uuid not null references public.profiles (id) on delete cascade,
  message     text not null default '' check (char_length(message) <= 500),  -- 지원 한마디
  status      public.application_status not null default 'pending',
  decided_at  timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (job_post_id, worker_id)
);
create index applications_worker_idx on public.applications (worker_id);

-- 매칭 확정 = 근무 계약. 알바가 탈퇴해도 사장님의 근무 기록은 남깁니다(worker_id → null).
create table public.assignments (
  id             uuid primary key default gen_random_uuid(),
  job_post_id    uuid not null references public.job_posts (id) on delete cascade,
  application_id uuid unique references public.applications (id) on delete set null,
  store_id       uuid not null references public.stores (id) on delete cascade,
  worker_id      uuid references public.profiles (id) on delete set null,
  hourly_wage    integer not null,                 -- 확정 시점 시급
  status         public.assignment_status not null default 'active',
  started_on     date not null,
  ended_on       date,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index assignments_store_idx on public.assignments (store_id);
create index assignments_worker_idx on public.assignments (worker_id);
-- 공고 1개에 근무 중인 알바는 1명
create unique index assignments_one_active_per_post on public.assignments (job_post_id) where status = 'active';

-- ── 근무 ─────────────────────────────────────────────────────────────
create table public.shifts (
  id               uuid primary key default gen_random_uuid(),
  assignment_id    uuid not null references public.assignments (id) on delete cascade,
  store_id         uuid not null references public.stores (id) on delete cascade,
  worker_id        uuid references public.profiles (id) on delete set null,
  work_date        date not null,               -- 한국 시간 기준 근무일
  status           public.shift_status not null,
  started_at       timestamptz,
  start_distance_m integer,                     -- 시작 시 매장까지 거리(m)
  ended_at         timestamptz,
  end_distance_m   integer,
  duration_min     integer generated always as (
    case when started_at is not null and ended_at is not null
      then floor(extract(epoch from (ended_at - started_at)) / 60)::integer
    end
  ) stored,
  memo             text not null default '' check (char_length(memo) <= 500),  -- 특이사항
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (assignment_id, work_date),
  constraint shifts_state_chk check (
    case status
      when 'missed'      then started_at is null and ended_at is null
      when 'in_progress' then started_at is not null and ended_at is null
      when 'completed'   then started_at is not null and ended_at is not null and ended_at >= started_at
    end
  )
);
create index shifts_store_date_idx on public.shifts (store_id, work_date desc);
create index shifts_worker_date_idx on public.shifts (worker_id, work_date desc);

create table public.shift_checks (
  shift_id          uuid not null references public.shifts (id) on delete cascade,
  checklist_item_id uuid not null references public.store_checklist_items (id) on delete cascade,
  title             text not null default '',   -- 체크 당시 항목 문구 (트리거가 채움)
  checked_at        timestamptz not null default now(),
  primary key (shift_id, checklist_item_id)
);

create table public.shift_photos (
  id                uuid primary key default gen_random_uuid(),
  shift_id          uuid not null references public.shifts (id) on delete cascade,
  store_id          uuid not null references public.stores (id) on delete cascade,  -- 트리거가 채움
  kind              public.shift_photo_kind not null,
  checklist_item_id uuid references public.store_checklist_items (id) on delete cascade,
  storage_path      text not null unique,       -- 'shift-photos' 버킷: '{store_id}/{shift_id}/{파일명}.jpg'
  created_at        timestamptz not null default now(),
  constraint shift_photos_item_chk check ((kind = 'item') = (checklist_item_id is not null))
);
create index shift_photos_shift_idx on public.shift_photos (shift_id);
create index shift_photos_created_idx on public.shift_photos (created_at);  -- 보관기간 정리용

-- 사장님 → 알바 평가 (평균은 profiles.rating_avg 로 집계)
create table public.reviews (
  id            uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.assignments (id) on delete cascade,
  reviewer_id   uuid default auth.uid() references public.profiles (id) on delete set null,
  reviewee_id   uuid not null references public.profiles (id) on delete cascade,
  rating        smallint not null check (rating between 1 and 5),
  comment       text not null default '' check (char_length(comment) <= 300),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (assignment_id, reviewer_id)
);
create index reviews_reviewee_idx on public.reviews (reviewee_id);

-- ── 알림 ─────────────────────────────────────────────────────────────
create table public.device_tokens (
  token      text primary key,               -- FCM 토큰
  user_id    uuid not null references public.profiles (id) on delete cascade,
  platform   text not null check (platform in ('android', 'ios')),
  updated_at timestamptz not null default now()
);
create index device_tokens_user_idx on public.device_tokens (user_id);

create table public.notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  type       public.notification_type not null,
  title      text not null,
  body       text not null,
  data       jsonb not null default '{}'::jsonb,   -- 알림을 눌렀을 때 이동할 화면 정보
  read_at    timestamptz,
  pushed_at  timestamptz,                          -- FCM 발송 시각 (5단계)
  created_at timestamptz not null default now()
);
create index notifications_user_idx on public.notifications (user_id, created_at desc);

-- ── 커뮤니티 (사장님 전용) ───────────────────────────────────────────
create table public.community_posts (
  id            uuid primary key default gen_random_uuid(),
  author_id     uuid default auth.uid() references public.profiles (id) on delete set null,  -- 탈퇴 시 '알 수 없음'
  category      public.community_category not null,
  region_code   text not null,                                        -- 작성자 매장의 행정동 코드
  region_name   text not null,
  sigungu_code  text generated always as (left(region_code, 5)) stored, -- 구 단위 필터용
  title         text not null check (char_length(title) between 1 and 100),
  body          text not null check (char_length(body) between 1 and 5000),
  comment_count integer not null default 0,                           -- 트리거 집계
  like_count    integer not null default 0,                           -- 트리거 집계
  view_count    integer not null default 0,                           -- 6단계 RPC가 증가
  is_hidden     boolean not null default false,                       -- 신고 처리로 숨김
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index community_posts_created_idx on public.community_posts (created_at desc);
create index community_posts_sigungu_idx on public.community_posts (sigungu_code, created_at desc);
create index community_posts_region_idx on public.community_posts (region_code, created_at desc);

create table public.community_comments (
  id         uuid primary key default gen_random_uuid(),
  post_id    uuid not null references public.community_posts (id) on delete cascade,
  author_id  uuid default auth.uid() references public.profiles (id) on delete set null,
  body       text not null check (char_length(body) between 1 and 1000),
  is_hidden  boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index community_comments_post_idx on public.community_comments (post_id, created_at);

-- 글 사진 (최대 5장, 'community-photos' 비공개 버킷: 사장님 회원만 열람)
create table public.community_post_photos (
  id           uuid primary key default gen_random_uuid(),
  post_id      uuid not null references public.community_posts (id) on delete cascade,
  storage_path text not null unique,           -- '{post_id}/{파일명}.jpg'
  sort_order   integer not null default 0,
  created_at   timestamptz not null default now()
);
create index community_post_photos_post_idx on public.community_post_photos (post_id, sort_order);

-- 공감(좋아요)
create table public.community_post_likes (
  post_id    uuid not null references public.community_posts (id) on delete cascade,
  user_id    uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
create index community_post_likes_user_idx on public.community_post_likes (user_id);

-- 차단: 내가 차단한 사람의 글·댓글은 내게 보이지 않음
create table public.user_blocks (
  blocker_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

-- 신고 (Google Play 사용자 제작 콘텐츠 정책상 필요)
create table public.content_reports (
  id          uuid primary key default gen_random_uuid(),
  reporter_id uuid default auth.uid() references public.profiles (id) on delete set null,
  target_type public.report_target not null,
  target_id   uuid not null,
  reason      text not null check (char_length(reason) between 1 and 300),
  created_at  timestamptz not null default now(),
  unique (reporter_id, target_type, target_id)
);

-- ── 수익 구조 (결제는 아직 구현하지 않음) ────────────────────────────
-- 유료 매장만 행이 생깁니다. 행이 없으면 무료 매장입니다.
create table public.subscriptions (
  id                   uuid primary key default gen_random_uuid(),
  store_id             uuid not null unique references public.stores (id) on delete cascade,
  plan                 public.subscription_plan not null default 'basic',
  status               public.subscription_status not null default 'active',
  current_period_start timestamptz,
  current_period_end   timestamptz,
  provider             text,   -- 결제사 (나중에)
  provider_ref         text,   -- 결제사 쪽 구독 ID
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

-- 플랜별 사용 가능한 기능 (기능 잠금 기준표)
create table public.plan_features (
  plan        public.subscription_plan not null,
  feature_key text not null,
  primary key (plan, feature_key)
);

-- ── 위치정보 확인자료 ───────────────────────────────────────────────
-- 위치정보법상 '위치정보 수집·이용·제공사실 확인자료' 자동 기록용 (6개월 이상 보관).
-- 탈퇴 후에도 보관해야 하므로 profiles 를 참조하지 않습니다.
create table public.location_access_logs (
  id              bigint generated always as identity primary key,
  subject_user_id uuid not null,                 -- 위치정보 주체
  action          public.location_log_action not null,
  purpose         text not null,                 -- 예: 'neighborhood_verification', 'shift_check_in'
  recipient_id    uuid,                          -- 제공받은 사람 (action = 'provide' 일 때)
  created_at      timestamptz not null default now()
);
create index location_access_logs_subject_idx on public.location_access_logs (subject_user_id, created_at desc);

-- ── updated_at 자동 갱신 ─────────────────────────────────────────────
create trigger set_updated_at before update on public.app_config         for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.profiles           for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.profile_private    for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.stores             for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.store_private      for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.job_posts          for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.applications       for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.assignments        for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.shifts             for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.reviews            for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.community_comments for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.subscriptions      for each row execute function private.set_updated_at();
-- 커뮤니티 글은 내용이 바뀔 때만 (댓글 수 집계로는 '수정됨'이 되지 않게)
create trigger set_updated_at before update of category, title, body on public.community_posts
  for each row execute function private.set_updated_at();
