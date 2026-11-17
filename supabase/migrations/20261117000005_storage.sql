-- =====================================================================
-- 1단계 ⑤ 사진 저장소 (Supabase Storage)
--  · 앱에서 긴 변 1280px · JPEG 로 압축해 올립니다 (파일당 2MB 제한).
--
--  버킷              공개   경로                              올리기·지우기          보기
--  shift-photos      X      {store_id}/{shift_id}/{파일}.jpg  진행 중 근무의 알바    그 알바 + 매장 사장님
--  store-photos      O      {store_id}/{파일}.jpg             매장 사장님            누구나(공개 URL)
--  community-photos  X      {post_id}/{파일}.jpg              글 작성자              사장님 회원
--
--  store-photos 는 공고에 노출되는 홍보용이라 공개입니다.
--  출입 비밀번호·CCTV 화면 등이 찍히지 않도록 앱 업로드 화면에서 안내합니다.
-- =====================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('shift-photos',     'shift-photos',     false, 2097152, array['image/jpeg']),
  ('store-photos',     'store-photos',     true,  2097152, array['image/jpeg']),
  ('community-photos', 'community-photos', false, 2097152, array['image/jpeg'])
on conflict (id) do nothing;

-- 경로의 n번째 부분을 uuid 로 꺼내기 (형식이 틀리면 null)
create or replace function private.path_uuid(p_name text, p_index integer)
returns uuid
language sql immutable
set search_path = ''
as $$
  select case
    when (string_to_array(p_name, '/'))[p_index]
         ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then ((string_to_array(p_name, '/'))[p_index])::uuid
  end;
$$;

-- 근무 사진에 접근할 수 있나? p_write = true: 올리기·지우기 / false: 보기
create or replace function private.can_access_shift_photo(p_name text, p_write boolean)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select cardinality(string_to_array(p_name, '/')) = 3
     and exists (
       select 1
       from public.shifts sh
       join public.stores s on s.id = sh.store_id
       where sh.id = private.path_uuid(p_name, 2)
         and sh.store_id = private.path_uuid(p_name, 1)
         and case
               when p_write then
                 sh.worker_id = (select auth.uid())
                 and sh.status = 'in_progress'
                 and private.has_feature(sh.store_id, 'photo_verification')
               else
                 sh.worker_id = (select auth.uid()) or s.owner_id = (select auth.uid())
             end
     );
$$;

-- 매장 사진을 관리할 수 있나? (매장 사장님)
create or replace function private.can_manage_store_photo(p_name text)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select cardinality(string_to_array(p_name, '/')) = 2
     and private.is_store_owner(private.path_uuid(p_name, 1));
$$;

-- 커뮤니티 사진을 관리할 수 있나? (글 작성자)
create or replace function private.can_manage_community_photo(p_name text)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select cardinality(string_to_array(p_name, '/')) = 2
     and private.is_post_author(private.path_uuid(p_name, 1));
$$;

revoke all on function private.path_uuid(text, integer)                   from public, anon;
revoke all on function private.can_access_shift_photo(text, boolean)      from public, anon;
revoke all on function private.can_manage_store_photo(text)               from public, anon;
revoke all on function private.can_manage_community_photo(text)           from public, anon;
grant execute on function private.path_uuid(text, integer)                to authenticated, service_role;
grant execute on function private.can_access_shift_photo(text, boolean)   to authenticated, service_role;
grant execute on function private.can_manage_store_photo(text)            to authenticated, service_role;
grant execute on function private.can_manage_community_photo(text)        to authenticated, service_role;

-- ── shift-photos ─────────────────────────────────────────────────────
create policy "shift-photos: read" on storage.objects for select to authenticated
  using (bucket_id = 'shift-photos' and private.can_access_shift_photo(name, false));
create policy "shift-photos: upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'shift-photos' and private.can_access_shift_photo(name, true));
create policy "shift-photos: delete" on storage.objects for delete to authenticated
  using (bucket_id = 'shift-photos' and private.can_access_shift_photo(name, true));

-- ── store-photos (보기는 공개 URL이라 정책 불필요. 아래 read 는 사장님의 관리용) ──
create policy "store-photos: owner read" on storage.objects for select to authenticated
  using (bucket_id = 'store-photos' and private.can_manage_store_photo(name));
create policy "store-photos: upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'store-photos' and private.can_manage_store_photo(name));
create policy "store-photos: delete" on storage.objects for delete to authenticated
  using (bucket_id = 'store-photos' and private.can_manage_store_photo(name));

-- ── community-photos ─────────────────────────────────────────────────
create policy "community-photos: read" on storage.objects for select to authenticated
  using (bucket_id = 'community-photos' and private.has_any_store());
create policy "community-photos: upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'community-photos' and private.can_manage_community_photo(name));
create policy "community-photos: delete" on storage.objects for delete to authenticated
  using (bucket_id = 'community-photos' and private.can_manage_community_photo(name));
