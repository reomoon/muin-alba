# 2단계 준비: 로그인·동네 인증 설정

앱 코드를 만들기 전에 사장님(개발자)이 직접 해야 하는 콘솔 설정입니다.
**키·비밀번호는 채팅이나 코드에 붙여넣지 마세요.** 콘솔 → Supabase 대시보드로 바로 옮기거나, 나중에 `app/.env`에만 적습니다.

아래에서 `<프로젝트ID>`는 Supabase 대시보드 주소 `supabase.com/dashboard/project/` 뒤의 영문 20자입니다.
Supabase 로그인 콜백 주소: `https://<프로젝트ID>.supabase.co/auth/v1/callback`

---

## 1. Flutter 개발 환경

1. Android Studio 설치 → 첫 실행 마법사에서 기본값으로 SDK 설치
2. Android Studio > Settings > Languages & Frameworks > Android SDK > **SDK Tools** 탭 → **Android SDK Command-line Tools** 체크 → Apply
3. Device Manager에서 에뮬레이터 만들기 (시스템 이미지는 **Google Play** 표시가 있는 최신 버전)
4. VS Code에 Flutter 확장 설치 → `Ctrl+Shift+P` → `Flutter: New Project` → **Download SDK** → `C:\dev` 같은 공백 없는 폴더 → "Add SDK to PATH"
5. VS Code 재시작 후 터미널에서 `flutter doctor --android-licenses` (전부 y) → `flutter doctor`

## 2. 카카오 (로그인 + 동네 이름 찾기)

[developers.kakao.com](https://developers.kakao.com) → 내 애플리케이션 → 애플리케이션 추가하기 (앱 이름: 우리동네무인알바)

1. **제품 설정 > 카카오 로그인 > 일반**: 사용 설정 **ON**
2. **앱 > 플랫폼 키 > REST API 키** (로그인과 동네 이름 찾기에 같이 씀). 키를 눌러 들어가서:
   - **카카오 로그인 리다이렉트 URI**: `https://<프로젝트ID>.supabase.co/auth/v1/callback` 등록
   - **클라이언트 시크릿**: 코드 생성 → 사용 **ON**
   (콘솔 개편으로 리다이렉트 URI·클라이언트 시크릿이 카카오 로그인 메뉴에서 REST API 키 아래로 옮겨졌습니다)
3. *(번호 유지용: 보안 메뉴는 2번으로 합쳐짐)*
4. **카카오 로그인 > 동의항목**
   - 닉네임: 필수 동의
   - 프로필 사진: 선택 동의
   - 카카오계정(이메일): 설정할 수 있으면 켜기. 비즈 앱 전환이 필요하다고 나오면 개인 개발자 비즈 앱으로 전환 (사업자 없이 가능)
5. **카카오맵(지도·로컬)** 사용 설정이 보이면 **ON**. 꺼져 있으면 동네 이름 찾기가 "disabled OPEN_MAP_AND_LOCAL service" 오류로 실패합니다.

## 3. 구글 로그인

[console.cloud.google.com](https://console.cloud.google.com) → 새 프로젝트 `muinalba`

1. **OAuth 동의 화면 (Google Auth Platform)**
   - 대상: 외부(External), 앱 이름: 우리동네무인알바, 지원 이메일: 본인
   - **테스트 사용자**에 본인 Gmail 추가 (앱 게시 전에는 테스트 사용자만 로그인 가능)
2. **클라이언트(사용자 인증 정보) → OAuth 클라이언트 ID 만들기**
   - 유형: **웹 애플리케이션**
   - 승인된 리디렉션 URI: `https://<프로젝트ID>.supabase.co/auth/v1/callback`
   - 만들기 → 클라이언트 ID와 클라이언트 보안 비밀번호 확인

## 4. Supabase 대시보드

1. **Authentication > Sign In / Providers**
   - **Kakao** 켜기 → Client ID: 카카오 **REST API 키**, Client Secret: 카카오 **Client Secret**
   - **Google** 켜기 → Client ID / Client Secret: 구글에서 만든 값
2. **Authentication > URL Configuration > Redirect URLs** → `com.muinalba.app://login-callback` 추가
3. **Edge Functions > Secrets** → 이름 `KAKAO_REST_API_KEY`, 값: 카카오 REST API 키
   (터미널에 키를 치면 명령 기록에 남으니 대시보드에서 넣는 걸 권장)

## 5. 서버 변경 적용 (VS Code 터미널)

```
npx supabase db push --remote
npx supabase functions deploy neighborhood delete-account --use-api
```

- `db push`: 2단계 마이그레이션 1개 → `Y`
- `functions deploy`: 동네 인증·회원 탈퇴 함수 업로드

적용 확인: SQL Editor에 `supabase/tests/step2_check.sql` 전체를 붙여넣고 Run → `✅ 2단계 점검 통과`

## 6. 네이버 지도

NCP 콘솔 → Application Services → Maps → Application 등록 → **Dynamic Map** → Android 앱 패키지 이름 `com.muinalba.app` → **Client ID** 확인 (나중에 `app/.env`에 적음)

---

## 7. 앱 설정값 넣고 실행

1. `app/.env` 파일을 열어 빈칸 채우기 (git에 올라가지 않음)
   - `SUPABASE_PUBLISHABLE_KEY`: Supabase 대시보드 > Project Settings > API Keys > **Publishable key** (`sb_publishable_`로 시작)
   - `NAVER_MAP_CLIENT_ID`: 6번에서 받은 Client ID (비워 두면 지도 자리에 안내 상자만 보임)
2. 에뮬레이터 켜기: Android Studio > Device Manager > ▶ (또는 터미널 `flutter emulators --launch Medium_Phone_API_37.0`)
3. VS Code 왼쪽 **실행 및 디버그** → 위쪽 목록에서 **우리동네무인알바** → ▶ (F5)

에뮬레이터 위치 바꾸기: 에뮬레이터 옆 `⋯` (Extended controls) > Location > 지도에서 동네 검색 → **Set location**

## 확인할 것 (2단계 테스트)

1. 로그인 화면 → **카카오로 시작하기** → 브라우저에서 로그인 → 앱으로 돌아옴
2. 처음 설정: 닉네임 확인, 필수 약관 3개 체크 → **시작하기**
3. 역할 선택: **알바생** 선택 → **다음**
4. 동네 인증: 위치 권한 허용 → "OO동 맞나요?" → **OO동으로 인증하기** → 홈의 공고 탭 위에 동네 이름
5. 내 정보 탭: 역할 바꾸기(사장님 추가) → **사장님으로 보기** 전환 → 하단 탭이 사장님용 5개로 바뀜
6. 로그아웃 → 다시 **Google로 시작하기**로 로그인되는지
7. (마지막에) 회원 탈퇴 → 로그인 화면으로 돌아옴 → Supabase Table Editor `profiles`에서 내 행이 없어졌는지

DB에서 확인: Table Editor > `user_consents`(약관 동의 3~4행), `worker_neighborhoods`(내 동네 1행), `location_access_logs`(위치 확인자료)
