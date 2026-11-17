# 우리동네무인알바

무인매장(무인카페·아이스크림·스터디카페 등) 사장님과 매장 근처에 사는 동네 알바생을 연결하는 앱입니다.
알바생은 하루 1시간 청소·정리·보충을 하고, 앱은 매칭과 근무 관리(위치 확인·사진·체크리스트·기록)를 제공합니다.

- 앱: Flutter (Android 우선) → `app/` (2단계에서 생성)
- 백엔드: Supabase만 사용 (Auth · Postgres + PostGIS · Storage · Edge Functions · pg_cron)

## 폴더

```
muin-search/
├─ app/                          Flutter 앱 (2단계)
├─ supabase/
│  ├─ config.toml                Supabase CLI 설정
│  ├─ migrations/                DB 변경 이력 (파일명 순서대로 적용)
│  │  ├─ …01_extensions.sql      PostGIS, private 스키마
│  │  ├─ …02_tables.sql          테이블·열거형·인덱스
│  │  ├─ …03_functions.sql       RLS 헬퍼 함수·트리거
│  │  ├─ …04_rls.sql             권한(GRANT)·RLS 정책
│  │  ├─ …05_storage.sql         사진 버킷·Storage 정책
│  │  └─ …06_reference_data.sql  설정값·요금제 기능표·업종별 체크리스트
│  └─ tests/
│     ├─ rls_check.sql           RLS 점검 (로컬·클라우드 SQL Editor 공용)
│     ├─ supabase_stubs.sql      로컬 테스트용 Supabase 흉내 (클라우드에 실행 금지)
│     └─ run.mjs                 npm run db:test 실행기
└─ package.json                  Supabase CLI·테스트 도구 버전 고정
```

## DB 한눈에 보기

| 영역 | 테이블 | 누가 보나 |
|---|---|---|
| 사용자 | `profiles` · `user_consents` · `profile_private`(연락처) · `worker_neighborhoods`(동네 인증) | 프로필 카드는 모두, 연락처는 매칭된 상대만, 동네 위치는 본인만 |
| 매장 | `stores` · `store_private`(출입 정보) · `store_photos` · `store_checklist_items` · `checklist_templates` | 사장님 + 근무·지원한 알바 + 인증 동네 1km 안의 알바 |
| 공고·매칭 | `job_posts` · `job_post_bookmarks` · `applications` · `assignments` · `reviews` | 공고는 사장님 + 1km 안의 알바, 지원·근무는 당사자만 |
| 근무 | `shifts` · `shift_checks` · `shift_photos` | 그 알바 + 매장 사장님 |
| 알림 | `device_tokens` · `notifications` | 본인만 |
| 커뮤니티 | `community_posts` · `community_comments` · `community_post_photos` · `community_post_likes` · `user_blocks` · `content_reports` | 매장을 등록한 사장님만 |
| 수익 구조 | `subscriptions` · `plan_features` · `app_config` | 구독은 사장님 본인 매장만 |
| 법적 기록 | `location_access_logs` (위치정보 수집·이용·제공 확인자료) | 본인 열람만 |

상태 변경(지원·수락·근무 시작/종료)은 앱이 테이블을 직접 고치지 않고 RPC 함수로만 합니다 (3·4단계).

## 준비

```
npm install
```

## DB 테스트 — 로컬 (Docker 불필요)

```
npm run db:test
```

메모리 안의 Postgres(PGlite + PostGIS)에 마이그레이션을 적용하고 `rls_check.sql`로 권한을 점검합니다.
auth·storage는 흉내낸 것이므로 최종 확인은 아래 클라우드 점검으로 합니다.

## 클라우드 Supabase에 적용

1. https://supabase.com/dashboard 에서 새 프로젝트 생성 (Region: Northeast Asia (Seoul)). DB 비밀번호는 따로 보관
   - Security: Enable Data API 켜기, Automatically expose new tables **끄기**, Enable automatic RLS 켜기
2. `npx supabase login`
3. `npx supabase link --project-ref <프로젝트 ID>` (대시보드 주소 `project/` 뒤의 영문)
4. `npx supabase db push --remote` (CLI 3.x는 `--remote` 없으면 로컬 Docker DB로 보냄)
5. SQL Editor에 `supabase/tests/rls_check.sql` 전체를 붙여넣고 Run → `✅ RLS 점검 통과`

PowerShell에서 `npx`가 "스크립트를 실행할 수 없으므로…"로 막히면 한 번만:
`Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned`

## 규칙

- 비밀값(키·토큰·비밀번호)은 코드에 넣지 않고 `.env`(커밋 금지) 또는 `supabase secrets`에만 둡니다.
- 이미 클라우드에 적용한 마이그레이션 파일은 고치지 않고, 바꿀 내용은 새 마이그레이션 파일로 추가합니다.
- 새 테이블에는 RLS를 켜고 `…04_rls.sql`처럼 GRANT·정책을 명시적으로 적은 뒤, `rls_check.sql`에 점검을 추가합니다.
- 반경·보관기간·최저시급·유료 잠금 같은 값은 `app_config` 테이블에서 바꿉니다. **최저시급은 매년 1월 1일에 갱신**해야 합니다.

## 진행 단계

- [x] 1단계: 프로젝트 구조, DB 스키마(마이그레이션), RLS
- [ ] 2단계: 로그인 + 역할 선택 + 동네 인증
- [ ] 3단계: 매장 등록 + 공고 + 지원/매칭
- [ ] 4단계: 근무 인증(사진·체크리스트) + 근무 기록
- [ ] 5단계: 푸시 알림
- [ ] 6단계: 커뮤니티 게시판
