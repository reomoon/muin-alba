-- =====================================================================
-- 1단계 ④ 권한 · RLS 정책
--  · GRANT 로 '무엇을(읽기/쓰기, 어떤 컬럼)' 할 수 있는지, RLS 로 '어느 행'인지 정합니다.
--  · 로그인 전(anon)은 어떤 테이블도 못 읽습니다.
--  · 지원·수락·근무 시작/종료 같은 상태 변경은 이후 단계의 RPC 함수가 처리하므로
--    applications · assignments · shifts 에는 앱이 직접 쓰는 권한이 없습니다.
--  · 새 테이블을 추가할 때도 이 파일처럼 권한과 정책을 명시적으로 적어 주세요.
-- =====================================================================

-- ── 기본 권한 초기화 ─────────────────────────────────────────────────
revoke all on all tables in schema public from anon, authenticated;
grant all on all tables in schema public to service_role;            -- Edge Function(서버)용
grant usage, select on all sequences in schema public to service_role;

-- ── 모든 테이블 RLS 켜기 ─────────────────────────────────────────────
alter table public.app_config            enable row level security;
alter table public.profiles              enable row level security;
alter table public.user_consents         enable row level security;
alter table public.profile_private       enable row level security;
alter table public.worker_neighborhoods  enable row level security;
alter table public.stores                enable row level security;
alter table public.store_private         enable row level security;
alter table public.store_photos          enable row level security;
alter table public.checklist_templates   enable row level security;
alter table public.store_checklist_items enable row level security;
alter table public.job_posts             enable row level security;
alter table public.job_post_bookmarks    enable row level security;
alter table public.applications          enable row level security;
alter table public.assignments           enable row level security;
alter table public.shifts                enable row level security;
alter table public.shift_checks          enable row level security;
alter table public.shift_photos          enable row level security;
alter table public.reviews               enable row level security;
alter table public.device_tokens         enable row level security;
alter table public.notifications         enable row level security;
alter table public.community_posts       enable row level security;
alter table public.community_comments    enable row level security;
alter table public.community_post_photos enable row level security;
alter table public.community_post_likes  enable row level security;
alter table public.user_blocks           enable row level security;
alter table public.content_reports       enable row level security;
alter table public.subscriptions         enable row level security;
alter table public.plan_features         enable row level security;
alter table public.location_access_logs  enable row level security;

-- ── 읽기 전용 기준 데이터 ────────────────────────────────────────────
grant select on public.app_config, public.plan_features, public.checklist_templates to authenticated;
create policy "app_config: read"          on public.app_config          for select to authenticated using (true);
create policy "plan_features: read"       on public.plan_features       for select to authenticated using (true);
create policy "checklist_templates: read" on public.checklist_templates for select to authenticated using (true);

-- ── 프로필: 카드는 모두 읽기, 수정은 본인 (평점·횟수 컬럼은 수정 불가) ──
grant select on public.profiles to authenticated;
grant update (nickname, avatar_url, bio, is_owner, is_worker, onboarded_at) on public.profiles to authenticated;
create policy "profiles: read"        on public.profiles for select to authenticated using (true);
create policy "profiles: update self" on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- ── 약관 동의: 본인 것만 ─────────────────────────────────────────────
grant select on public.user_consents to authenticated;
grant insert (consent_type, version) on public.user_consents to authenticated;
grant update (withdrawn_at) on public.user_consents to authenticated;
create policy "user_consents: read own"     on public.user_consents for select to authenticated
  using (user_id = (select auth.uid()));
create policy "user_consents: insert own"   on public.user_consents for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy "user_consents: withdraw own" on public.user_consents for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- ── 연락처: 본인 + 지금 매칭된 상대 ──────────────────────────────────
grant select on public.profile_private to authenticated;
grant insert (phone) on public.profile_private to authenticated;
grant update (phone) on public.profile_private to authenticated;
create policy "profile_private: read self or matched" on public.profile_private for select to authenticated
  using (user_id = (select auth.uid()) or private.is_matched_with(user_id));
create policy "profile_private: insert self" on public.profile_private for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy "profile_private: update self" on public.profile_private for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- ── 동네 인증: 본인만 읽기·해제. 인증(쓰기)은 2단계 RPC ─────────────
grant select, delete on public.worker_neighborhoods to authenticated;
create policy "worker_neighborhoods: read own"   on public.worker_neighborhoods for select to authenticated
  using (user_id = (select auth.uid()));
create policy "worker_neighborhoods: delete own" on public.worker_neighborhoods for delete to authenticated
  using (user_id = (select auth.uid()));

-- ── 매장 ─────────────────────────────────────────────────────────────
-- 읽기: 사장님 본인 / 근무·지원했던 알바 / 내 동네 안에서 모집 중인 매장
-- 삭제: 근무 이력이 없을 때만 (있으면 is_active = false 로 비활성화)
grant select, delete on public.stores to authenticated;
grant insert (name, category, address, address_detail, location, region_code, region_name, contact_phone)
  on public.stores to authenticated;
grant update (name, category, address, address_detail, location, region_code, region_name, contact_phone, is_active)
  on public.stores to authenticated;
create policy "stores: read"       on public.stores for select to authenticated
  using (owner_id = (select auth.uid()) or private.worker_can_view_store(id));
create policy "stores: insert own" on public.stores for insert to authenticated
  with check (owner_id = (select auth.uid()));
create policy "stores: update own" on public.stores for update to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy "stores: delete own without history" on public.stores for delete to authenticated
  using (owner_id = (select auth.uid()) and not private.store_has_history(id));

-- 출입 정보: 사장님 + 근무 확정된 알바
grant select on public.store_private to authenticated;
grant insert (store_id, access_note) on public.store_private to authenticated;
grant update (access_note) on public.store_private to authenticated;
create policy "store_private: read"   on public.store_private for select to authenticated
  using (private.is_store_owner(store_id) or private.is_active_worker(store_id));
create policy "store_private: insert" on public.store_private for insert to authenticated
  with check (private.is_store_owner(store_id));
create policy "store_private: update" on public.store_private for update to authenticated
  using (private.is_store_owner(store_id)) with check (private.is_store_owner(store_id));

-- 매장 사진 목록: 매장을 볼 수 있으면 읽기, 관리는 사장님
grant select, delete on public.store_photos to authenticated;
grant insert (store_id, storage_path, sort_order) on public.store_photos to authenticated;
grant update (sort_order) on public.store_photos to authenticated;
create policy "store_photos: read"   on public.store_photos for select to authenticated
  using (private.is_store_owner(store_id) or private.worker_can_view_store(store_id));
create policy "store_photos: insert" on public.store_photos for insert to authenticated
  with check (private.is_store_owner(store_id));
create policy "store_photos: update" on public.store_photos for update to authenticated
  using (private.is_store_owner(store_id)) with check (private.is_store_owner(store_id));
create policy "store_photos: delete" on public.store_photos for delete to authenticated
  using (private.is_store_owner(store_id));

-- 매장 체크리스트: 매장을 볼 수 있으면 읽기(공고 상세에 표시), 관리는 사장님. 삭제 대신 비활성
grant select on public.store_checklist_items to authenticated;
grant insert (store_id, title, requires_photo, sort_order) on public.store_checklist_items to authenticated;
grant update (title, requires_photo, sort_order, is_active) on public.store_checklist_items to authenticated;
create policy "store_checklist_items: read"   on public.store_checklist_items for select to authenticated
  using (private.is_store_owner(store_id) or private.worker_can_view_store(store_id));
create policy "store_checklist_items: insert" on public.store_checklist_items for insert to authenticated
  with check (private.is_store_owner(store_id));
create policy "store_checklist_items: update" on public.store_checklist_items for update to authenticated
  using (private.is_store_owner(store_id)) with check (private.is_store_owner(store_id));

-- ── 공고 ─────────────────────────────────────────────────────────────
-- 읽기: 사장님 본인 / 지원했던 알바 / 인증 동네 반경 안의 모집 중 공고
-- 삭제 대신 status = 'closed'
grant select on public.job_posts to authenticated;
grant insert (store_id, title, description, hourly_wage, work_minutes, time_type,
              window_start, window_end, work_days, start_date, end_date)
  on public.job_posts to authenticated;
grant update (title, description, hourly_wage, work_minutes, time_type,
              window_start, window_end, work_days, start_date, end_date, status)
  on public.job_posts to authenticated;
create policy "job_posts: read"   on public.job_posts for select to authenticated
  using (private.is_store_owner(store_id) or private.worker_can_view_job_post(id, store_id, status));
create policy "job_posts: insert" on public.job_posts for insert to authenticated
  with check (private.is_store_owner(store_id));
create policy "job_posts: update" on public.job_posts for update to authenticated
  using (private.is_store_owner(store_id)) with check (private.is_store_owner(store_id));

-- 관심 공고: 본인 것만, 볼 수 있는 공고만 등록
grant select, delete on public.job_post_bookmarks to authenticated;
grant insert (job_post_id) on public.job_post_bookmarks to authenticated;
create policy "job_post_bookmarks: read own"   on public.job_post_bookmarks for select to authenticated
  using (user_id = (select auth.uid()));
create policy "job_post_bookmarks: insert own" on public.job_post_bookmarks for insert to authenticated
  with check (user_id = (select auth.uid()) and private.can_view_job_post(job_post_id));
create policy "job_post_bookmarks: delete own" on public.job_post_bookmarks for delete to authenticated
  using (user_id = (select auth.uid()));

-- ── 지원 · 매칭 · 근무 기록: 읽기만 (쓰기는 RPC) ─────────────────────
grant select on public.applications, public.assignments, public.shifts to authenticated;
create policy "applications: read" on public.applications for select to authenticated
  using (worker_id = (select auth.uid()) or private.is_job_post_owner(job_post_id));
create policy "assignments: read"  on public.assignments  for select to authenticated
  using (worker_id = (select auth.uid()) or private.is_store_owner(store_id));
create policy "shifts: read"       on public.shifts       for select to authenticated
  using (worker_id = (select auth.uid()) or private.is_store_owner(store_id));

-- 체크리스트 체크: 진행 중인 내 근무에만 (매장 플랜에 checklist 기능 필요)
grant select, delete on public.shift_checks to authenticated;
grant insert (shift_id, checklist_item_id) on public.shift_checks to authenticated;
create policy "shift_checks: read"   on public.shift_checks for select to authenticated
  using (private.can_view_shift(shift_id));
create policy "shift_checks: insert" on public.shift_checks for insert to authenticated
  with check (private.can_record_shift(shift_id, 'checklist'));
create policy "shift_checks: delete" on public.shift_checks for delete to authenticated
  using (private.can_record_shift(shift_id, 'checklist'));

-- 근무 사진 기록: 진행 중인 내 근무에만 (매장 플랜에 photo_verification 기능 필요)
grant select, delete on public.shift_photos to authenticated;
grant insert (shift_id, kind, checklist_item_id, storage_path) on public.shift_photos to authenticated;
create policy "shift_photos: read"   on public.shift_photos for select to authenticated
  using (private.can_view_shift(shift_id));
create policy "shift_photos: insert" on public.shift_photos for insert to authenticated
  with check (private.can_record_shift(shift_id, 'photo_verification'));
create policy "shift_photos: delete" on public.shift_photos for delete to authenticated
  using (private.can_record_shift(shift_id, 'photo_verification'));

-- ── 평가: 그 매장 사장님이 근무 계약의 알바를 평가 ───────────────────
grant select on public.reviews to authenticated;
grant insert (assignment_id, reviewee_id, rating, comment) on public.reviews to authenticated;
grant update (rating, comment) on public.reviews to authenticated;
create policy "reviews: read own"   on public.reviews for select to authenticated
  using (reviewer_id = (select auth.uid()) or reviewee_id = (select auth.uid()));
create policy "reviews: insert"     on public.reviews for insert to authenticated
  with check (reviewer_id = (select auth.uid()) and private.can_review(assignment_id, reviewee_id));
create policy "reviews: update own" on public.reviews for update to authenticated
  using (reviewer_id = (select auth.uid())) with check (reviewer_id = (select auth.uid()));

-- ── 알림 ─────────────────────────────────────────────────────────────
-- FCM 토큰 등록은 5단계 RPC (다른 계정에 묶인 토큰을 옮겨야 해서)
grant select, delete on public.device_tokens to authenticated;
create policy "device_tokens: read own"   on public.device_tokens for select to authenticated
  using (user_id = (select auth.uid()));
create policy "device_tokens: delete own" on public.device_tokens for delete to authenticated
  using (user_id = (select auth.uid()));

-- 알림함: 본인 것만 읽기·삭제, 수정은 읽음 표시(read_at)만. 생성은 서버(트리거·RPC)
grant select, delete on public.notifications to authenticated;
grant update (read_at) on public.notifications to authenticated;
create policy "notifications: read own"   on public.notifications for select to authenticated
  using (user_id = (select auth.uid()));
create policy "notifications: update own" on public.notifications for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "notifications: delete own" on public.notifications for delete to authenticated
  using (user_id = (select auth.uid()));

-- ── 커뮤니티: 매장을 1곳 이상 등록한 사장님만 ────────────────────────
-- 숨김 처리된 글·댓글은 작성자 본인에게만, 내가 차단한 사람의 글·댓글은 안 보임
grant select, delete on public.community_posts to authenticated;
grant insert (category, region_code, region_name, title, body) on public.community_posts to authenticated;
grant update (category, title, body) on public.community_posts to authenticated;
create policy "community_posts: read" on public.community_posts for select to authenticated
  using (
    private.has_any_store()
    and (not is_hidden or author_id = (select auth.uid()))
    and not private.is_blocked_by_me(author_id)
  );
create policy "community_posts: insert" on public.community_posts for insert to authenticated
  with check (author_id = (select auth.uid()) and private.owns_store_in_region(region_code));
create policy "community_posts: update own" on public.community_posts for update to authenticated
  using (author_id = (select auth.uid())) with check (author_id = (select auth.uid()));
create policy "community_posts: delete own" on public.community_posts for delete to authenticated
  using (author_id = (select auth.uid()));

grant select, delete on public.community_comments to authenticated;
grant insert (post_id, body) on public.community_comments to authenticated;
grant update (body) on public.community_comments to authenticated;
create policy "community_comments: read" on public.community_comments for select to authenticated
  using (
    private.has_any_store()
    and (not is_hidden or author_id = (select auth.uid()))
    and not private.is_blocked_by_me(author_id)
  );
create policy "community_comments: insert" on public.community_comments for insert to authenticated
  with check (
    author_id = (select auth.uid())
    and private.has_any_store()
    and exists (select 1 from public.community_posts p where p.id = post_id)  -- 내게 보이는 글에만
  );
create policy "community_comments: update own" on public.community_comments for update to authenticated
  using (author_id = (select auth.uid())) with check (author_id = (select auth.uid()));
create policy "community_comments: delete own" on public.community_comments for delete to authenticated
  using (author_id = (select auth.uid()));

grant select, delete on public.community_post_photos to authenticated;
grant insert (post_id, storage_path, sort_order) on public.community_post_photos to authenticated;
create policy "community_post_photos: read"   on public.community_post_photos for select to authenticated
  using (exists (select 1 from public.community_posts p where p.id = post_id));
create policy "community_post_photos: insert" on public.community_post_photos for insert to authenticated
  with check (private.is_post_author(post_id));
create policy "community_post_photos: delete" on public.community_post_photos for delete to authenticated
  using (private.is_post_author(post_id));

grant select, delete on public.community_post_likes to authenticated;
grant insert (post_id) on public.community_post_likes to authenticated;
create policy "community_post_likes: read"       on public.community_post_likes for select to authenticated
  using (private.has_any_store());
create policy "community_post_likes: insert own" on public.community_post_likes for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.community_posts p where p.id = post_id)
  );
create policy "community_post_likes: delete own" on public.community_post_likes for delete to authenticated
  using (user_id = (select auth.uid()));

-- 차단 목록: 본인 것만
grant select, delete on public.user_blocks to authenticated;
grant insert (blocked_id) on public.user_blocks to authenticated;
create policy "user_blocks: read own"   on public.user_blocks for select to authenticated
  using (blocker_id = (select auth.uid()));
create policy "user_blocks: insert own" on public.user_blocks for insert to authenticated
  with check (blocker_id = (select auth.uid()));
create policy "user_blocks: delete own" on public.user_blocks for delete to authenticated
  using (blocker_id = (select auth.uid()));

-- 신고: 사장님 회원이 등록, 본인 신고 내역만 읽기
grant select on public.content_reports to authenticated;
grant insert (target_type, target_id, reason) on public.content_reports to authenticated;
create policy "content_reports: read own"   on public.content_reports for select to authenticated
  using (reporter_id = (select auth.uid()));
create policy "content_reports: insert own" on public.content_reports for insert to authenticated
  with check (reporter_id = (select auth.uid()) and private.has_any_store());

-- ── 구독: 사장님은 자기 매장 것만 읽기 (쓰기는 나중에 결제 서버가 service_role 로) ──
grant select on public.subscriptions to authenticated;
create policy "subscriptions: read own store" on public.subscriptions for select to authenticated
  using (private.is_store_owner(store_id));

-- ── 위치정보 확인자료: 본인 기록 열람만 (기록은 서버 함수) ───────────
grant select on public.location_access_logs to authenticated;
create policy "location_access_logs: read own" on public.location_access_logs for select to authenticated
  using (subject_user_id = (select auth.uid()));
