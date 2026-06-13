# docs/PLAN.md — 멀티테넌트·개인정보 빌드 스펙 (v4)

> Claude Code가 이 문서만 보고도 앱을 단계별로 확장할 수 있도록 작성. 절대 규칙은 `CLAUDE.md` 참조.
> 본 스펙의 출처(사업·전략 배경): Claude.ai 공유 대화. 사업 방향 요약은 §0.

## §0. 방향 (왜 이걸 만드는가)
- **목표 제품:** 254개 공동훈련센터(4년제 27·비고교 125·고교 129)가 함께 쓰는 멀티테넌트 표준 플랫폼.
- **사업 모델:** **센터는 무료 + 공동훈련센터 지원단(한기대)에 단일 B2G 계약(IP 이전/라이선스 + 운영·유지보수)으로 과금.** (수익은 일회성 IP보다 운영 계약에 있음.)
- **시장 진입:** 명지대(+1~2곳) 파일럿으로 트랙션 → '작동 제품 + IP + 제안'으로 지원단 접근.
- **제약(법적):** 재직 중 본인 사업자/공동창업 운영·명지대 영리판매·동료 센터 개인판매는 피함. 인프라 소유자=창작자이되 **조직/사업 계정 + 연속성 장치** 전제.
- 위 모든 작업의 코드 측 검증 기준: **"A센터 사용자가 B센터 데이터 0건."**

---

## §1. 현 구조 사실 목록 (제품화의 걸림돌)
P0(`docs/CURRENT_STATE.md`)에 실측 결과가 정리되어 있음. 핵심만:

| # | 사실 | 영향 |
|---|------|------|
| 1 | 공개읽기 테이블(notices·library·jobs·companies·success_cases·qna_posts·polls·surveys)에 **center_id 없음** | A센터 anon이 B센터 콘텐츠 조회 — **최우선** |
| 2 | 관리자 RLS가 **갓모드** `for all to authenticated using (true)` (sql 다수) | 어떤 센터 관리자든 전 센터 PII 열람 |
| 3 | 학생 등은 **비로그인**(anon + `localStorage('ilhak_profile')`), 민감 작업은 `SECURITY DEFINER` RPC | `auth.uid()` 학생 RLS 불가 → 센터 인지 RPC 필요 |
| 4 | `config.js`가 **정적 단일 센터**(CENTER_NAME·JOBS·COMPANIES·MANAGERS·PRIVACY_*·FIREBASE `mjuipp`·PUSH_KICK_URL 하드코딩) | 센터별 값을 DB로 옮겨야 함 |
| 5 | RPC가 **센터 무인지**(이름/코드만 매칭, `app.js`의 `normCo` 문자열 매칭) | 센터 간 동명 기업·코드 충돌 |
| 6 | 데이터 **미국 리전**(Supabase `ummuyzqyanrearbzgqyp`), 처리방침·보호책임자 명지대 단일 | 서울 리전 + 센터별 거버넌스 필요 |
| 7 | 푸시 = **개인 Google 계정 Apps Script** + 단일 Firebase `mjuipp` + `PUSH_KICK_URL`, 5분 트리거 | 버스팩터·할당량 → 조직 계정 + 자동화 |
| 8 | 호스팅 = **개인 GitHub Pages** 단일 정적 배포, 코드배부·메일 수기 | 운영 주체 소유 도메인·셀프서비스 프로비저닝 |
| 9 | 스토리지 = library **단일 공개 버킷** + `getPublicUrl`(`admin.html`) | 센터별 경로 + 비공개 버킷 + 서명 URL |
| 10 | **센터 컨텍스트 개념이 코드에 없음**. `manifest.json` `start_url:"./index.html"` → `?center=`로 들어와도 PWA 설치 시 센터 유실 | 센터 식별·고정 필요 |
| 11 | 실(實)계정 없음(localStorage 프로필뿐) | 다기기·복구·지원 디버깅 불가 |
| 12 | 노션 DB로 가입코드 배부·가입자 관리(개인 작업) | 인앱 관리자 대시보드 + CSV 일괄등록으로 |

### 보존할 강점 (회귀 금지)
- PII 테이블에 anon 정책 미부여(직접 접근 전면 차단), 민감 조회는 `SECURITY DEFINER` RPC로만, 공개 콘텐츠만 anon.
- `rls-check.html` 자가점검(anon으로 MUST_BE_BLOCKED 테이블을 몰래 읽어 FAIL 잡기).
- rate limit(`verify_attempts`), 혼동문자 제외 코드, 멱등 마이그레이션, 친절한 에러 변환(`friendlyError`), a11y·스켈레톤·인앱브라우저 감지·iOS 배지.

---

## §2. 인증·신뢰 모델 (반드시 준수)
- **관리자만 Supabase Auth 로그인**(`admin.html`의 `signInWithPassword`). 관리자 권한·센터는 **`admin_users` 매핑 테이블**(user_id → role ∈ {super_admin, center_admin} → center_id)로 결정하고 RLS가 강제.
- **학생/지원자/기업담당자는 비로그인 유지.** 센터 귀속은 '가입 시 기기↔센터 바인딩 + 센터 인지 RPC'로 처리하고, **클라이언트가 보낸 center_id는 신뢰하지 않음**(코드·토큰에서 서버가 도출).
- RLS 작성 시: publishable 키에서 `to authenticated`가 안 먹는 전례 → `to public` + `auth.uid()`/RPC 조건 패턴(`sql/09_admin_extras.sql` 참고).

## §3. 데이터 모델 (목표)
- **신규:** `centers`(id, name, slug, region, privacy_officer, retention 등 config.js의 센터별 값), `admin_users`(user_id, center_id, role).
- **기존 전 테이블에 `center_id` 추가**(registrations·push_tokens·student_codes·company_codes·company_stages·company_contacts·company_info·company_survey_responses·job_postings·polls·poll_votes·qna_posts·success_cases·surveys·survey_answers·notices·library·calendar_events 등). NOT NULL + FK(centers) 지향, 백필 = 기존 데이터 전부 명지대 센터로.
- 공개읽기도 `center_id = 현재센터`로 스코프. 시딩은 센터별 멱등.

## §4. RLS 정책 (목표)
- PII 테이블: anon 정책 없음 유지. 학생 경로는 센터 인지 `SECURITY DEFINER` RPC만 노출(RPC 내부에서 center 도출·검증).
- 관리자: 갓모드 제거. `center_admin` = `center_id = (select center_id from admin_users where user_id = auth.uid())` 행만. `super_admin` = 전체.
- 공개 콘텐츠: `select to public using (published = true and center_id = <요청 센터>)`.
- 새 테이블마다 `rls-check.html` 목록 갱신 + 점검 통과.

## §5. 7단계 빌드 (각 단계: 계획→동의→구현→AC 검증→rls-check)

> **진행 상태(2026-06-13):**
> - **P1 ✅ 완료·브라우저 검증.**
> - **P2 🟢 코드 완료 + RLS 격리 검증:** `admin.html` 센터별 업로드 경로 + `library.html` 서명기 연결(http 공개 URL 직링크=회귀 없음, path형만 서명기) + `sql/20`(비공개 버킷·경로 스코프 정책) + `supabase/functions/sign-library`. **검증:** ① library.html 라이브 mju 정상 렌더(서명기 분기 비활성), 콘솔 0. ② **AC(교차센터 차단) pglite로 증명** — 버킷 private, adminA는 `mju/`만·adminB는 `demo/`만·anon 0건 (`docs/VERIFICATION.md`). 남은 라이브 단계: 운영 버킷 private 전환 + 서명기 배포(`docs/DEPLOY.md` 4).
> - **P3 🟢 대부분 완료(폴백 우선):** `app.js loadCenterConfig()`(센터별 설정)+`privacy.html` 센터별 처리방침 + **공개읽기 센터 스코프** `app.js getCenterId()`(센터 uuid를 `center_id_for_slug` RPC로 1회 해석·캐시; 마이그레이션 전 RPC 부재 → null → 스코프 미적용 = 파일럿 동일). **9개 공개읽기 전 페이지 배선·브라우저 검증 완료:** `app.js`(공지 배지)·`library.html`·`notice.html`·`calendar.html`·`companies.html`·`cases.html`·`vote.html`·`survey.html`(목록+단건)·`mycompany.html`(자료+소식). 전부 mju 폴백 정상 렌더, 콘솔 0. (공개 콘텐츠라 클라 필터로 충분; PII 는 RLS(sql/21)·RPC 로 별도 강제.)
>   - **남은 P3(미검증·인프라/인증 의존):** CSV 일괄등록 UI(admin.html — 관리자 인증 필요라 미검증), JOBS/COMPANIES config→DB(현재 config.js 정적, 센터 추가 시 DB화 — admin 화면 필요).
> - **P4 🟢 부분 완료:** 센터별 처리방침(위 P3 폴백). 서울 리전 이전은 인프라(`docs/DEPLOY.md` 0).
> - **P5 🟢 RLS 격리 검증(라이브 적용 대기):** `sql/19`(centers·admin_users·center_id 백필·헬퍼)·`sql/21`(갓모드 제거·센터 스코프 RLS) — **pglite로 적용·검증 통과**: 갓모드 0개, adminA=mju만·adminB=demo만·super=전체·anon=PII 0건 (`docs/VERIFICATION.md`). `rls-check.html` 갱신. 남은 것: 라이브(스테이징/운영) 적용 + `admin_users` 등록(`docs/DEPLOY.md`), 관리자 화면 role 분기 UI(admin 인증 필요라 미검증).
> - **P7 ⛔ 인프라 의존:** 서명기 배포·조직계정·커스텀 도메인·푸시 이전 → `docs/DEPLOY.md` 5. (코드: Edge Function 작성 완료, 배포는 사용자.)
- **P0 — 현황 파악.** 스키마·프론트 데이터 접근부·인프라 의존을 실측해 `docs/CURRENT_STATE.md` 작성. (완료: 초안 존재, 작업 시작 시 갱신)
- **P1 — 센터 컨텍스트 + PWA 유지. ✅ 완료(2026-06-13).** `config.js` 상단 부트스트랩이 활성 센터를 `?center=slug > localStorage('ilhak_center') > 기본 'mju'` 로 해석·영속화(`window.CENTER_SLUG`). `app.js`에 `getCenter()`/`centerUrl()` 추가. 모든 페이지가 config.js를 먼저 로드하므로 16개 HTML 무수정으로 전 페이지 적용. 슬러그 화이트리스트(`^[a-z0-9-]{1,40}$`). **클라 미신뢰 명문화**: CENTER_SLUG는 표시·힌트용이고 데이터 귀속은 서버(초대코드 RPC)가 정함.
  - *AC:* 두 센터 URL로 진입 시 각자 자기 센터 컨텍스트 유지, 설치(PWA) 후에도 보존. → **검증됨**(로컬 http 서버 + 실제 브라우저): ?center=demo→demo·영속, 무파라미터 재방문→localStorage값 유지(PWA 재실행 등가), 초기화 후→mju, 잘못된 슬러그→mju, 순수해석기 6케이스 + 콘솔 에러 0.
  - *한계(→P7):* GitHub Pages 단일 오리진이라 같은 브라우저에서 센터 전환 시 localStorage 공유. 진짜 동시 다센터 분리는 센터별 오리진(서브도메인/커스텀 도메인)에서 — P7.
- **P2 — 스토리지 격리.** library 비공개 버킷 + 센터별 경로 + 서명 URL. `admin.html` 업로드/삭제/링크 경로 수정.
  - *AC:* 한 센터 파일 링크로 타 센터 파일 접근 불가.
- **P3 — config 정적값 DB화 + CSV 일괄등록.** JOBS·COMPANIES·MANAGERS·PRIVACY_* 등을 `centers`/센터별 테이블로. 노션 대체 인앱 대시보드 + CSV/엑셀 일괄등록. 타게팅 어휘 센터 스코프화.
  - *AC:* 명지대는 기존과 동일 동작(회귀 없음), 신규 센터는 자기 값만.
- **P4 — 센터별 거버넌스 + 서울 리전.** 데이터 서울 리전 이전, 센터별 처리방침·보호책임자(`privacy.html` 동적화), 위·수탁 구조 반영.
  - *AC:* 각 센터 처리방침이 자기 controller로 표시, 데이터 리전=서울.
- **P5 — 센터 셀프 개설 + 관리자 권한 분리.** `admin_users` 도입, 갓모드 제거, super/center_admin RLS, 신규 센터 프로비저닝 흐름.
  - *AC:* center_admin은 자기 센터만, super_admin은 전체. 교차 접근 0건.
- **P7 — 인프라 소유 정상화.** 푸시·호스팅을 개인 계정 → **조직/사업 계정**으로(개인 Gmail Apps Script·개인 GitHub Pages 제거), 센터 인지 발송, 최소 연속성 장치(문서·백업·비상 인계).
  - *AC:* 개인 소비자 계정 의존 0, 센터별 푸시 정확 발송.

> (P6은 커뮤니티 등 후순위 기능 자리. 스토어/네이티브(Capacitor)·커뮤니티(2층 구조: 격리 비공개 + 닉네임·센터라벨 공유)는 영업 이후.)

## §6. 작업 규칙 (요약 — 상세는 CLAUDE.md)
개인·외부 계정 의존 금지 / 공개 스토리지 URL 금지 / 센터 컨텍스트 고정·PWA 유지 / 센터별 멱등 시딩 / RLS 회귀 테스트(rls-check) 필수 / 클라 미신뢰 / 파일럿 보존.

## §7. 추적 매트릭스 (§1의 12개 사실 → 해소 단계)
1→P3 · 2→P5 · 3→P1·P5 · 4→P3 · 5→P3 · 6→P4 · 7→P7 · 8→P7 · 9→P2 · 10→P1 · 11→P5 · 12→P3
