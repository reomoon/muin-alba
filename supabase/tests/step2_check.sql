-- =====================================================================
-- 2단계 점검: 동네 인증 저장 · 회원 탈퇴 준비
--   실행: (1) 로컬 npm run db:test
--         (2) 클라우드 SQL Editor 에 전체 붙여넣고 Run
--   마지막에 ROLLBACK 하므로 DB에 아무것도 남지 않습니다.
--   끝까지 가면 '✅ 2단계 점검 통과', 실패하면 어느 항목인지 메시지와 함께 멈춥니다.
-- =====================================================================
begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('a0000000-0000-4000-8000-0000000000a2', 'owner-a2@test.invalid',  '{"name": "사장A2"}'),
  ('c0000000-0000-4000-8000-0000000000c2', 'worker-w2@test.invalid', '{"name": "알바W2"}');

-- ═════ 1. 앱(로그인 사용자)은 서버 전용 함수를 부를 수 없음 ═════
select set_config('request.jwt.claims', '{"sub": "c0000000-0000-4000-8000-0000000000c2", "role": "authenticated"}', true);
set local role authenticated;

do $$ begin
  begin
    perform * from public.save_neighborhood(
      'c0000000-0000-4000-8000-0000000000c2', 37.5045, 127.0366, '1168064000', '서울특별시 강남구 역삼1동');
    assert false, '앱에서 save_neighborhood 를 직접 부를 수 없어야 함 (동네 이름 조작 방지)';
  exception when insufficient_privilege then null;
  end;

  begin
    perform * from public.prepare_account_deletion('c0000000-0000-4000-8000-0000000000c2');
    assert false, '앱에서 prepare_account_deletion 을 직접 부를 수 없어야 함';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- ═════ 2. 서버(service_role)로 동네 인증 저장 ═════
set local role service_role;

do $$
declare
  r      record;
  v_hint text;
begin
  select * into r from public.save_neighborhood(
    'c0000000-0000-4000-8000-0000000000c2', 37.5045, 127.0366, '1168064000', '서울특별시 강남구 역삼1동');
  assert r.region_name = '서울특별시 강남구 역삼1동', '동네 인증이 저장돼야 함';
  assert r.expires_at = r.verified_at + interval '30 days', '인증 유효기간이 30일이어야 함';

  -- 다시 인증하면 덮어씀 (사람당 1개)
  perform * from public.save_neighborhood(
    'c0000000-0000-4000-8000-0000000000c2', 37.4979, 127.0276, '1168065000', '서울특별시 강남구 역삼2동');
  assert (select count(*) from public.worker_neighborhoods
           where user_id = 'c0000000-0000-4000-8000-0000000000c2') = 1, '동네 인증은 사람당 1개여야 함';
  assert (select region_name from public.worker_neighborhoods
           where user_id = 'c0000000-0000-4000-8000-0000000000c2') = '서울특별시 강남구 역삼2동',
    '다시 인증하면 새 동네로 바뀌어야 함';
  assert (select count(*) from public.location_access_logs
           where subject_user_id = 'c0000000-0000-4000-8000-0000000000c2'
             and purpose = 'neighborhood_verification') = 2,
    '인증할 때마다 위치정보 확인자료가 남아야 함';

  begin
    perform * from public.save_neighborhood(
      'c0000000-0000-4000-8000-0000000000c2', 35.68, 139.76, '1168064000', '해외');
    assert false, '대한민국 밖 좌표는 거절돼야 함';
  exception when raise_exception then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'out_of_korea' then raise; end if;
  end;
end $$;
reset role;

-- ═════ 3. 회원 탈퇴 준비 ═════
-- 사장A2 매장·공고에 알바W2가 근무 중 (관리자 권한으로 생성)
insert into public.stores (id, owner_id, name, category, address, location, region_code, region_name) values
  ('10000000-0000-4000-8000-0000000000a2', 'a0000000-0000-4000-8000-0000000000a2', '탈퇴 테스트 매장', 'other',
   '서울 강남구', extensions.st_point(127.0366, 37.5000, 4326)::extensions.geography, '1168064000', '서울특별시 강남구 역삼1동');
insert into public.job_posts (id, store_id, title, hourly_wage, time_type, window_start, status) values
  ('20000000-0000-4000-8000-0000000000a2', '10000000-0000-4000-8000-0000000000a2', '탈퇴 테스트 공고', 12000, 'fixed', '10:00', 'matched');
insert into public.assignments (id, job_post_id, store_id, worker_id, hourly_wage, started_on) values
  ('40000000-0000-4000-8000-0000000000a2', '20000000-0000-4000-8000-0000000000a2', '10000000-0000-4000-8000-0000000000a2',
   'c0000000-0000-4000-8000-0000000000c2', 12000, current_date);

-- 로컬 테스트(PGlite)에서만 Storage 파일 목록을 흉내냅니다 (클라우드에서는 건너뜀)
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_storage_admin') then
    insert into storage.objects (bucket_id, name) values
      ('store-photos', '10000000-0000-4000-8000-0000000000a2/front.jpg'),
      ('shift-photos', '10000000-0000-4000-8000-0000000000a2/50000000-0000-4000-8000-0000000000a2/before.jpg'),
      ('store-photos', '10000000-0000-4000-8000-0000000000ff/other-store.jpg');
  end if;
end $$;

set local role service_role;

do $$
declare
  v_paths text[];
begin
  -- 알바가 탈퇴: 근무 중 매칭 종료 + 공고 다시 모집, 지울 매장 사진 없음
  select array_agg(p.bucket_id || ':' || p.name order by p.bucket_id || ':' || p.name) into v_paths
  from public.prepare_account_deletion('c0000000-0000-4000-8000-0000000000c2') p;
  assert v_paths is null, '매장이 없는 알바는 지울 매장 사진이 없어야 함';
  assert (select status from public.assignments
           where id = '40000000-0000-4000-8000-0000000000a2') = 'ended', '탈퇴하는 알바의 근무 중 매칭은 종료돼야 함';
  assert (select status from public.job_posts
           where id = '20000000-0000-4000-8000-0000000000a2') = 'open', '그 공고는 다시 모집 중이 돼야 함';

  -- 사장님이 탈퇴: 내 매장 사진만 지울 목록에 (로컬에서만 확인)
  if not exists (select 1 from pg_roles where rolname = 'supabase_storage_admin') then
    select array_agg(p.bucket_id || ':' || p.name order by p.bucket_id || ':' || p.name) into v_paths
    from public.prepare_account_deletion('a0000000-0000-4000-8000-0000000000a2') p;
    assert v_paths = array[
      'shift-photos:10000000-0000-4000-8000-0000000000a2/50000000-0000-4000-8000-0000000000a2/before.jpg',
      'store-photos:10000000-0000-4000-8000-0000000000a2/front.jpg'
    ], '사장님 탈퇴 시 내 매장 사진만 지울 목록에 나와야 함';
  end if;
end $$;
reset role;

rollback;

select '✅ 2단계 점검 통과 — 테스트 데이터는 모두 되돌렸습니다.' as result;
