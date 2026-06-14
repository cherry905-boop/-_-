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

## 10. 멀티테넌트 전환 진행 (sql/22~, /goal 자율모드 2026-06-14)
> 로드맵·단계표는 `docs/MULTITENANT.md`. 핵심 진단: 토대(sql/19·21)는 운영 적용됨, 비어있는 핵심 = **'center_id 서버 도출 경로'**(가입·관리자쓰기·발급이 center_id 미주입 → 신규행 NULL 고아).

- **0단계 토대 하드닝 — 🟢 코드+정적검증 완료 / 라이브·커밋 대기.**
  - `sql/22_baseline_hardening.sql`(신규): registrations RLS + anon insert 정책 박제(`to public with check(true)`, permissive=운영 무해·재구축 안전). registrations CREATE TABLE 은 여전히 대시보드만 → 스키마 덤프 캡처 남음.
  - `sql/08`: `delete from success_cases` 전체삭제에 다센터 가드(센터>1이면 중단, center_id 있으면 mju만) + NULL행 mju 귀속.
  - `sql/09` Section B: 버킷 `public=false`·`on conflict do nothing`, `library public read`(anon) 제거 → sql/20 안 덮음.
  - `rls-check.html` MUST_BE_BLOCKED += student_codes·company_codes·unverified_signups.
  - **대기(사용자):** 스테이징에 sql/22 적용 → rls-check 전항목 PASS, 학생 가입 1건 테스트, 커밋. (이 작업 환경엔 node/pglite·라이브 접근 없음 → 동적검증 불가.)
- **1단계 코드 센터 스코프 — 🟢 코드 완료 / 라이브·검증 대기.**
  - `sql/23_codes_center_scope.sql`(신규): student_codes person-uniq → `(center_id, name, phone) where active`. code 는 전역 unique 유지(센터 도출 근거).
  - **보정:** 회사 키(`company` PK)+사업자번호 자연키 전환은 **5단계로 통합**(사업자번호 컬럼 부재 + admin.html company upsert가 기본 PK 충돌에 의존 → 키 변경은 프론트 upsert 변경과 한 묶음).
- **2단계 가입·발급 RPC — 🟢 코드 완료(SQL+프론트) / 라이브·검증 대기.**
  - `sql/24_signup_issue_rpc.sql`(신규): verify_by_code·verify_code_solo·verify_company_code_solo 에 `center_id`·`center_slug` 추가(verify_student 호출·HRD 자동채움 보존, HRD 조회 센터 스코프화). `register_with_code`·`register_applicant`·`issue_student_code`·`issue_company_code` 신설 — 모두 SECURITY DEFINER, **center_id 서버 도출**(코드/슬러그/admin_users), 클라 center_id 미신뢰. registrations insert 는 `_insert_registration`(p_row 키 ∩ 실제 컬럼만 동적 insert → 가변 스키마·기본값 보존).
  - **프론트 전환 완료:** index.html doRegister·지원자 → register_with_code/register_applicant, admin.html issueCode·issueCoCode(일괄발급 포함) → issue_* RPC. 전부 **RPC 우선 + 함수없음/오류 시 기존 insert·발급 폴백**(회귀 0). 가입 성공 시 `center_slug`로 `localStorage('ilhak_center')` 센터 바인딩. **critical path라 스테이징 검증 필수.**
- **3단계 관리자 쓰기 center_id 자동주입 — 🟢 코드 완료(SQL) / 라이브·검증 대기.**
  - `sql/25_center_id_writes.sql`(신규): `_set_center_id_on_write` 트리거(super_admin=명시 center_id honor, center_admin=**클라값 무시·current_admin_center() 강제**) → 관리자-쓰기 **13개** 테이블(student_codes·company_codes·company_contacts·company_info·company_stages·job_postings·qna_posts·success_cases·surveys·polls·notices·library·calendar_events) BEFORE INSERT 부착. `sql/14` registrations admin read/delete 의 `auth.uid() is not null`(전센터 OR 구멍) → 센터 스코프 교체. `unverified_signups` anon insert 박제 + 센터 admin 정책.
  - **의도적 제외(중요):** registrations(register_* RPC가 처리)·poll_votes·survey_answers·company_survey_responses·consultations·consultation_messages·push_tokens·notice_recipients 등 **anon/학생/시스템 쓰기 테이블엔 트리거 미부착**(비관리자 insert 때 center null 덮어쓰기 방지). 이들 학생·기업 응답은 **부모(poll/survey)·토큰등록 RPC로 center 도출하는 보강이 별도 필요**(미구현, 2번째 센터 전). admin.html 콘텐츠 insert는 트리거가 자동 처리 → 무수정.
- **4단계 센터개설·역할게이팅 — 🟢 코드 완료(SQL+프론트) / 라이브·검증 대기.**
  - `sql/26_center_provisioning.sql`(신규): `create_center(slug,name,…)`·`seed_center(center_id)`(현재 빈 센터=no-op, mju 시드 복사 금지)·`grant_admin(email,slug,role)`(이메일→auth.users→admin_users upsert) — 전부 `is_super_admin()` 가드. `admin_users` super 한정 쓰기 정책 추가(본인행 select 정책은 유지).
  - **프론트 완료:** admin.html `refresh` role-aware(2096~) — `admin_users` 자기행 조회. **테이블 없음(미적용)=레거시 전체 콘솔 폴백**(미적용 DB 잠김 방지, prod엔 본인 super 매핑돼 잠김 없음), 매핑 존재+미매핑일 때만 `#noperm`(권한없음). super 전용 `sec-centers` 탭(나브 71·섹션 352)=create_center/grant_admin RPC 폼만. `applyRoleUI`가 super일 때만 탭 노출. **안전 속성:** UI 게이팅이 실패로 열려도 데이터는 sql/21 RLS가 센터 스코프로 강제 → blind 변경 안전(보안경계는 UI 아님).
- **5단계 명단 일괄등록 — 🟢 코드 완료(스키마+RPC+UI) / 라이브·검증 대기.**
  - `sql/27_roster_master_schema.sql`(신규, **추가만**): companies/students 에 center_id(+mju 백필, 19 배열 누락분), companies·company_codes·company_stages·company_info 에 `biz_no`(사업자번호) + `unique(center_id, biz_no) where biz_no is not null`. **company PK 무손상** → admin.html company upsert 무회귀.
  - **RPC 완료:** `sql/28_roster_bulk_rpc.sql` — `bulk_upsert_companies`(notion_id NOT NULL → 합성 `csv:센터:사업자`, biz_no/name 키로 갱신 후 신규 insert)·`bulk_upsert_student_roster`(학번 우선 → 이름+전화 중복 skip). 둘 다 center 서버주입(super=인자/center_admin=강제), 동적 insert(키∩실제컬럼), authenticated grant.
  - **UI 완료:** admin.html 가입자 탭 상단 CSV 업로드 카드 — 학생/기업 선택, 템플릿 다운로드, 한글 머리글→컬럼 매핑(이름/학번/휴대폰/소속기업/직무, 회사명/사업자번호), 미리보기(인식 행수·무시 열), bulk RPC 호출(함수없음 시 안내). 마스터 스키마(권순천 제공: companies=notion_id NOT NULL·id 없음, students=id PK·name_norm·student_no·job_keys[])에 정확히 맞춤.
  - **별도 micro(추후):** company_codes/stages/info 의 `company text PK`→`(center_id, biz_no)` 전환(biz_no 적재 + admin.html company upsert onConflict 전환 후).
