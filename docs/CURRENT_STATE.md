# docs/CURRENT_STATE.md — P0 현황 파악 (실측)

> 2026-06-13 시점, 저장소 코드 직접 확인. 멀티테넌트 전환 전 단일 테넌트(명지대) 기준.
> 추정이 아니라 코드에서 확인한 사실만 기록. 이후 작업 시 변경되면 갱신.

## 1. 파일 구조
- **학생용 페이지(`*.html`)**: index, intro, notice, library, calendar, consult, companies, cases, faq, qna, vote, survey, company-survey, mycompany, install, privacy, rls-check.
- **관리자 콘솔**: `admin.html` (≈151KB, 단일 거대 파일 — 리팩터 공수 큼).
- **공용 스크립트**: `app.js`(ES 모듈, 공용 도우미), `config.js`(센터/앱 설정 — "한 곳만 고치면 됨"), `survey-ui.js`, `styles.css`(≈45KB).
- **PWA**: `manifest.json`, `sw.js`, `firebase-messaging-sw.js`.
- **SQL 마이그레이션**: `sql/01~18_*.sql`(증분, 멱등) + `sql/ALL_IN_ONE.sql`(통합본) + `sql/README.md`.
- 정적 자산: `assets/`, `icons/`, `files/`.

## 2. 인증·신뢰 모델
- 클라이언트는 **Supabase anon(publishable) 키**로만 접속(`app.js`의 `createClient(SUPABASE_URL, SUPABASE_ANON_KEY)`).
- **학생/지원자/기업담당자: 로그인 없음.** 신원 = `localStorage('ilhak_profile')`(이름·target_type·job_key·company·type1·manager 등). 기기 단위.
- **관리자: Supabase Auth 로그인.** `admin.html`에서 `supabase.auth.signInWithPassword` + `getSession`/`signOut`. 즉 관리자만 authenticated 사용자.
- 민감 작업은 `SECURITY DEFINER` RPC로만 수행(예: `refresh_push_token`, `verify_*`, 통계/해시 RPC 등 다수).

## 3. 데이터베이스 (Supabase, 미국 리전 `ummuyzqyanrearbzgqyp`)
- **확인된 테이블**: registrations, push_tokens, student_codes, company_codes, company_contacts, company_info, company_stages, company_survey_responses, job_postings, qna_posts, success_cases, surveys, survey_answers, polls, poll_votes, verify_attempts (+ rls-check가 가정하는 students, push_logs, consultations, consultation_messages, survey_responses, deletion_log, sync_log, notice_recipients, notices, library, calendar_events, jobs, companies).
- **center_id / tenant 개념 전무** (`grep -i center sql/` → 0건).
- **RLS — 관리자 갓모드**: `for all to authenticated using (true) with check (true)` 가 03/04/05/02/07/ALL_IN_ONE 등 다수. → 어떤 관리자든 전 데이터 접근.
- **RLS — 공개 콘텐츠**: 일부 `select to public using (true)`/`published=true`(예: 17_polls의 "anyone read polls").
- **프로젝트 특이점**: publishable 키에서 `to authenticated` 정책이 안 먹는 전례 → `to public` + `auth.uid()` 조건을 쓰는 규칙(`sql/09_admin_extras.sql`, `sql/12_company_contacts.sql` 주석).
- **PII 보호**: registrations·push_tokens 등엔 anon SELECT 정책을 주지 않아 직접 접근 차단(강점).

## 4. RLS 자가점검 (`rls-check.html`)
- anon 키로 각 테이블을 몰래 읽어 **차단=PASS / 읽힘=FAIL** 판정.
- `MUST_BE_BLOCKED` = students, registrations, push_logs, push_tokens, consultations, consultation_messages, survey_responses, deletion_log, sync_log, notice_recipients, company_contacts, survey_answers, poll_votes, company_info.
- `PUBLIC_OK` = notices, library, calendar_events, jobs, companies, surveys, polls.
- **규칙: 새 테이블 추가 시 이 목록에 등록하고 재점검.**

## 5. `config.js` (정적 단일 센터 — 전부 명지대 하드코딩)
- Supabase URL/anon 키, CENTER_NAME='일학습병행 공동훈련센터', APP_TITLE.
- 개인정보: PRIVACY_OFFICER='권순천 (일학습병행운영팀)', 연락처 cherry905@mju.ac.kr / 031-324-1228, 시행일 2026.6.11, 보유기간, 국외이전='Supabase Inc.(미국), Google LLC(미국)'.
- `JOBS`(14직무, 명지대 학과 매핑), `COMPANIES`(25개 시드), `TYPES`/`MANAGERS`(권순천·김성훈·차민정·노혜정·길은경)/`STATUSES`, `COMPANY_STAGES`(8단계), `COMPANY_SURVEYS`(교사/HRD 만족도 문항).
- `FIREBASE_CONFIG`(projectId `mjuipp`), `FCM_VAPID_KEY`, `PUSH_KICK_URL`(개인 Google Apps Script `/macros/s/.../exec`).
- ※ 위 anon/Firebase/VAPID 키는 **공개용(노출 안전)**. service_role 키는 레포·클라에 없음(정상).

## 6. 타게팅·매칭 로직 (`app.js`)
- 공지/자료/일정 타게팅: `matchSel`/`noticeMatches`가 target_type·job_key·company·type1·manager로 매칭.
- 회사명은 `normCo`(㈜·(주)·공백 제거)로 **문자열 정규화 매칭** → 센터 간 동명 충돌 위험.
- 센터 파라미터·필터 없음.

## 7. 스토리지 (`admin.html`)
- 자료실 파일을 `supabase.storage.from('library').upload(...)` 후 **`getPublicUrl`로 공개 링크** 생성. 비공개/서명 URL/센터 경로 없음.

## 8. 푸시·인프라
- FCM 웹 푸시(`firebase-messaging-sw.js`) + 단일 Firebase `mjuipp`.
- 공지 발행 시 `PUSH_KICK_URL`(개인 Google 계정 Apps Script)을 깨워 즉시 발송, 평시 5분 트리거.
- 호스팅: GitHub Pages(`cherry905-boop/-_-`) 정적 단일 배포. 코드 배부·메일 수기(`mailto:`).
- `manifest.json` `start_url:"./index.html"` — 센터 파라미터 미보존.

## 8b. 라이브 검증 (2026-06-14, 운영 프로젝트 `ummuyzqyanrearbzgqyp`, 공개 anon 키, 읽기 전용)
- **PII 차단 PASS(14/14):** students·registrations·push_logs·push_tokens·consultations·consultation_messages·survey_responses·deletion_log·sync_log·notice_recipients·company_contacts·survey_answers·poll_votes·company_info → anon 전부 '차단됨'. **운영 PII 보호 정상.**
- **공개 콘텐츠 정상:** notices·library·calendar_events·jobs·companies·surveys·polls 읽기 가능(의도된 공개).
- **마이그레이션 미적용 확인:** `centers` 테이블 없음 / `center_id_for_slug` RPC 없음 / `notices.center_id` 컬럼 없음 → `getCenterId()` = null → **내 멀티테넌트 코드가 폴백(스코프 미적용)으로 동작 = 파일럿과 동일(회귀 없음) 라이브 확인.**
- **미검증(스테이징 필요):** 멀티테넌트 RLS 교차센터 격리는 `sql/19~21`을 DB에 적용해야 검증 가능. 운영(실 PII)엔 적용하지 않음 → 별도 스테이징 프로젝트 필요.

## 9. 결론
보안 기본기(anon 차단 + SECURITY DEFINER RPC + 자가점검)는 견고하나, **단일 테넌트·개인 계정·수기 의존**이 곳곳에 박혀 있음. 멀티테넌트 전환의 본질 = 이 개인·수기·단일 의존을 '조직 계정이 소유한 자동화 인프라 + center_id 격리'로 옮기는 것. 다음 작업 = `docs/PLAN.md` P1(센터 컨텍스트)부터 계획-동의-구현.
