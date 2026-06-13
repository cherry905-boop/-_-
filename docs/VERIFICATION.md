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

## 한계(이 검증이 보장하지 않는 것)
- pglite는 Supabase 호환 **스텁** 위에서 돈다(실제 `auth.users`·storage 서비스·PostgREST 아님). RLS 정책 **로직**과 마이그레이션 **유효성**을 증명하지만, 라이브 Supabase의 PostgREST 키 동작(예: publishable 키 `to authenticated` 전례)·서울 리전·Edge Function 서명기 배포는 별도.
- 따라서 **운영 반영 시** 스테이징에 동일 적용 후 `rls-check.html` + 본 검증을 재확인 권장(`docs/DEPLOY.md`).

## 함께 검증된 것(브라우저, 실제 mju Supabase, 읽기전용)
- 운영 PII 14개 테이블 anon 차단 PASS, 공개 콘텐츠 정상, 마이그레이션 미적용 상태에서 `getCenterId()=null`(폴백)로 파일럿 무회귀 — `docs/CURRENT_STATE.md` §8b.
