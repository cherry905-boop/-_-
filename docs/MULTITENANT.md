# docs/MULTITENANT.md — 멀티테넌트 전환 실행 로드맵 (sql/22~)

> 출처: 2026-06-14 구조분석(다중에이전트) + 결정. 절대규칙은 `CLAUDE.md`, 배경 스펙은 `docs/PLAN.md` §1~§7.
> 핵심 진단: 토대(`sql/19`·`21`)는 운영 적용됨. **비어있는 핵심 = 'center_id 서버 도출 경로'가 통째로 없음** —
> 가입·관리자 쓰기·코드발급이 center_id 를 안 채워 신규행이 전부 center_id=NULL(고아)로 들어간다. 이걸 채운다.

## 운영 모델 (확정)
- **(A) 센터 생성·관리자 발급** = super_admin 이 슈퍼관리자 화면에서 수동(~10개). 셀프 공개가입 없음.
- **(B) 명단·콘텐츠** = center_admin 이 자기 대시보드에서 엑셀/CSV 업로드 + 초대코드 발급으로 셀프.
- **(C) center_id 는 항상 서버가 도출** — 관리자=`admin_users` 매핑, 학생/기업=초대코드. 클라가 보낸 center_id 미신뢰.
- **companies = 센터별 스코프 + 사업자번호 자연키.** 같은 법인이 여러 센터면 각 센터에 별도 행, `(center_id, 사업자번호)` 로 묶음.
  공유 회사 레지스트리는 만들지 않는다(크로스테넌트 표면·프라이버시). 교차집계는 super_admin 이 사업자번호 GROUP BY.

## 철칙
**center_id NOT NULL 승격은 맨 마지막.** 모든 쓰기가 center_id 를 채우기 전에 NOT NULL 을 걸면 anon 가입이 전면 마비된다.

## 단계 (한 번에 한 단계: 계획→구현→검증→사용자 확인)

| 단계 | 파일 | 내용 | 상태 |
|---|---|---|---|
| **0. 토대 하드닝** | `sql/22` + `sql/08`·`sql/09`·`rls-check.html` 편집 | registrations anon insert 박제 / 08 전체삭제 다센터 가드 / 09 공개버킷 무력화 / rls-check 코드테이블 추가 | 🟢 코드 완료, **라이브 적용·검증 대기** |
| 1. 코드 센터 스코프 | `sql/23` | **student_codes** person-uniq → `(center_id, name, phone) where active` (code 는 전역 unique 유지 = 센터 도출 근거). company 키+사업자번호는 5단계로 통합(★) | 🟢 코드 완료, 라이브·검증 대기 |
| 2. 가입·발급 RPC | `sql/24` + 프론트 | verify_*(02/09/13) center_id/center_slug 반환(HRD 자동채움·verify_student 보존) + register_with_code/register_applicant/issue_student_code/issue_company_code 신설(SECURITY DEFINER, center 서버 도출, registrations **동적 insert**=스키마 변동·기본값 보존). 프론트 전환 완료: index.html 가입(doRegister·지원자) → register_with_code/register_applicant, admin.html issueCode/issueCoCode → issue_* (모두 RPC 우선 + 함수없음/오류 시 기존 insert·발급 폴백, center_slug 로 localStorage 센터 바인딩). | 🟢 코드 완료 / 라이브·검증 대기 |
| 3. 관리자 쓰기 자동주입 | `sql/25` | `_set_center_id_on_write` 트리거(super=명시값 honor, center_admin=클라값 무시·강제) → **관리자-쓰기 13개 테이블** BEFORE INSERT. sql/14 전센터 OR 구멍 센터스코프 교체 + unverified_signups anon insert 박제·센터 정책. (학생/anon 쓰기 테이블 제외=부모/RPC 도출 별도 보강) | 🟢 코드 완료(SQL) / 라이브·검증 대기 |
| 4. 센터개설·역할게이팅 | `sql/26` + admin.html | create_center/seed_center(빈센터 no-op)/grant_admin(is_super 가드) + admin_users super 쓰기 정책. admin.html refresh role-aware(⚠️ **admin_users 조회 실패=기존 콘솔 폴백**으로 배포갭 차단, 미매핑만 '권한없음'; 데이터경계는 RLS가 강제), super 전용 sec-centers 탭(create_center/grant_admin RPC만). | 🟢 코드 완료 / 라이브·검증 대기 |
| 5. 명단 일괄등록 + 회사 사업자번호 키 | `sql/27` + admin.html | **스키마 추가분✅:** companies/students 에 center_id(+mju 백필), companies·company_codes·stages·info 에 biz_no + `unique(center_id,biz_no) where biz_no not null`(추가만=PK 무손상). **대기(마스터 스키마 필요):** bulk_upsert_student_roster/companies RPC + admin.html CSV UI. **별도 micro:** company PK→biz_no 전환(biz_no 적재·프론트 onConflict 후). | 🟡 스키마 완료 / RPC·UI 대기 |
| 6. 스토리지 격리 | `sql/20` (기존) | 버킷 private, admin.html getPublicUrl 제거, sign-library 서명기, 경로 `<slug>/` | ⬜ (코드 존재, 라이브 적용 대기) |
| 7. center_id NOT NULL 승격 | `sql/28` | NULL행 mju 백필 후 핵심 테이블 NOT NULL. push_tokens 등 비관리자/시스템 쓰기 경로의 center_id 주입 책임자 테이블별 확인 | ⬜ |
| (8. config DB화, 선택) | `sql/29` | MANAGERS/단계/어휘를 centers jsonb 또는 center_settings 로, loadCenterConfig 확장 | ⬜ |

## 검증 (단계마다)
- `rls-check.html` 전 항목 PASS(MUST_BE_BLOCKED 차단 유지).
- 교차센터 격리: pglite 스텁 위에 해당 sql 적용 → adminA=자기센터만 / adminB=자기센터만 / super=전체 / anon=PII 0건 (`docs/VERIFICATION.md` 패턴). 라이브 접근 불가 → pglite/스테이징.
- 폴백 우선: RPC/마이그레이션 미적용 구간엔 기존 파일럿(mju) 동작 그대로(회귀 0).

## 0단계에서 코드 읽고 정교화한 점 (계획 대비 보정)
- **시드 파일(06/08/11)은 `sql/19`(centers 생성)보다 먼저 실행** → 그 안에서 center_id 를 참조할 수 없다. 따라서 시드의
  센터 스코프화는 06/08/11 in-place 가 아니라 **4단계의 `seed_center(p_center_id)` 함수**(centers·center_id 존재 후)로 간다.
- **`sql/08` 은 `delete from success_cases` 전체삭제** → 멀티테넌트에서 다른 센터 사례까지 지운다. 0단계에서 다센터 가드만 선제.
- 06/11 은 additive(where not exists)·mju 전용·pre-19 이라 그대로 두되, 4단계 seed_center 가 멀티테넌트 시딩의 단일 경로가 된다.
- **★ 1단계(코드 센터키)에서 회사 키를 뺐다:** 목표는 "(center_id, 사업자번호/code)"였으나 ① 사업자번호 컬럼이 스키마에 없음(grep 0건, 5단계 도입), ② admin.html 의 company_codes/stages/info upsert(1932/1966/2005)가 onConflict 미지정=기본 PK(`company`) 충돌에 의존 → company PK 를 떼면 그 upsert 가 깨진다. 그래서 회사 키 전환을 사업자번호 도입·admin.html upsert 변경과 함께 **5단계로 통합**. 1단계는 student_codes 만(update/insert 라 결합 없음).
