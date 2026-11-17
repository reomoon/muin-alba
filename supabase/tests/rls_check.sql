-- =====================================================================
-- RLS 점검 스크립트
--   가짜 사용자 4명(사장A·사장B·알바W·알바X)과 매장·공고·근무를 만들고,
--   각자의 권한으로 무엇이 보이고 무엇이 막히는지 확인합니다.
--   마지막에 ROLLBACK 하므로 DB에 아무것도 남지 않습니다.
--
--   실행 방법
--   (1) 로컬:     npm run db:test
--   (2) 클라우드: Supabase 대시보드 > SQL Editor 에 이 파일 전체를 붙여넣고 Run
--
--   결과: 마지막에 '✅ RLS 점검 통과' 가 나오면 성공.
--         실패하면 어느 항목인지 메시지(예: 'W: 부산 공고는 안 보여야 함')와 함께 멈춥니다.
--
--   위치: 사장A 매장(강남) / 알바W 는 그 북쪽 약 500m / 알바X 는 약 10km / 사장B 매장(부산)
-- =====================================================================
begin;

-- ═════════════════════════════════════════════════════════════════════
-- 0. 로그인 전(anon)은 아무것도 못 읽음
-- ═════════════════════════════════════════════════════════════════════
set local role anon;
do $$ begin
  begin
    perform 1 from public.stores limit 1;
    assert false, 'anon: 로그인 전에는 테이블을 읽을 수 없어야 함';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- ═════════════════════════════════════════════════════════════════════
-- 1. 테스트 데이터 (관리자 권한으로 생성)
-- ═════════════════════════════════════════════════════════════════════
insert into auth.users (id, email, raw_user_meta_data) values
  ('a0000000-0000-4000-8000-000000000001', 'owner-a@test.invalid',  '{"name": "사장A"}'),
  ('b0000000-0000-4000-8000-000000000002', 'owner-b@test.invalid',  '{"name": "사장B"}'),
  ('c0000000-0000-4000-8000-000000000003', 'worker-w@test.invalid', '{"name": "알바W"}'),
  ('d0000000-0000-4000-8000-000000000004', 'worker-x@test.invalid', '{"name": "알바X"}');

do $$ begin
  assert (select count(*) from public.profiles where nickname in ('사장A', '사장B', '알바W', '알바X')) = 4,
    '회원가입 트리거: 프로필 4개가 자동으로 만들어져야 함';
end $$;

update public.profiles set is_owner = true
 where id in ('a0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000002');
update public.profiles set is_worker = true
 where id in ('c0000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-000000000004');

insert into public.stores (id, owner_id, name, category, address, location, region_code, region_name, created_at) values
  ('10000000-0000-4000-8000-00000000000a', 'a0000000-0000-4000-8000-000000000001', '테스트 무인카페', 'unmanned_cafe',
   '서울 강남구 테헤란로 152', extensions.st_point(127.0366, 37.5000, 4326)::extensions.geography,
   '1168064000', '서울특별시 강남구 역삼1동', now() - interval '30 days'),
  ('10000000-0000-4000-8000-00000000000b', 'b0000000-0000-4000-8000-000000000002', '테스트 아이스크림', 'ice_cream',
   '부산 부산진구 중앙대로 672', extensions.st_point(129.0597, 35.1578, 4326)::extensions.geography,
   '2623052000', '부산광역시 부산진구 부전2동', now() - interval '30 days');

do $$ begin
  assert (select count(*) from public.store_checklist_items where store_id = '10000000-0000-4000-8000-00000000000a') = 6,
    '매장 등록 트리거: 무인카페 기본 체크리스트 6개가 복사돼야 함';
end $$;

insert into public.store_private (store_id, access_note) values
  ('10000000-0000-4000-8000-00000000000a', '출입 비밀번호 1234*'),
  ('10000000-0000-4000-8000-00000000000b', '출입 비밀번호 5678*');

insert into public.job_posts (id, store_id, title, hourly_wage, time_type, window_start, window_end, status) values
  ('20000000-0000-4000-8000-0000000000a1', '10000000-0000-4000-8000-00000000000a', '마감 청소 (매칭 완료)', 12000, 'flexible', '22:00', '01:00', 'matched'),
  ('20000000-0000-4000-8000-0000000000a2', '10000000-0000-4000-8000-00000000000a', '주말 오전 정리',       12000, 'fixed',    '09:00', null,    'open'),
  ('20000000-0000-4000-8000-0000000000b1', '10000000-0000-4000-8000-00000000000b', '오전 정리',            11000, 'fixed',    '10:00', null,    'open');

insert into public.worker_neighborhoods (user_id, location, region_code, region_name) values
  ('c0000000-0000-4000-8000-000000000003', extensions.st_point(127.0366, 37.5045, 4326)::extensions.geography,
   '1168064000', '서울특별시 강남구 역삼1동'),
  ('d0000000-0000-4000-8000-000000000004', extensions.st_point(127.0366, 37.5900, 4326)::extensions.geography,
   '1129052500', '서울특별시 성북구 테스트동');

insert into public.applications (id, job_post_id, worker_id, message, status, decided_at) values
  ('30000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-0000000000a1',
   'c0000000-0000-4000-8000-000000000003', '걸어서 5분 거리예요', 'accepted', now());

insert into public.assignments (id, job_post_id, application_id, store_id, worker_id, hourly_wage, started_on) values
  ('40000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-0000000000a1', '30000000-0000-4000-8000-000000000001',
   '10000000-0000-4000-8000-00000000000a', 'c0000000-0000-4000-8000-000000000003', 12000, current_date);

insert into public.shifts (id, assignment_id, store_id, worker_id, work_date, status, started_at, start_distance_m) values
  ('50000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-00000000000a',
   'c0000000-0000-4000-8000-000000000003', current_date, 'in_progress', now(), 20);

insert into public.profile_private (user_id, phone) values
  ('a0000000-0000-4000-8000-000000000001', '01011110001'),
  ('c0000000-0000-4000-8000-000000000003', '01011110003'),
  ('d0000000-0000-4000-8000-000000000004', '01011110004');

insert into public.community_posts (id, author_id, category, region_code, region_name, title, body) values
  ('60000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001', 'tip',
   '1168064000', '서울특별시 강남구 역삼1동', '키오스크 오류 해결 팁', '전원을 껐다 켜면 대부분 해결돼요');

-- ═════════════════════════════════════════════════════════════════════
-- 2. 사장A (매장A 주인, 알바W와 매칭됨)
-- ═════════════════════════════════════════════════════════════════════
select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000001", "role": "authenticated"}', true);
set local role authenticated;

do $$ begin
  assert (select count(*) from public.stores) = 1,                 'A: 자기 매장 1곳만 보여야 함';
  assert (select count(*) from public.store_private) = 1,          'A: 자기 매장 출입 정보만 보여야 함';
  assert (select count(*) from public.job_posts) = 2,              'A: 자기 공고 2개만 보여야 함';
  assert (select count(*) from public.applications) = 1,          'A: 자기 공고에 온 지원 1건이 보여야 함';
  assert (select count(*) from public.shifts) = 1,                 'A: 자기 매장 근무 기록 1건이 보여야 함';
  assert (select count(*) from public.worker_neighborhoods) = 0,   'A: 알바의 동네 인증 위치는 안 보여야 함';
  assert (select count(*) from public.profile_private
           where user_id = 'c0000000-0000-4000-8000-000000000003') = 1, 'A: 매칭된 알바W 연락처는 보여야 함';
  assert (select count(*) from public.profile_private
           where user_id = 'd0000000-0000-4000-8000-000000000004') = 0, 'A: 매칭 안 된 알바X 연락처는 안 보여야 함';
  assert (select count(*) from public.community_posts) = 1,        'A: 커뮤니티 글이 보여야 함';
  assert private.can_access_shift_photo(
    '10000000-0000-4000-8000-00000000000a/50000000-0000-4000-8000-000000000001/before-1.jpg', false),
    'A: 자기 매장 근무 사진은 볼 수 있어야 함';
  assert not private.can_access_shift_photo(
    '10000000-0000-4000-8000-00000000000a/50000000-0000-4000-8000-000000000001/before-1.jpg', true),
    'A: 근무 사진 올리기는 알바만 가능해야 함';
  assert private.can_manage_store_photo('10000000-0000-4000-8000-00000000000a/1.jpg'),
    'A: 자기 매장 사진은 올릴 수 있어야 함';
  assert not private.can_manage_store_photo('10000000-0000-4000-8000-00000000000b/1.jpg'),
    'A: 남의 매장 사진은 올릴 수 없어야 함';
end $$;

do $$
declare
  v_rows integer;
  v_hint text;
begin
  update public.stores set name = '바꿔치기' where id = '10000000-0000-4000-8000-00000000000b';
  get diagnostics v_rows = row_count;
  assert v_rows = 0, 'A: 남의 매장을 수정할 수 없어야 함';

  delete from public.stores where id = '10000000-0000-4000-8000-00000000000a';
  get diagnostics v_rows = row_count;
  assert v_rows = 0, 'A: 근무 이력이 있는 매장은 삭제되지 않아야 함 (비활성화만)';

  begin
    insert into public.stores (owner_id, name, category, address, location, region_code, region_name)
    values ('b0000000-0000-4000-8000-000000000002', '가짜', 'other', '어딘가',
            extensions.st_point(127.0, 37.5, 4326)::extensions.geography, '0000000000', '어딘가');
    assert false, 'A: 남의 이름(owner_id)으로 매장을 등록할 수 없어야 함';
  exception when insufficient_privilege then null;
  end;

  begin
    update public.profiles set rating_avg = 5.0 where id = 'a0000000-0000-4000-8000-000000000001';
    assert false, 'A: 평점(rating_avg)을 직접 고칠 수 없어야 함';
  exception when insufficient_privilege then null;
  end;

  begin
    insert into public.job_posts (store_id, title, hourly_wage, time_type, window_start)
    values ('10000000-0000-4000-8000-00000000000b', '남의 매장 공고', 12000, 'fixed', '10:00');
    assert false, 'A: 남의 매장에 공고를 올릴 수 없어야 함';
  exception when insufficient_privilege then null;
  end;

  begin
    insert into public.job_posts (store_id, title, hourly_wage, time_type, window_start)
    values ('10000000-0000-4000-8000-00000000000a', '최저시급 미만', 9000, 'fixed', '10:00');
    assert false, 'A: 최저시급 미만 공고는 막혀야 함';
  exception when raise_exception then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'below_min_wage' then raise; end if;
  end;

  begin
    insert into public.job_posts (store_id, title, hourly_wage, time_type, window_start, window_end, work_minutes)
    values ('10000000-0000-4000-8000-00000000000a', '시간대가 너무 짧음', 12000, 'flexible', '10:00', '10:30', 60);
    assert false, 'A: 근무 시간보다 짧은 자유 시간대는 막혀야 함';
  exception when raise_exception then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'window_too_short' then raise; end if;
  end;
end $$;

-- A: 매장 사진 등록, 알바W 평가 → 평점 집계
insert into public.store_photos (store_id, storage_path)
values ('10000000-0000-4000-8000-00000000000a', '10000000-0000-4000-8000-00000000000a/1.jpg');
insert into public.reviews (assignment_id, reviewee_id, rating, comment)
values ('40000000-0000-4000-8000-000000000001', 'c0000000-0000-4000-8000-000000000003', 5, '꼼꼼하게 해 주세요');

do $$ begin
  assert (select rating_avg from public.profiles where id = 'c0000000-0000-4000-8000-000000000003') = 5.0
     and (select rating_count from public.profiles where id = 'c0000000-0000-4000-8000-000000000003') = 1,
    '평가 트리거: 알바W 평점이 5.0 (1건)으로 집계돼야 함';
end $$;
reset role;

-- ═════════════════════════════════════════════════════════════════════
-- 3. 알바W (사장A 매장 근처, 근무 중)
-- ═════════════════════════════════════════════════════════════════════
select set_config('request.jwt.claims', '{"sub": "c0000000-0000-4000-8000-000000000003", "role": "authenticated"}', true);
set local role authenticated;

do $$ begin
  assert (select count(*) from public.job_posts) = 2,              'W: 지원한 공고 + 1km 안 모집 공고 = 2개가 보여야 함';
  assert (select count(*) from public.job_posts
           where store_id = '10000000-0000-4000-8000-00000000000b') = 0, 'W: 부산 공고는 안 보여야 함';
  assert (select count(*) from public.stores) = 1,                 'W: 근처·근무 매장만 보여야 함';
  assert (select count(*) from public.store_private) = 1,          'W: 근무 확정된 매장의 출입 정보는 보여야 함';
  assert (select count(*) from public.store_checklist_items) = 6,  'W: 근무 매장 체크리스트가 보여야 함';
  assert (select count(*) from public.store_photos) = 1,           'W: 근무 매장 사진 목록이 보여야 함';
  assert (select count(*) from public.applications) = 1,          'W: 자기 지원만 보여야 함';
  assert (select count(*) from public.shifts) = 1,                 'W: 자기 근무만 보여야 함';
  assert (select count(*) from public.worker_neighborhoods) = 1,   'W: 자기 동네 인증만 보여야 함';
  assert (select count(*) from public.profile_private) = 2,        'W: 자기 + 매칭된 사장A 연락처만 보여야 함';
  assert (select count(*) from public.reviews) = 1,                'W: 자기가 받은 평가가 보여야 함';
  assert (select count(*) from public.community_posts) = 0,        'W: 매장 없는 사용자는 커뮤니티를 못 봐야 함';
  assert private.can_access_shift_photo(
    '10000000-0000-4000-8000-00000000000a/50000000-0000-4000-8000-000000000001/before-1.jpg', true),
    'W: 진행 중인 근무 사진은 올릴 수 있어야 함';
  assert not private.can_manage_store_photo('10000000-0000-4000-8000-00000000000a/2.jpg'),
    'W: 매장 사진은 올릴 수 없어야 함';
end $$;

-- W: 체크리스트 체크 (항목 문구가 자동 저장), 근무 사진 기록, 관심 공고 등록
insert into public.shift_checks (shift_id, checklist_item_id)
select '50000000-0000-4000-8000-000000000001', i.id
from public.store_checklist_items i
where i.store_id = '10000000-0000-4000-8000-00000000000a'
order by i.sort_order
limit 1;

insert into public.shift_photos (shift_id, kind, storage_path)
values ('50000000-0000-4000-8000-000000000001', 'before',
        '10000000-0000-4000-8000-00000000000a/50000000-0000-4000-8000-000000000001/before-1.jpg');

insert into public.job_post_bookmarks (job_post_id) values ('20000000-0000-4000-8000-0000000000a2');

do $$
declare
  v_hint text;
begin
  assert (select count(*) from public.shift_checks where title = '테이블·의자 닦기') = 1,
    'W: 체크할 때 항목 문구가 함께 저장돼야 함';
  assert (select store_id from public.shift_photos limit 1) = '10000000-0000-4000-8000-00000000000a',
    'W: 근무 사진의 매장 정보가 자동으로 채워져야 함';

  begin
    insert into public.shift_photos (shift_id, kind, storage_path)
    values ('50000000-0000-4000-8000-000000000001', 'after', '10000000-0000-4000-8000-00000000000b/x/after.jpg');
    assert false, 'W: 경로가 틀린 사진 기록은 막혀야 함';
  exception when raise_exception then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'invalid_photo_path' then raise; end if;
  end;

  begin
    insert into public.job_post_bookmarks (job_post_id) values ('20000000-0000-4000-8000-0000000000b1');
    assert false, 'W: 볼 수 없는 공고(부산)는 관심 등록이 안 돼야 함';
  exception when insufficient_privilege then null;
  end;

  begin
    insert into public.community_posts (category, region_code, region_name, title, body)
    values ('free', '1168064000', '서울특별시 강남구 역삼1동', '알바도 써볼까', '내용');
    assert false, 'W: 매장 없는 사용자는 커뮤니티에 글을 쓸 수 없어야 함';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- ═════════════════════════════════════════════════════════════════════
-- 4. 알바X (사장A 매장에서 약 10km)
-- ═════════════════════════════════════════════════════════════════════
select set_config('request.jwt.claims', '{"sub": "d0000000-0000-4000-8000-000000000004", "role": "authenticated"}', true);
set local role authenticated;

do $$ begin
  assert (select count(*) from public.job_posts) = 0,        'X: 1km 밖이라 공고가 안 보여야 함';
  assert (select count(*) from public.stores) = 0,           'X: 매장 정보도 안 보여야 함';
  assert (select count(*) from public.store_photos) = 0,     'X: 매장 사진 목록도 안 보여야 함';
  assert (select count(*) from public.shifts) = 0,           'X: 남의 근무 기록은 안 보여야 함';
  assert (select count(*) from public.shift_photos) = 0,     'X: 남의 근무 사진 기록은 안 보여야 함';
  assert (select count(*) from public.profile_private) = 1,  'X: 자기 연락처만 보여야 함';
  assert (select count(*) from public.profiles) = 4,         'X: 프로필 카드(닉네임·평점)는 모두 보여야 함';
  assert not private.can_access_shift_photo(
    '10000000-0000-4000-8000-00000000000a/50000000-0000-4000-8000-000000000001/before-1.jpg', false),
    'X: 남의 근무 사진은 볼 수 없어야 함';
end $$;
reset role;

-- ═════════════════════════════════════════════════════════════════════
-- 5. 사장B (부산 매장 주인)
-- ═════════════════════════════════════════════════════════════════════
select set_config('request.jwt.claims', '{"sub": "b0000000-0000-4000-8000-000000000002", "role": "authenticated"}', true);
set local role authenticated;

do $$ begin
  assert (select count(*) from public.stores) = 1,           'B: 자기 매장만 보여야 함';
  assert (select count(*) from public.store_private) = 1,    'B: 자기 매장 출입 정보만 보여야 함';
  assert (select count(*) from public.shifts) = 0,           'B: 남의 매장 근무 기록은 안 보여야 함';
  assert (select count(*) from public.shift_checks) = 0,     'B: 남의 매장 체크 기록은 안 보여야 함';
  assert (select count(*) from public.applications) = 0,     'B: 남의 공고 지원자는 안 보여야 함';
  assert (select count(*) from public.profile_private) = 0,  'B: 매칭된 사람이 없으니 연락처가 안 보여야 함';
  assert (select count(*) from public.community_posts) = 1,  'B: 커뮤니티 글이 보여야 함';
  assert not private.can_access_shift_photo(
    '10000000-0000-4000-8000-00000000000a/50000000-0000-4000-8000-000000000001/before-1.jpg', false),
    'B: 남의 매장 근무 사진은 볼 수 없어야 함';
end $$;

-- B: 내 동네에 글쓰기, 사장A 글에 댓글·공감
insert into public.community_posts (category, region_code, region_name, title, body)
values ('question', '2623052000', '부산광역시 부산진구 부전2동', '아이스크림 냉동고 추천', '어떤 모델 쓰세요?');
insert into public.community_comments (post_id, body)
values ('60000000-0000-4000-8000-000000000001', '좋은 팁 감사해요');
insert into public.community_post_likes (post_id) values ('60000000-0000-4000-8000-000000000001');

do $$ begin
  assert (select comment_count from public.community_posts where id = '60000000-0000-4000-8000-000000000001') = 1,
    '댓글 트리거: 댓글 수가 1로 집계돼야 함';
  assert (select like_count from public.community_posts where id = '60000000-0000-4000-8000-000000000001') = 1,
    '공감 트리거: 공감 수가 1로 집계돼야 함';

  begin
    insert into public.community_posts (category, region_code, region_name, title, body)
    values ('question', '1168064000', '서울특별시 강남구 역삼1동', '남의 동네 글', '내용');
    assert false, 'B: 내 매장이 없는 동네로는 글을 쓸 수 없어야 함';
  exception when insufficient_privilege then null;
  end;

  begin
    update public.community_posts set comment_count = 999 where id = '60000000-0000-4000-8000-000000000001';
    assert false, 'B: 댓글 수를 직접 고칠 수 없어야 함';
  exception when insufficient_privilege then null;
  end;
end $$;

-- B: 사장A 차단 → A의 글이 안 보여야 함
insert into public.user_blocks (blocked_id) values ('a0000000-0000-4000-8000-000000000001');
do $$ begin
  assert (select count(*) from public.community_posts
           where author_id = 'a0000000-0000-4000-8000-000000000001') = 0,
    'B: 차단한 사람의 글은 안 보여야 함';
end $$;
reset role;

-- ═════════════════════════════════════════════════════════════════════
-- 6. 유료 잠금 켜기 (paywall_enabled = true)
-- ═════════════════════════════════════════════════════════════════════
update public.app_config set value = 'true' where key = 'paywall_enabled';

-- 사장A: 두 번째 매장은 무료 한도(1곳) 초과 → 공고 등록이 잠겨야 함
select set_config('request.jwt.claims', '{"sub": "a0000000-0000-4000-8000-000000000001", "role": "authenticated"}', true);
set local role authenticated;

insert into public.stores (name, category, address, location, region_code, region_name)
values ('두 번째 매장', 'ice_cream', '서울 강남구 테헤란로 200',
        extensions.st_point(127.0400, 37.5010, 4326)::extensions.geography, '1168064000', '서울특별시 강남구 역삼1동');

do $$
declare
  v_hint text;
begin
  begin
    insert into public.job_posts (store_id, title, hourly_wage, time_type, window_start)
    select s.id, '두 번째 매장 공고', 12000, 'fixed', '10:00' from public.stores s where s.name = '두 번째 매장';
    assert false, 'A: 무료 한도를 넘는 매장은 공고 등록이 잠겨야 함';
  exception when raise_exception then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'feature_locked' then raise; end if;
  end;

  -- 첫 매장(무료 한도 안)은 여전히 공고 등록 가능
  insert into public.job_posts (store_id, title, hourly_wage, time_type, window_start)
  values ('10000000-0000-4000-8000-00000000000a', '첫 매장 추가 공고', 12000, 'fixed', '10:00');
end $$;
reset role;

-- 알바W: 무료 매장에서는 체크리스트·사진이 잠겨야 함
select set_config('request.jwt.claims', '{"sub": "c0000000-0000-4000-8000-000000000003", "role": "authenticated"}', true);
set local role authenticated;

do $$ begin
  begin
    insert into public.shift_checks (shift_id, checklist_item_id)
    select '50000000-0000-4000-8000-000000000001', i.id
    from public.store_checklist_items i
    where i.store_id = '10000000-0000-4000-8000-00000000000a'
    order by i.sort_order offset 1 limit 1;
    assert false, 'W: 무료 매장에서는 체크리스트 기록이 잠겨야 함';
  exception when insufficient_privilege then null;
  end;

  assert not private.can_access_shift_photo(
    '10000000-0000-4000-8000-00000000000a/50000000-0000-4000-8000-000000000001/after-1.jpg', true),
    'W: 무료 매장에서는 사진 올리기가 잠겨야 함';
end $$;
reset role;

-- 매장A 구독 시작 → 다시 열려야 함
insert into public.subscriptions (store_id, plan, status)
values ('10000000-0000-4000-8000-00000000000a', 'basic', 'active');

select set_config('request.jwt.claims', '{"sub": "c0000000-0000-4000-8000-000000000003", "role": "authenticated"}', true);
set local role authenticated;

insert into public.shift_checks (shift_id, checklist_item_id)
select '50000000-0000-4000-8000-000000000001', i.id
from public.store_checklist_items i
where i.store_id = '10000000-0000-4000-8000-00000000000a'
order by i.sort_order offset 1 limit 1;

do $$ begin
  assert (select count(*) from public.shift_checks) = 2, 'W: 구독 매장에서는 체크리스트 기록이 돼야 함';
  assert private.can_access_shift_photo(
    '10000000-0000-4000-8000-00000000000a/50000000-0000-4000-8000-000000000001/after-1.jpg', true),
    'W: 구독 매장에서는 사진을 올릴 수 있어야 함';
end $$;
reset role;

rollback;

select '✅ RLS 점검 통과 — 테스트 데이터는 모두 되돌렸습니다.' as result;
