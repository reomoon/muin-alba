-- =====================================================================
-- 2단계: 동네 인증 저장 · 회원 탈퇴 준비 · 보안 경고 정리
--
--  동네 인증 흐름
--   앱(GPS 좌표) → Edge Function 'neighborhood' → 카카오 로컬 API로 행정동 확인
--   → 서버 키로 save_neighborhood 호출 (앱이 직접 호출할 수 없음)
--  위치를 받을 때마다 location_access_logs 에 확인자료를 남깁니다.
-- =====================================================================

-- ── 동네 인증 저장 (Edge Function 전용) ──────────────────────────────
create or replace function public.save_neighborhood(
  p_user_id     uuid,
  p_lat         double precision,
  p_lng         double precision,
  p_region_code text,
  p_region_name text
)
returns table (region_code text, region_name text, verified_at timestamptz, expires_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  -- 대한민국 범위 밖 좌표는 거절 (GPS 오류·조작 1차 차단)
  if p_lat is null or p_lng is null
     or p_lat not between 33.0 and 38.9 or p_lng not between 124.5 and 131.9 then
    raise exception '대한민국 안의 위치가 아니에요.' using hint = 'out_of_korea';
  end if;
  if p_region_code is null or p_region_code !~ '^[0-9]{10}$' then
    raise exception '행정동 코드가 올바르지 않아요.' using hint = 'invalid_region';
  end if;

  insert into public.worker_neighborhoods (user_id, location, region_code, region_name, verified_at)
  values (
    p_user_id,
    extensions.st_point(p_lng, p_lat, 4326)::extensions.geography,
    p_region_code,
    p_region_name,
    now()
  )
  on conflict (user_id) do update
    set location    = excluded.location,
        region_code = excluded.region_code,
        region_name = excluded.region_name,
        verified_at = excluded.verified_at;

  insert into public.location_access_logs (subject_user_id, action, purpose)
  values (p_user_id, 'collect', 'neighborhood_verification');

  return query
    select wn.region_code,
           wn.region_name,
           wn.verified_at,
           wn.verified_at + make_interval(days => private.config_int('neighborhood_valid_days'))
    from public.worker_neighborhoods wn
    where wn.user_id = p_user_id;
end;
$$;

-- ── 회원 탈퇴 준비 (Edge Function 'delete-account' 전용) ──────────────
--  1) 알바로 근무 중인 매칭은 '근무 끝'으로 바꾸고 공고를 다시 모집 중으로
--  2) 지워야 할 사진 경로를 돌려줌 (내 매장의 매장 사진·근무 사진)
--     Storage 파일은 SQL로 지우면 실제 파일이 남으므로 Edge Function이 Storage API로 지웁니다.
--  그 뒤 Edge Function이 auth 사용자를 지우면 나머지 데이터는 외래키 규칙대로 정리됩니다.
create or replace function public.prepare_account_deletion(p_user_id uuid)
returns table (bucket_id text, name text)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  update public.job_posts jp
     set status = 'open'
   where jp.status = 'matched'
     and jp.id in (
       select a.job_post_id from public.assignments a
       where a.worker_id = p_user_id and a.status = 'active'
     );

  update public.assignments a
     set status = 'ended',
         ended_on = (now() at time zone 'Asia/Seoul')::date
   where a.worker_id = p_user_id and a.status = 'active';

  return query
    select o.bucket_id::text, o.name::text
    from storage.objects o
    where o.bucket_id in ('store-photos', 'shift-photos')
      and split_part(o.name, '/', 1) in (
        select s.id::text from public.stores s where s.owner_id = p_user_id
      );
end;
$$;

-- 서버(service_role)만 실행 가능
revoke all on function public.save_neighborhood(uuid, double precision, double precision, text, text)
  from public, anon, authenticated;
revoke all on function public.prepare_account_deletion(uuid) from public, anon, authenticated;
grant execute on function public.save_neighborhood(uuid, double precision, double precision, text, text)
  to service_role;
grant execute on function public.prepare_account_deletion(uuid) to service_role;

-- ── 보안 경고 정리 ───────────────────────────────────────────────────
-- 프로젝트 생성 때 켠 'Enable automatic RLS' 옵션이 만든 이벤트 트리거 함수가
-- API로 호출 가능하다는 경고(Security Advisor) 제거. 트리거 동작에는 영향 없음.
do $$
begin
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'rls_auto_enable' and p.pronargs = 0
  ) then
    execute 'revoke all on function public.rls_auto_enable() from public, anon, authenticated';
  end if;
end $$;
