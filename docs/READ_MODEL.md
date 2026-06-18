# docs/READ_MODEL.md — 데이터 원장 → 화면 분배(read-model) 설계 (v1, 설계만)

> **상태: 설계 확정용 문서. 코드 없음.** CLAUDE.md 규칙(코드 전 계획, 한 번에 한 단계)에 따라
> 분배 계약(인자·반환컬럼·타게팅 규칙·종착 RLS)을 먼저 못박는다. 구현은 §7 순서로 별도 세션.
> 절대 규칙은 `CLAUDE.md`, 단계 로드맵은 `docs/PLAN.md` 참조. 이 문서는 그 위의 **공개읽기 하드닝(P3.5)** 자리.

---

## §0. 원칙 — 원장 / 분배 / 화면 3층
- **원장(ledger):** `notices·library·calendar_events·surveys·polls·success_cases·job_postings·qna_posts·tasks …`
  는 **사실만** 적재. 화면용 판단(누구에게 보일지, 어떤 컬럼이 필요한지)을 테이블이 들고 있지 않는다.
- **분배(read-model RPC):** 화면은 원장을 직접 만지지 않고 **`SECURITY DEFINER` 조회 RPC**에서 필요한 만큼만 배급받는다.
  타게팅(대상자 매칭)과 컬럼 선별을 **서버에서** 끝낸다. 센터는 서버가 헤더에서 도출(클라 미신뢰).
- **화면:** 받은 행을 그대로 렌더. `target_scope/target_value` 같은 분배용 메타는 **화면에 내려가지 않는다.**

> 한 줄: **"화면이 원장을 다시 조립하지 않게, 서버에 배급소를 둔다."**

---

## §1. 현 구조 실측 (2026-06-17 기준)

### 1-1. 직접 조회 지도 (학생용 공개 페이지)
| 화면 | 직접 읽는 원장 | 클라에서 거르는 로직 | 이미 있는 분배 RPC |
|---|---|---|---|
| `notice.html:108` | `notices` (**body·target 통째로**) | `noticeMatches()` | `my_personal_notices`(토큰 전용) |
| `app.js:236` (홈/탭 배지) | `notices` (target만) | `noticeMatches()` | — |
| `library.html:165` | `library` | `visible`(job_key) | `my_targeted_library`(토큰) |
| `calendar.html:172` | `calendar_events` | `visible` | `my_targeted_calendar(_from)`(토큰) |
| `survey.html:101/131` | `surveys`(목록+단건) | `matchSel` | — |
| `vote.html:66` | `polls` | `matchSel` | `poll_results`/`submit_poll_vote` |
| `cases.html:91` | `success_cases` | (published만) | — |
| `companies.html:127` | `job_postings` | — | — |
| `mycompany.html:176/222` | `library`,`notices` | `isMyCompanyNotice` | `my_company_info`/`my_company_stage` |
| `faq.html:140` | `qna_posts` | — | — |
| `index.html` | `centers·tasks·companies·jobs` | — | 가입·검증 RPC 9종 |

### 1-2. 실측된 노출 (이 설계의 1순위 동기)
`sql/36_tighten_public_and_anon_policies.sql` 은 공개테이블 anon SELECT 를
`published=true AND center_id = request_center_id()` **까지만** 조였다. `target_scope` 는 안 막는다.
→ **타게팅 공지/설문/투표의 `body`·`target_value` 가 anon 에게 전부 내려가고**, 브라우저 `noticeMatches`/`matchSel`
이 "보여줄 것만" 고를 뿐이다. devtools/네트워크 탭에서 **남의 코호트·기업 대상 항목을 그대로 열람** 가능.
(개인 지정 공지·자료·일정은 이미 토큰 RPC `my_personal_notices`/`my_targeted_*` 로 분리돼 안전.)

### 1-3. admin 은 별개 (이 문서 범위 밖)
`admin.html` 은 30테이블·96직조회의 큰 배전반이지만 **`sql/21` 이 서버단 RLS
(`is_super_admin() OR center_id = current_admin_center()`)로 이미 센터를 강제**한다 → PII 누수 아님,
일관성·유지보수 과제. admin read-model 은 **별도 문서**로 분리한다(§8).

---

## §2. 재사용할 기존 인프라 (새로 만들지 말 것)
- **`request_center_id()`** (`sql/35:12`) — 요청 헤더 `x-ilhak-center` → `center_id`. `stable security definer`, anon 실행 가능,
  **클라가 보낸 center_id 를 신뢰하지 않는** 서버 도출의 단일 출처. read-model 의 센터는 전부 이걸로 도출.
- **`_jsonb_pick_keys(jsonb, text[])`** (`sql/35:180`) — 허용 키 화이트리스트. (쓰기용이지만 패턴 참고.)
- **`my_targeted_*` 패턴** (`sql/35:451~524`) — `returns setof <table>`, `where center_id = request_center_id()`,
  `v_center is null → return`(fail-closed), 토큰 해시(`substring(sha256,16)`)로 개인 매칭. **read-model 의 본보기.**
- **`poll_results` / `my_company_*`** (`sql/35:526~616`) — `coalesce(request_center_id(), current_admin_center())`
  로 학생·관리자 양쪽에서 호출되는 RPC 의 센터 도출 관용.
- **타게팅 규칙 원본** (`app.js:159 matchSel`, `app.js:171 noticeMatches`) — 아래 §4 에 서버 의사코드로 1:1 이식.

---

## §3. 분배 계약 — 공통 규칙 (모든 read-model RPC 공통)
1. **센터:** `v_center := request_center_id();` `if v_center is null then return; end if;` (fail-closed = 빈 결과).
   화면은 빈 결과를 `centerRequiredMessage()` 로 안내(현 `requireCenterId()` 흐름과 동일).
2. **클라 미신뢰:** center_id 인자를 받지 않는다. 프로필도 표시·매칭용 힌트일 뿐(권위 아님, 현 모델 유지).
3. **컬럼 선별:** 반환은 **화면 렌더에 필요한 컬럼만.** `target_scope/target_value/job_key('tokv:%')` 등 분배 메타는
   반환하지 않는다(over-fetch·노출 차단). → `returns table(...)` 로 컬럼을 명시(테이블 통짜 `setof` 지양).
4. **멱등·권한:** `create or replace` + `grant execute ... to anon, authenticated`. (PII 테이블엔 anon 정책 절대 부여 금지 — 규칙4.)
5. **타게팅은 서버에서:** §4 규칙을 RPC 내부에서 수행. 화면에서 `noticeMatches`/`matchSel`/`visible` **제거**가 목표.
6. **회귀 0:** 같은 프로필·센터에서 RPC 가 돌려주는 "보이는 집합"이 현재 클라 필터 결과와 **동일**해야 한다(§9 AC).

---

## §4. 타게팅 규칙 (클라 → 서버 1:1 이식)
`app.js` 의 두 함수를 SQL 로 옮긴다. 프로필은 RPC 인자 `p_profile jsonb`
(키: `job_key, company, type1, target_type, interest_jobs[], manager`)로 받는다.

### 4-1. `noticeMatches(n, profile)` → SQL
```
all     → 항상 true
job     → p_profile->>'job_key'      = target_value
company → normCo(p_profile->>'company') = normCo(target_value)
target  → p_profile->>'target_type'  = target_value
type    → p_profile->>'type1'        = target_value
custom  → matchSel(target_value::jsonb, p_profile, withManagers := true)
그 외    → false
```
- `normCo(s)` = `app.js:157` 정확 포팅 = `regexp_replace(s,'㈜|\(주\)|주식회사|\s','','g')`.
  ⚠️ **app.js normCo 는 `lower()` 를 하지 않는다**(`my_company_stage` 의 lower 포함식과 다름). 클라 회귀 0 이 우선이라
  `_norm_co(text)` 는 소문자화 없이 정의(소문자화하면 라틴 회사명에서 클라보다 과노출 = 회귀).

### 4-2. `matchSel(sel, profile, withManagers)` → SQL
```
sel.targets   ∋ profile.target_type                                  → true
sel.jobs      ∋ profile.job_key                                      → true
sel.jobs      ∩ profile.interest_jobs[] ≠ ∅                          → true
normCo(sel.companies[]) ∋ normCo(profile.company)                    → true
sel.types     ∋ profile.type1                                        → true
withManagers AND sel.managers ∋ trim(profile.manager)               → true
else false
```
- `withManagers` = 공지에서만 true(자료/일정은 false — 기존 동작 보존, `app.js:158` 주석 근거).
- 무프로필(anon, 키 없음): 모든 비-`all` 분기가 false → **`all` 항목만** 반환(현 동작과 동일).

### 4-3. 신뢰 모델 (중요 — 바뀌지 않음)
- 프로필은 **클라가 자기 신고**(localStorage)한 값. 지금도 그렇다. read-model 은 이 신뢰 수준을 **올리지도 낮추지도 않는다.**
- **개선점:** 오늘은 "전체 목록 + 브라우저 필터"라 한 번의 쿼리로 남의 대상 항목까지 보임.
  read-model 은 "내가 신고한 프로필에 맞는 행 + all" 만 받으므로 **캐주얼 노출이 사라진다**(열거하려면 프로필을 바꿔가며 반복 호출해야 하고, 그건 published 콘텐츠라 위협모델상 허용 범위).
- **진짜 비밀 항목**(특정인 지정)은 이미 토큰 경로(`my_personal_notices`, `my_targeted_*`)로 분리돼 있고 그대로 둔다.

---

## §5. 테이블별 명세 (우선순위 3티어)

### Tier 1 — 타게팅 노출 즉시 차단 (notices·surveys·polls)
지금 anon 이 타게팅 행을 통째로 보는 곳. **read-model RPC + anon SELECT 정책을 `target_scope='all'` 로 축소.**

**`public_notices(p_profile jsonb) returns table(id uuid, title text, body text, created_at timestamptz)`**
- `where published and center_id = request_center_id() and noticeMatches(...)` (§4-1), `order by created_at desc`.
- 화면(`notice.html`)·배지(`app.js:230 unreadNoticeCount`)가 호출. 개인공지는 기존 `my_personal_notices` 로 **병합 유지**.
- 대응 정책: `notices` anon SELECT → `published and center_id=req and target_scope='all'`
  (타게팅 행은 RPC 로만). `rls-check` 에 "anon 이 target_scope≠all 공지 0건" 강화 테스트 추가.

**`public_surveys(p_profile jsonb) returns table(id, title, description, created_at)`** + **`public_survey(p_id uuid, p_profile jsonb)`**(단건, `questions` 포함)
- `where open and center_id=req and (target_scope='all' or matchSel(target_value, p_profile, false))` (`survey.html:91` 규칙).
- 단건은 추가로 가시성 재확인(목록에 안 보이는 설문 id 직접 입력 차단).

**`public_polls(p_profile jsonb) returns table(id, question, description, options, multi, results_public, open, close_at, created_at)`**
- `where center_id=req and (target_scope='all' or matchSel(target_value, p_profile, false))` (`vote.html:51`).
- 집계는 기존 `poll_results`/`submit_poll_vote` 그대로.

### Tier 2 — 토큰 분리 점검 + 컬럼 정리 (library·calendar)
개인 지정 행(`job_key like 'tokv:%'`)은 이미 `my_targeted_*` 토큰 RPC 로 분리. **단, 평문 anon SELECT 가
`tokv:%` 행을 payload 로 흘리는지 확인 필요**(`library.html` `visible` 가 UI 에선 숨기지만 네트워크엔 노출).
- **`public_library(p_profile jsonb) returns table(id, title, kind, url, job_key, created_at)`** — `job_key not like 'tokv:%'` + (선택)job 필터.
- **`public_calendar(p_from date, p_profile jsonb) returns table(title, event_date, kind, job_key, memo)`** — 동일.
- 대응 정책: anon SELECT 에 `job_key not like 'tokv:%'` 추가(평문에서 토큰행 제외). 토큰행은 `my_targeted_*` 로만.
- 우선순위 Tier1 보다 낮음(이미 토큰 분리됨) — 컬럼 정리·payload 차단이 주목적.

### Tier 3 — 타게팅 없음, 일관성만 (cases·companies·job_postings·qna_posts·tasks)
대상자 개념이 없어 노출 위험은 낮음. 마지막에 얇은 `public_list` 래퍼로 통일(컬럼 선별·센터 스코프 일원화)하거나,
직조회 유지 허용. **여기서 멈춰도 보안상 문제 없음**(현 sql/36 센터 스코프로 충분).

---

## §6. 종착 상태 — RLS / rls-check 영향
- **원장 직조회 소멸의 의미:** 프론트 `.from('notices'|'surveys'|'polls')` 제거 →
  타게팅 행은 RPC 로만 도달. anon SELECT 정책을 `target_scope='all'`(+`job_key not like 'tokv:%'`)로 축소.
- **rls-check.html:** `notices·surveys·polls·library·calendar_events` 는 계속 `PUBLIC_OK`(전체가 막히면 안 됨).
  **단 테스트 강화:** anon 으로 ① `target_scope='all'` 행은 읽히고 ② 타게팅/`tokv` 행은 **0건**임을 둘 다 검증.
  (새 RPC 는 SECURITY DEFINER 라 `MUST_BE_BLOCKED` 목록과 무관 — 테이블 추가 아님.)
- **마이그레이션:** 멱등(`create or replace`, 정책 `drop ... if exists` 후 재생성). 제안 파일 번호:
  `sql/37_public_read_model.sql`(RPC + `_norm_co` 헬퍼) → `sql/38_tighten_targeted_select.sql`(anon SELECT 축소).
  **37 배포·프론트 전환·검증 후에 38** 을 적용한다(순서 역전 시 화면이 빈다).

---

## §7. 단계별 롤아웃 (한 번에 한 단계)
1. **수직 증명 = notices 1개.** `sql/37` 에 `_norm_co` + `public_notices` 만 추가 → `notice.html`·`app.js` 배지를
   RPC 로 전환(클라 `noticeMatches` 제거) → `mju` 동일동작 확인 + 콘솔 0 → `sql/38` 의 notices 분기로 anon SELECT 축소
   → `rls-check` 강화 테스트 통과. **여기까지가 1 PR.**
2. 검증되면 **surveys·polls** 동일 패턴 복제(같은 RPC 골격, matchSel 분기).
3. **library·calendar**(Tier2) — 토큰행 payload 차단 + 컬럼 정리.
4. **Tier3** 정리(선택).
각 단계: 계획→동의→구현→AC 검증(§9)→rls-check. mju 회귀 0 을 매 단계 확인.

---

## §8. 비목표 (이 문서 범위 밖)
- **admin read-model**(`admin_content_list` 등 96직조회 정리) — 별도 문서. RLS(`sql/21`)가 이미 격리하므로 긴급도 낮음.
- **`public_home_snapshot` / `public_app_context`** 같은 묶음 RPC — 화면 단순화엔 좋으나 분배 경계가 흐려져 후순위.
- 푸시·스토리지·리전·인프라 소유(`docs/PLAN.md` P7/P2/P4).

---

## §9. AC (검증 기준)
1. **회귀 0:** mju 의 임의 프로필(직무/기업/유형/지원자)에서 RPC 가 돌려주는 가시 집합 = 현 클라 필터 결과와 동일.
2. **노출 차단:** anon 으로 원장 직조회 시 `target_scope≠'all'` 공지·설문·투표 **0건**, `tokv:%` 자료/일정 **0건**.
3. **센터 격리:** A센터 헤더로 호출 → B센터 행 **0건**(`request_center_id()` 도출). 헤더 없음 → 빈 결과(fail-closed).
4. **컬럼 최소화:** 응답 payload 에 `target_scope/target_value` 부재.
5. **rls-check 강화 테스트 PASS**, 콘솔 에러 0.

---

## §10. 검증 결과 — 1단계(notices 수직 증명) (2026-06-17)
**구현물:** `sql/37_public_read_model.sql`(`_norm_co`·`_match_sel`·`_match_sel_text`·`public_notices`),
`sql/38_tighten_targeted_select.sql`(notices anon SELECT 축소), `notice.html`·`app.js unreadNoticeCount`(RPC 우선+폴백),
`rls-check.html`(타게팅 노출 점검 추가).

### A. RPC 로직 — pglite(WASM Postgres)로 `public_notices` 적용·측정 (자격증명 0)
GUC 스텁 `request_center_id()` + 2센터·15공지 시드. **`ALL_PASS: true`:**
- **패리티(AC §9.1):** 7개 프로필 전부 `public_notices(mju)` 결과 = 클라 `noticeMatches` 기대와 동일.
  (all/job/company/target/type/custom — `targets·jobs·interest_jobs∩·companies(normCo)·types·managers`, 잘못된 JSON→제외, 미발행→제외.)
- **센터격리(AC §9.3):** demo 헤더 → demo 행만, mju 누수 0. **fail-closed:** 헤더 없음 → 0건.
- **컬럼최소화(AC §9.4):** 반환 = `id,title,body,created_at` (target_scope/target_value 부재).

### B. 프론트 회귀 — 로컬 서버 + 실제 mju Supabase (읽기전용)
마이그레이션 **미적용** 라이브에서:
- `public_notices` RPC → **404**(부재) → 프론트가 **직조회 폴백** → 공지 정상 렌더, **콘솔 에러 0**, `who="전체 공지"`.
- 폴백 직조회 200·2건. → **파일럿 회귀 0 확인**(sql 적용 전·후 모두 안전).
- 실측 노출: 현재 anon 이 `target_scope≠'all'` 공지 **1건 직접 열람 가능** → `sql/38` 적용 시 닫힘(rls-check 점검이 추적).

### 남은 라이브 작업(사용자, `docs/DEPLOY.md` 흐름)
`sql/37` 적용 → 프론트 배포 확인 → mju 회귀 0 재확인 → `sql/38` 적용 → `rls-check.html` "타게팅 노출 PASS" 확인.
이후 §7 2단계(surveys·polls) 동일 골격 복제.
