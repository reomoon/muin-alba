-- =====================================================================
-- 1단계 ③ 내부 함수(private 스키마) · 트리거
--  · RLS 정책에서 쓰는 헬퍼는 security definer 로 만들어, 정책끼리 서로를 다시
--    검사하면서 생기는 무한 재귀를 막습니다. 모두 '지금 로그인한 사람' 기준입니다.
--  · search_path = '' 로 고정하고 모든 이름을 스키마까지 적습니다 (보안 권장사항).
-- =====================================================================

-- ── 설정값 읽기 ──────────────────────────────────────────────────────
create or replace function private.config_int(p_key text)
returns integer
language sql stable security definer
set search_path = ''
as $$
  select (c.value #>> '{}')::integer from public.app_config c where c.key = p_key;
$$;

create or replace function private.config_bool(p_key text)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select coalesce((select (c.value #>> '{}')::boolean from public.app_config c where c.key = p_key), false);
$$;

-- ── 요금제 · 기능 잠금 ───────────────────────────────────────────────
-- 매장의 현재 플랜
--   'basic' 등 : 유효한 구독이 있음
--   'free'     : 구독은 없지만 사장님의 무료 한도(free_store_limit, 먼저 등록한 순) 안
--   'none'     : 구독도 없고 무료 한도도 넘음 → 어떤 기능도 못 씀
create or replace function private.store_plan(p_store_id uuid)
returns text
language sql stable security definer
set search_path = ''
as $$
  with paid as (
    select sub.plan::text as plan
    from public.subscriptions sub
    where sub.store_id = p_store_id
      and sub.status in ('trialing', 'active')
      and (sub.current_period_end is null or sub.current_period_end > now())
  ),
  target as (
    select s.id, s.owner_id, s.created_at from public.stores s where s.id = p_store_id
  ),
  earlier_free as (   -- 이 매장보다 먼저 등록된, 구독 없는 운영 중 매장 수
    select count(*) as n
    from public.stores s
    join target t on s.owner_id = t.owner_id
    where s.is_active
      and (s.created_at, s.id) < (t.created_at, t.id)
      and not exists (
        select 1 from public.subscriptions sub
        where sub.store_id = s.id
          and sub.status in ('trialing', 'active')
          and (sub.current_period_end is null or sub.current_period_end > now())
      )
  )
  select coalesce(
    (select plan from paid),
    case when (select n from earlier_free) < private.config_int('free_store_limit') then 'free' else 'none' end
  );
$$;

-- 이 매장에서 해당 기능을 쓸 수 있나? (app_config.paywall_enabled = false 면 항상 가능)
-- 기능 키: job_posting, shift_tracking, photo_verification, checklist, work_history, monthly_report
create or replace function private.has_feature(p_store_id uuid, p_feature text)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select not private.config_bool('paywall_enabled')
      or exists (
        select 1 from public.plan_features pf
        where pf.plan::text = private.store_plan(p_store_id)
          and pf.feature_key = p_feature
      );
$$;

-- ── 관계 확인 ────────────────────────────────────────────────────────
-- 내 매장인가?
create or replace function private.is_store_owner(p_store_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.stores s
    where s.id = p_store_id and s.owner_id = (select auth.uid())
  );
$$;

-- 이 매장에 지금 근무 확정된 알바인가?
create or replace function private.is_active_worker(p_store_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.assignments a
    where a.store_id = p_store_id
      and a.worker_id = (select auth.uid())
      and a.status = 'active'
  );
$$;

-- 매장을 1곳 이상 등록한 사장님인가? (커뮤니티 이용 조건)
create or replace function private.has_any_store()
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (select 1 from public.stores s where s.owner_id = (select auth.uid()));
$$;

-- 이 행정동에 내 매장이 있나? (커뮤니티 글의 동네)
create or replace function private.owns_store_in_region(p_region_code text)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.stores s
    where s.owner_id = (select auth.uid()) and s.region_code = p_region_code
  );
$$;

-- 지금 매칭(근무 중)된 사이인가? (연락처 공개 조건)
create or replace function private.is_matched_with(p_user_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.assignments a
    join public.stores s on s.id = a.store_id
    where a.status = 'active'
      and (
        (s.owner_id = (select auth.uid()) and a.worker_id = p_user_id)
        or (a.worker_id = (select auth.uid()) and s.owner_id = p_user_id)
      )
  );
$$;

-- 이 위치가 내 인증 동네 안인가? (반경 neighborhood_radius_m, 인증 후 neighborhood_valid_days 이내)
create or replace function private.is_in_my_area(p_location extensions.geography)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.worker_neighborhoods wn
    where wn.user_id = (select auth.uid())
      and wn.verified_at > now() - make_interval(days => private.config_int('neighborhood_valid_days'))
      and extensions.st_dwithin(wn.location, p_location, private.config_int('neighborhood_radius_m'))
  );
$$;

-- (알바 입장) 이 매장을 볼 수 있나? 근무했던 / 지원했던 / 내 동네 안에서 모집 중인 매장
create or replace function private.worker_can_view_store(p_store_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.stores s
    where s.id = p_store_id
      and (
        exists (
          select 1 from public.assignments a
          where a.store_id = s.id and a.worker_id = (select auth.uid())
        )
        or exists (
          select 1
          from public.applications ap
          join public.job_posts jp on jp.id = ap.job_post_id
          where jp.store_id = s.id and ap.worker_id = (select auth.uid())
        )
        or (
          s.is_active
          and exists (select 1 from public.job_posts jp where jp.store_id = s.id and jp.status = 'open')
          and private.is_in_my_area(s.location)
        )
      )
  );
$$;

-- (알바 입장) 이 공고를 볼 수 있나? 지원했던 공고 / 내 동네 안의 모집 중 공고
create or replace function private.worker_can_view_job_post(
  p_job_post_id uuid, p_store_id uuid, p_status public.job_post_status)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
      select 1 from public.applications ap
      where ap.job_post_id = p_job_post_id and ap.worker_id = (select auth.uid())
    )
    or (
      p_status = 'open'
      and exists (
        select 1 from public.stores s
        where s.id = p_store_id and s.is_active and private.is_in_my_area(s.location)
      )
    );
$$;

-- 이 공고를 볼 수 있나? (사장님 본인 또는 위 조건)
create or replace function private.can_view_job_post(p_job_post_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.job_posts jp
    where jp.id = p_job_post_id
      and (
        private.is_store_owner(jp.store_id)
        or private.worker_can_view_job_post(jp.id, jp.store_id, jp.status)
      )
  );
$$;

-- 이 공고의 사장님인가?
create or replace function private.is_job_post_owner(p_job_post_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.job_posts jp
    join public.stores s on s.id = jp.store_id
    where jp.id = p_job_post_id and s.owner_id = (select auth.uid())
  );
$$;

-- 이 근무 기록을 볼 수 있나? (근무한 알바 / 매장 사장님)
create or replace function private.can_view_shift(p_shift_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.shifts sh
    join public.stores s on s.id = sh.store_id
    where sh.id = p_shift_id
      and (sh.worker_id = (select auth.uid()) or s.owner_id = (select auth.uid()))
  );
$$;

-- 진행 중인 '내' 근무이고 매장 플랜에 그 기능이 있나? (체크리스트·사진 기록 조건)
create or replace function private.can_record_shift(p_shift_id uuid, p_feature text)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.shifts sh
    where sh.id = p_shift_id
      and sh.worker_id = (select auth.uid())
      and sh.status = 'in_progress'
      and private.has_feature(sh.store_id, p_feature)
  );
$$;

-- 이 근무 계약의 알바를 평가할 수 있나? (그 매장 사장님만)
create or replace function private.can_review(p_assignment_id uuid, p_reviewee_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.assignments a
    join public.stores s on s.id = a.store_id
    where a.id = p_assignment_id
      and s.owner_id = (select auth.uid())
      and a.worker_id = p_reviewee_id
  );
$$;

-- 근무 이력이 있는 매장인가? (이력이 있으면 삭제 대신 비활성화)
create or replace function private.store_has_history(p_store_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (select 1 from public.assignments a where a.store_id = p_store_id);
$$;

-- 내가 차단한 사람인가?
create or replace function private.is_blocked_by_me(p_user_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.user_blocks b
    where b.blocker_id = (select auth.uid()) and b.blocked_id = p_user_id
  );
$$;

-- 내가 쓴 커뮤니티 글인가?
create or replace function private.is_post_author(p_post_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.community_posts p
    where p.id = p_post_id and p.author_id = (select auth.uid())
  );
$$;

-- ── 트리거 ───────────────────────────────────────────────────────────

-- 첫 로그인(회원가입) 시 프로필 자동 생성. 카카오·구글 닉네임과 사진을 가져옵니다.
create or replace function private.handle_new_user()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, nickname, avatar_url)
  values (
    new.id,
    left(coalesce(
      new.raw_user_meta_data ->> 'nickname',
      new.raw_user_meta_data ->> 'name',
      new.raw_user_meta_data ->> 'full_name',
      new.raw_user_meta_data ->> 'user_name',
      ''
    ), 20),
    coalesce(new.raw_user_meta_data ->> 'avatar_url', new.raw_user_meta_data ->> 'picture')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- 매장 등록 시 업종별 기본 체크리스트 복사 (사장님이 이후 수정)
create or replace function private.copy_checklist_template()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  insert into public.store_checklist_items (store_id, title, requires_photo, sort_order)
  select new.id,
         e.item ->> 'title',
         coalesce((e.item ->> 'requires_photo')::boolean, false),
         e.ord::integer
  from public.checklist_templates t
  cross join lateral jsonb_array_elements(t.items) with ordinality as e(item, ord)
  where t.category = new.category;
  return null;
end;
$$;

create trigger copy_checklist_template
  after insert on public.stores
  for each row execute function private.copy_checklist_template();

-- 매장 사진: 최대 5장, 경로는 '{store_id}/...'
create or replace function private.check_store_photo()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  if new.storage_path not like new.store_id::text || '/%' then
    raise exception '사진 경로가 올바르지 않아요.' using hint = 'invalid_photo_path';
  end if;
  if (select count(*) from public.store_photos p where p.store_id = new.store_id) >= 5 then
    raise exception '매장 사진은 5장까지 올릴 수 있어요.' using hint = 'photo_limit';
  end if;
  return new;
end;
$$;

create trigger check_store_photo
  before insert on public.store_photos
  for each row execute function private.check_store_photo();

-- 공고 검사: 최저시급, 자유 시간대 길이, 무료 한도
create or replace function private.validate_job_post()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
declare
  v_check_wage boolean;
  v_min_wage   integer := private.config_int('min_hourly_wage');
  v_window_min integer;
begin
  -- 최저시급은 새 공고이거나 시급을 바꿀 때만 검사 (해가 바뀌어도 기존 공고 마감은 가능하게)
  if tg_op = 'INSERT' then
    v_check_wage := true;
  else
    v_check_wage := new.hourly_wage is distinct from old.hourly_wage;
  end if;

  if v_check_wage and new.hourly_wage < v_min_wage then
    raise exception '시급은 최저시급(%원) 이상이어야 해요.', v_min_wage
      using hint = 'below_min_wage';
  end if;

  if new.time_type = 'flexible' then
    -- 자정을 넘는 시간대(예: 22:00~02:00)도 허용
    v_window_min := (extract(epoch from (new.window_end - new.window_start)) / 60)::integer;
    if v_window_min < 0 then
      v_window_min := v_window_min + 1440;
    end if;
    if v_window_min < new.work_minutes then
      raise exception '가능 시간대가 근무 시간(%분)보다 짧아요.', new.work_minutes
        using hint = 'window_too_short';
    end if;
  end if;

  if tg_op = 'INSERT' and not private.has_feature(new.store_id, 'job_posting') then
    raise exception '무료 플랜은 매장 %곳까지 공고를 올릴 수 있어요.', private.config_int('free_store_limit')
      using hint = 'feature_locked';
  end if;

  return new;
end;
$$;

create trigger validate_job_post
  before insert or update on public.job_posts
  for each row execute function private.validate_job_post();

-- 체크 시 그 매장의 항목인지 확인하고, 당시 항목 문구를 함께 저장
create or replace function private.fill_shift_check()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  select i.title into new.title
  from public.store_checklist_items i
  join public.shifts sh on sh.store_id = i.store_id
  where i.id = new.checklist_item_id
    and sh.id = new.shift_id
    and i.is_active;

  if not found then
    raise exception '이 매장의 체크리스트 항목이 아니에요.' using hint = 'invalid_checklist_item';
  end if;
  return new;
end;
$$;

create trigger fill_shift_check
  before insert on public.shift_checks
  for each row execute function private.fill_shift_check();

-- 근무 사진: 매장 정보를 채우고 경로('{store_id}/{shift_id}/...')를 확인
create or replace function private.fill_shift_photo()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  select sh.store_id into new.store_id from public.shifts sh where sh.id = new.shift_id;

  if new.store_id is null
     or new.storage_path not like new.store_id::text || '/' || new.shift_id::text || '/%' then
    raise exception '사진 경로가 올바르지 않아요.' using hint = 'invalid_photo_path';
  end if;

  if new.checklist_item_id is not null and not exists (
    select 1 from public.store_checklist_items i
    where i.id = new.checklist_item_id and i.store_id = new.store_id
  ) then
    raise exception '이 매장의 체크리스트 항목이 아니에요.' using hint = 'invalid_checklist_item';
  end if;
  return new;
end;
$$;

create trigger fill_shift_photo
  before insert on public.shift_photos
  for each row execute function private.fill_shift_photo();

-- 평점 집계 (받은 평가의 평균·개수)
create or replace function private.refresh_rating()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
declare
  v_user uuid;
begin
  if tg_op = 'DELETE' then v_user := old.reviewee_id; else v_user := new.reviewee_id; end if;

  update public.profiles p
  set rating_avg   = coalesce((select round(avg(r.rating), 1) from public.reviews r where r.reviewee_id = v_user), 0),
      rating_count = (select count(*) from public.reviews r where r.reviewee_id = v_user)
  where p.id = v_user;
  return null;
end;
$$;

create trigger refresh_rating
  after insert or delete or update of rating on public.reviews
  for each row execute function private.refresh_rating();

-- 근무 완료·미출근 횟수 집계 (지원자 카드에 표시)
create or replace function private.refresh_shift_counts()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
declare
  v_user uuid;
begin
  if tg_op = 'DELETE' then v_user := old.worker_id; else v_user := new.worker_id; end if;
  if v_user is null then
    return null;
  end if;

  update public.profiles p
  set completed_shifts = (select count(*) from public.shifts s where s.worker_id = v_user and s.status = 'completed'),
      missed_shifts    = (select count(*) from public.shifts s where s.worker_id = v_user and s.status = 'missed')
  where p.id = v_user;
  return null;
end;
$$;

create trigger refresh_shift_counts
  after insert or delete or update of status on public.shifts
  for each row execute function private.refresh_shift_counts();

-- 커뮤니티 댓글 수 집계
create or replace function private.refresh_comment_count()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
declare
  v_post uuid;
begin
  if tg_op = 'DELETE' then v_post := old.post_id; else v_post := new.post_id; end if;

  update public.community_posts p
  set comment_count = (
    select count(*) from public.community_comments c where c.post_id = v_post and not c.is_hidden
  )
  where p.id = v_post;
  return null;
end;
$$;

create trigger refresh_comment_count
  after insert or delete or update of is_hidden on public.community_comments
  for each row execute function private.refresh_comment_count();

-- 커뮤니티 공감 수 집계
create or replace function private.refresh_like_count()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
declare
  v_post uuid;
begin
  if tg_op = 'DELETE' then v_post := old.post_id; else v_post := new.post_id; end if;

  update public.community_posts p
  set like_count = (select count(*) from public.community_post_likes l where l.post_id = v_post)
  where p.id = v_post;
  return null;
end;
$$;

create trigger refresh_like_count
  after insert or delete on public.community_post_likes
  for each row execute function private.refresh_like_count();

-- 커뮤니티 글 사진: 최대 5장, 경로는 '{post_id}/...'
create or replace function private.check_community_photo()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  if new.storage_path not like new.post_id::text || '/%' then
    raise exception '사진 경로가 올바르지 않아요.' using hint = 'invalid_photo_path';
  end if;
  if (select count(*) from public.community_post_photos p where p.post_id = new.post_id) >= 5 then
    raise exception '사진은 5장까지 올릴 수 있어요.' using hint = 'photo_limit';
  end if;
  return new;
end;
$$;

create trigger check_community_photo
  before insert on public.community_post_photos
  for each row execute function private.check_community_photo();

-- ── 실행 권한: RLS를 평가하는 authenticated 와 서버용 service_role 만 ──
revoke all on all functions in schema private from public, anon;
grant execute on all functions in schema private to authenticated, service_role;
