# docs/VERIFICATION.md — 멀티테넌트 RLS 검증 결과

> 2026-06-14, **로컬 WASM Postgres(pglite, PostgreSQL 18.3)**에서 실제 마이그레이션을 적용·검증.
> 자격증명·운영 DB·시크릿 키 사용 0. Supabase 호환 스텁(auth 스키마·`auth.uid()`·anon/authenticated 역할·storage 스키마)을
> 만든 뒤 레포의 `sql/19·20·21`을 그대로 적용하고, 2개 센터·3명 관리자·데이터를 시드해 역할별 가시성을 측정.

## 적용 결과 (세 마이그레이션 모두 클린)
- `sql/19_multitenant_core.sql` ✅ — `centers`(mju 시드)·`admin_users`·헬퍼(`current_admin_center`/`is_super_admin`/`center_id_for_slug`) 생성, 기존 테이블에 `center_id` 추가·백필.
- `sql/21_rls_center_scope.sql` ✅ — 갓모드(`for all to authenticated using(true)`) **0개로 제거**, 센터 스코프 정책 생성(`is_super_admin() OR center_id = current_admin_center()`), 공개읽기(`published=true`) 보존.
- `sql/20_storage_isolation.sql` ✅ — `library` 버킷 `public=false`, 경로(`<slug>/...`) 스코프 storage 정책 생성.

## 교차센터 격리 — PII 테이블 `registrations` (RLS가 유일 게이트)
시드: center `mju`(reg 2건: mju-stu1·mju-stu2), `demo`(reg 1건: demo-stu1).

| 역할(JWT sub + SET ROLE) | 보이는 registrations | 판정 |
|---|---|---|
| adminA = mju center_admin | mju-stu1, mju-stu2 **만** | ✅ demo 0건 |
| adminB = demo center_admin | demo-stu1 **만** | ✅ mju 0건 |
| super_admin | 3건 전부 | ✅ |
| anon (미로그인) | **0건** | ✅ PII 차단 |

→ **`ALL_PASS: true`. "A센터 사용자가 B센터 데이터 0건" RLS 수준 증명.**
(notices 등 공개 콘텐츠는 `published=true` 정책으로 모든 역할에 보이는 게 정상 — 센터 스코프는 클라이언트 `getCenterId()` 필터가 담당, 9개 페이지 브라우저 검증 완료.)

## 교차센터 격리 — 스토리지 `library` 버킷
시드: `mju/lib/a.pdf`, `demo/lib/b.pdf` (버킷 비공개).

| 역할 | 보이는 객체 | 판정 |
|---|---|---|
| adminA (mju) | `mju/lib/a.pdf` **만** | ✅ demo 0건 |
| adminB (demo) | `demo/lib/b.pdf` **만** | ✅ mju 0건 |
| anon | **0건** | ✅ (학생 다운로드는 P7 서명기 경유) |

→ **`ALL_PASS: true`. P2 스토리지 교차센터 차단 RLS 수준 증명.**

## 교차센터 격리 — DELETE 경로 (sql/07 "admin delete" 갓모드 제거)
> 2026-06-15 추가. sql/07 의 레거시 `create policy "admin delete" ... for delete to authenticated using(true)`
> 가 sql/21·32 정리 루프(3조건)에서 빠져 있던 회귀를 pglite(PG18.3)로 재현·수정 검증.

배경(Postgres RLS 의미론, 실측): 컬럼 참조 WHERE(`where center_id=…`) DELETE 는 행을 '읽어야' 해 SELECT 정책
가시성이 필요 → 센터 정책이 타 센터 행을 숨겨 '필터 삭제'는 막힌다. 그러나 **무필터 `DELETE FROM notices` 는
컬럼을 안 읽어 SELECT 가시성이 불필요** → 갓모드 `using(true)` 만 있으면 아무 로그인 계정이나(심지어 admin_users
매핑이 없는 계정도) 전 센터 공지를 통째로 지운다. ('A센터 사용자가 B센터 데이터 0건' 위반.)

시드: mju 공지 2건 / demo 공지 2건. 무필터 `DELETE FROM notices` 를 역할별로 실행해 센터별 파괴 건수 측정(후 ROLLBACK).

| 시나리오(무필터 DELETE) | 수정 전(3조건) | 수정 후(5조건·role 가드) |
|---|---|---|
| adminB(demo) → mju 공지 파괴 | **2건(교차센터 전멸)** | **0건** ✅ |
| adminB(demo) → demo 공지(자기센터) | 2건 | 2건(정상 삭제 유지·회귀 0) ✅ |
| admin_users 매핑 없는 로그인계정 → mju | **2건** | **0건** ✅ |
| anon → mju | 0건 | 0건 |
| 갓모드 "admin delete" 잔존 | 있음 | **제거됨** ✅ |
| 공개읽기 "anyone read polls"(to public using(true)) | 보존 | **보존**(role 가드로 오삭제 방지) ✅ |

→ **`ALL_PASS: true`.** sql/21·32 정리 조건에 `(qual='true' or with_check='true') and roles @> array['authenticated']`
를 추가해 cmd 무관 bare-true 관리자 갓모드를 제거하고, 공개읽기({anon}/{public}) bare-true 정책은 authenticated
가드로 보존했다. 더불어 6개 대상 테이블(notices·library·calendar_events·consultations·consultation_messages·
notice_recipients)에 sql/21 루프가 `enable row level security` 를 멱등 박제한다(RLS 가 꺼져 있으면 정책 무력화).

## 한계(이 검증이 보장하지 않는 것)
- pglite는 Supabase 호환 **스텁** 위에서 돈다(실제 `auth.users`·storage 서비스·PostgREST 아님). RLS 정책 **로직**과 마이그레이션 **유효성**을 증명하지만, 라이브 Supabase의 PostgREST 키 동작(예: publishable 키 `to authenticated` 전례)·서울 리전·Edge Function 서명기 배포는 별도.
- 따라서 **운영 반영 시** 스테이징에 동일 적용 후 `rls-check.html` + 본 검증을 재확인 권장(`docs/DEPLOY.md`).

## 함께 검증된 것(브라우저, 실제 mju Supabase, 읽기전용)
- 운영 PII 14개 테이블 anon 차단 PASS, 공개 콘텐츠 정상, 마이그레이션 미적용 상태에서 `getCenterId()=null`(폴백)로 파일럿 무회귀 — `docs/CURRENT_STATE.md` §8b.
