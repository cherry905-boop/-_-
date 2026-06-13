# CLAUDE.md — 일학습병행 앱

> 이 파일은 매 세션 자동 로드됩니다. **최소·간결**하게 유지하고, 상세 계획·데이터 모델은 `@docs/PLAN.md`에 둡니다.

@docs/PLAN.md

## 제품 한 줄
일학습병행 공동훈련센터 학생 소통 앱(공지·자료·일정·상담·모집·설문·투표·FAQ). **현재 명지대 단일 테넌트** → 목표는 **멀티테넌트 표준 플랫폼**.

## 스택
- 프론트: 바닐라 JS 멀티페이지 PWA. 기능별 `*.html` + 공용 `app.js`(ES 모듈)·`config.js`·`styles.css`. 관리자 콘솔 = `admin.html`(단일 거대 파일).
- 백엔드: **Supabase**(Postgres + RLS + Storage + Auth). 마이그레이션 = `sql/01~18_*.sql`(증분, 멱등) + `sql/ALL_IN_ONE.sql`(통합본).
- 푸시: FCM(`firebase-messaging-sw.js`) + 현재는 개인 Google 계정 Apps Script 발송기(`PUSH_KICK_URL`).
- 배포: GitHub Pages 정적 호스팅.

## 절대 규칙 (위반 시 작업 중단하고 사용자에게 확인)
3. **학생·지원자·기업담당자는 비로그인**(anon + `localStorage('ilhak_profile')`). 그래서 `auth.uid()` 기반 학생 RLS는 불가. **민감 조회·쓰기는 `SECURITY DEFINER` RPC로만.** Supabase Auth 로그인(`signInWithPassword`)은 **관리자(`admin.html`)만**.
4. **PII 테이블엔 anon 정책을 절대 부여하지 않음** (registrations·push_tokens·push_logs·consultations·consultation_messages·survey_responses·survey_answers·poll_votes·company_contacts·company_info·notice_recipients·deletion_log·sync_log·students). 공개 콘텐츠 테이블만 anon SELECT(notices·library·calendar_events·jobs·companies·surveys·polls, 보통 `published=true`).
5. **새 테이블을 추가하면 반드시 `rls-check.html`의 `MUST_BE_BLOCKED` 또는 `PUBLIC_OK` 목록에 등록하고 점검을 통과시킨다.** RLS 회귀 테스트는 필수.
6. **관리자 갓모드 금지.** 현재 `for all to authenticated using (true)` 정책은 어떤 관리자든 전 센터 데이터를 봄 → `admin_users` 매핑으로 `super_admin`/`center_admin` 역할·센터를 제한.
7. **publishable 키에서는 `to authenticated` 정책이 안 먹는 전례**가 있음 → 정책은 `to public` + `auth.uid()` 조건 패턴으로 작성(`sql/09_admin_extras.sql` 주석 참고).
8. **공개 스토리지 URL 금지.** 현재 library 버킷이 `getPublicUrl`로 전체 공개(`admin.html`) → 센터별 경로 + **비공개 버킷 + 서명(signed) URL**.
9. **개인·외부 소비자 계정 의존 금지.** 푸시(개인 Gmail Apps Script·단일 Firebase `mjuipp`)·호스팅(개인 GitHub Pages)을 **조직/사업 계정**으로. 인프라 소유자는 창작자(권순천)이되 조직 계정으로 운영.
10. **멀티테넌트 검증 기준: "A센터 사용자가 B센터 데이터 0건."** 모든 테이블에 `center_id`, 공개읽기도 센터 스코프.
11. **마이그레이션은 멱등**(`if not exists`/`create or replace`), 시딩은 **센터별 멱등**(명지대 고유 시드로 타 센터를 덮지 않음).
12. **명지대 파일럿 동작을 깨지 않는다.** 검증된 단일 테넌트 흐름은 보존하며 확장.

## 작업 방식
- **코드 전에 계획 먼저.** 새 작업은 ① 관련 `@docs`/파일을 읽어 현황 요약 → ② 목표·제약·검증기준 명시한 **마이그레이션/구현 계획 제안** → ③ 동의 후 단계별 구현 → ④ 리뷰. "한 방에 다 만들어줘" 금지.
- **한 번에 한 단계.** `docs/PLAN.md`의 단계(P0→P1→…)를 하나씩. 새 작업 시작 시 `/clear`.
- 코드는 주변 코드의 한국어 주석·명명·관용을 따른다.
