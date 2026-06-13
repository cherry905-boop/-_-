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
4. `rls-check.html` 실행 → `admin_users` 차단(PASS)·`centers` 공개·PII 전부 PASS 확인.
- → 통과 시 "관리자 갓모드 제거 + center_admin 격리" 검증 완료.
