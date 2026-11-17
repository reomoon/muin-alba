-- =====================================================================
-- 로컬 테스트(PGlite) 전용: Supabase 가 기본으로 갖고 있는 역할·스키마를 최소한으로 흉내냅니다.
-- ⚠ 클라우드 DB 에는 실행하지 마세요. (npm run db:test 가 자동으로 사용)
-- =====================================================================

-- API 역할
create role anon nologin noinherit;
create role authenticated nologin noinherit;
create role service_role nologin noinherit bypassrls;

create schema if not exists extensions;
create schema auth;
create schema storage;

grant usage on schema public, extensions, auth, storage to anon, authenticated, service_role;

-- auth: 사용자 테이블과 auth.uid()
create table auth.users (
  id                 uuid primary key,
  email              text,
  raw_user_meta_data jsonb,
  raw_app_meta_data  jsonb,
  created_at         timestamptz default now()
);

create function auth.uid() returns uuid
language sql stable
as $$
  select nullif(
    coalesce(
      current_setting('request.jwt.claim.sub', true),
      (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
    ),
    ''
  )::uuid;
$$;
grant execute on function auth.uid() to anon, authenticated, service_role;

-- storage: 버킷·객체 테이블
create table storage.buckets (
  id                 text primary key,
  name               text not null,
  owner              uuid,
  public             boolean default false,
  file_size_limit    bigint,
  allowed_mime_types text[],
  created_at         timestamptz default now(),
  updated_at         timestamptz default now()
);
create table storage.objects (
  id         uuid primary key default gen_random_uuid(),
  bucket_id  text references storage.buckets (id),
  name       text,
  owner      uuid,
  metadata   jsonb,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
alter table storage.objects enable row level security;
grant all on storage.objects to anon, authenticated, service_role;
grant select on storage.buckets to anon, authenticated, service_role;

-- 클라우드 프로젝트의 'Automatically expose new tables'를 끈 상태와 같게 둡니다.
-- (새 테이블·함수에 API 역할 권한이 자동으로 붙지 않음 → 마이그레이션에서 GRANT를 빠뜨리면
--  로컬 테스트에서도 바로 실패합니다. 이 설정을 켠 프로젝트에서도 그대로 통과합니다.)
