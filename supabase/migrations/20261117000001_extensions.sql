-- =====================================================================
-- 1단계 ① 확장 기능 · 내부 스키마
-- =====================================================================

-- PostGIS: 좌표(geography) 저장과 거리 계산(ST_DWithin · ST_Distance)
-- pg_cron · pg_net 은 실제로 쓰는 단계(4·5단계)에서 켭니다.
create extension if not exists postgis with schema extensions;

-- private: RLS 헬퍼·트리거 함수 전용 스키마.
-- API(PostgREST)에 노출되지 않으므로 앱에서 직접 호출할 수 없습니다.
create schema if not exists private;
grant usage on schema private to authenticated, service_role;
