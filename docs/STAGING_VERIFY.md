# docs/STAGING_VERIFY.md — 멀티테넌트 교차센터 격리 검증(스테이징)

> 목적: **운영 DB(실 PII) 말고 일회용 스테이징 프로젝트**에서 `sql/19~21`을 적용하고
> "A센터↔B센터 0건"을 검증한다. 검증이 끝나면 스테이징은 삭제해도 된다.
>
> 역할 분담(중요):
> - **anon(공개) 키로 내가 검증 가능:** 공개읽기 센터 스코프(센터별 공지/자료만 보임) + PII anon 차단.
> - **관리자(authenticated) RLS 격리는 본인이 검증:** center_admin 로그인은 비밀번호 인증이라 내가 못 함(안전규칙). 아래 8번 절차를 본인이 실행.

## 1. 스테이징 Supabase 프로젝트 생성
- 새 프로젝트(서울 리전 권장). **운영 프로젝트가 아님.**

## 2. 기존 스키마 적용
- SQL 에디터에서 `sql/ALL_IN_ONE.sql` 실행(기존 테이블·RPC·정책 일괄). 오류 없으면 다음.

## 3. 멀티테넌트 마이그레이션 적용 (순서대로)
1. `sql/19_multitenant_core.sql`
2. `sql/21_rls_center_scope.sql`
3. (선택, 스토리지 검증 시) `sql/20_storage_isolation.sql`

## 4. 검증용 2센터 + 샘플 데이터 시드 (아래 그대로 실행)
```sql
-- 두 번째 센터(demo) 추가 (mju 는 sql/19 가 이미 시드)
insert into public.centers (slug, name, region, app_title)
values ('demo', '데모 공동훈련센터', '데모대', '데모 일학습앱')
on conflict (slug) do nothing;

-- 센터별 공개 공지 2건씩 (공개읽기 센터 스코프 검증용)
insert into public.notices (title, body, target_scope, target_value, published, center_id)
select * from (values
  ('[MJU] 명지 공지 A', '명지대 전용', 'all', null, true, (select id from public.centers where slug='mju')),
  ('[MJU] 명지 공지 B', '명지대 전용', 'all', null, true, (select id from public.centers where slug='mju')),
  ('[DEMO] 데모 공지 A', '데모 전용', 'all', null, true, (select id from public.centers where slug='demo')),
  ('[DEMO] 데모 공지 B', '데모 전용', 'all', null, true, (select id from public.centers where slug='demo'))
) v(title, body, target_scope, target_value, published, center_id);

-- 센터별 공개 자료 1건씩 (외부 링크형 — 스토리지 없이 검증)
insert into public.library (title, kind, url, job_key, published, center_id)
select * from (values
  ('[MJU] 명지 자료', '기타', 'https://example.com/mju', null, true, (select id from public.centers where slug='mju')),
  ('[DEMO] 데모 자료', '기타', 'https://example.com/demo', null, true, (select id from public.centers where slug='demo'))
) v(title, kind, url, job_key, published, center_id);
```
> ※ 위 컬럼명이 본인 스키마와 다르면(예: notices 에 body 대신 content) 그 부분만 맞춰주세요.

## 5. 나에게 줄 것
- 스테이징 프로젝트의 **공개 anon 키 + URL** (시크릿/service_role 아님).

## 6. 내가 검증할 것 (anon, 읽기 전용)
- `?center=mju` 진입 → 공지/자료에 **[MJU]만** 보이고 **[DEMO]는 0건** (그 반대도).
- PII 테이블(registrations·push_tokens 등) anon **여전히 차단**.
- → 통과 시 "공개읽기 센터 스코프 격리 = A↔B 0건" 라이브 증명.

## 7. (선택) 스토리지 격리
- `sql/20` 적용 + Edge Function `sign-library` 배포 후 별도 검증.

## 8. 본인이 직접 검증할 것 — 관리자 RLS 격리 (sql/21)
center_admin 로그인은 비밀번호 인증이라 내가 못 하니, 본인이:
1. 스테이징에 Auth 사용자 2명 생성(대시보드 → Authentication → Add user): adminA, adminB.
2. `admin_users` 매핑:
   ```sql
   insert into public.admin_users (user_id, center_id, role) values
     ('<adminA uid>', (select id from public.centers where slug='mju'),  'center_admin'),
     ('<adminB uid>', (select id from public.centers where slug='demo'), 'center_admin');
   ```
3. 앱(또는 admin.html)에서 **adminA 로 로그인** → `registrations`/`notices` 등 조회 → **mju 행만** 보이고 demo 0건인지 확인. adminB 는 그 반대.
4. `rls-check.html` 실행 → `admin_users` 차단(PASS)·`centers` 공개·PII 전부 PASS·하단 **삭제 경로** 전부 PASS 확인.
5. **삭제 격리(sql/07 갓모드 제거 보강):** adminB(demo)로 로그인한 채로 공지/자료를 삭제 시도 → **mju 행은 0건 영향**(자기 센터 demo 만 삭제). admin.html 삭제 버튼은 보통 id 필터라 SELECT 가시성으로도 막히지만, **무필터 삭제 경로**까지 닫혔는지는 `docs/VERIFICATION.md` 의 DELETE 경로 표(pglite)가 증명 — sql/07 "admin delete"(for delete to authenticated using(true)) 갓모드가 sql/21·32 정리 루프에서 제거됐는지 함께 확인.
- → 통과 시 "관리자 갓모드 제거(ALL·SELECT·DELETE 무스코프 + bare-true) + center_admin 격리" 검증 완료.

---

## 9. 0~5단계(sql/22~27) 신규 적용·검증 — center_id 서버 도출 백본
> §3(19·21) 이후에 **순서대로** 적용. 전부 멱등. 0~2·4 프론트(index.html·admin.html)도 함께 배포.

### 9-A. 적용 순서
`sql/22` → `sql/23` → `sql/24` → `sql/25` → `sql/26` → `sql/27`
- 22=토대 하드닝(registrations anon insert 박제) / 23=코드 센터스코프 / 24=가입·발급 RPC / 25=관리자쓰기 트리거 / 26=센터개설 RPC / 27=명단 스키마(biz_no).
- ⚠️ `sql/20`(스토리지)·NOT NULL(미작성)은 **여기 포함 안 함** — 별도(§7, 추후).

### 9-B. rls-check.html (갱신됨)
- MUST_BE_BLOCKED 에 **student_codes·company_codes·unverified_signups** 추가됨 → anon 전부 **차단 PASS** 확인.

### 9-C. 가입 = center_id 서버 도출 (핵심)
1. adminA(mju)로 admin.html → 가입자 탭에서 학생 코드 발급(issue_student_code RPC) → 코드 복사.
2. `?center=mju` 로 index.html → 그 코드로 학생 가입.
3. 스테이징 SQL 에디터:
   ```sql
   select center_id, name, target_type from public.registrations order by created_at desc limit 3;
   ```
   → 방금 가입행 **center_id = mju(≠null)** 면 PASS. (demo 코드로 가입하면 center_id=demo 여야 함.)
4. **폴백 테스트:** `sql/24` 미적용 상태에서 가입 → 기존처럼 그냥 insert 되는지(회귀 0). (RPC 없으면 프론트가 직접 insert 폴백.)

### 9-D. 관리자 쓰기 트리거(25)
- adminA(mju)로 공지 1건 발행 → `select center_id from notices order by created_at desc limit 1;` → **center_id=mju 자동** 이면 PASS.
- adminA 가 클라에서 임의 center_id 를 넣어도 **무시되고 mju 강제**(트리거)인지 확인.

### 9-E. 센터 개설·역할(26 + admin 프론트)
- super_admin(본인)로 admin.html → **'센터' 탭** 노출 확인(center_admin 으로 로그인하면 미노출).
- '센터 개설'(create_center) → centers 행 생성 / '관리자 발급'(grant_admin, 대상 Auth 계정 선존재 필요) → admin_users 매핑.
- **배포 갭 확인:** admin_users 매핑이 없는 새 Auth 계정으로 로그인 → '권한 없음'(#noperm) 뜨는지. (단, 미적용 DB면 기존 전체 콘솔 폴백.)

### 9-F. 통과 기준
- rls-check 전 PASS / 가입행 center_id 채워짐 / 트리거 자동주입 / super만 센터탭 / 교차센터(adminA=mju만·adminB=demo만) 0건.
- → 통과하면 5RPC(마스터 스키마)·6스토리지·7 NOT NULL 진행해도 안전한 토대 확보.
