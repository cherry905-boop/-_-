-- =====================================================================
-- 32_master_center_scope.sql  —  [리뷰 보강] companies/students 마스터 센터 스코프 RLS
-- 멱등. 적용 순서: 27(companies/students 에 center_id 추가) 이후. 라이브 적용 + rls-check 통과 확인.
--
-- 배경: companies/students 마스터는 sql/27 에서 center_id 를 받았지만, sql/21(센터 스코프 RLS)·
--   sql/25(center_id 주입 트리거) 의 테이블 배열에서 누락돼 '센터 스코프 정책이 없는' 상태였다.
--   → 두 번째 센터가 생기면 관리자가 타 센터의 회사·학생을 볼 수 있다(students 는 이름·전화=PII).
--
-- 이 파일이 하는 일(추가만):
--   · students : RLS 활성 + 센터 스코프 관리자 정책(super=전체 / center_admin=자기 센터). anon 차단 유지
--     (rls-check MUST_BE_BLOCKED). students 는 프론트가 직접 읽지 않으므로 anon 정책 불필요.
--   · companies: RLS 활성 + 센터 스코프 관리자 정책 + anon '활성 회사 읽기'(가입폼 드롭다운 보존).
--     companies 의 anon 읽기는 untrusted anon 특성상 센터로 못 좁힌다 → 회사'명'은 교차센터 노출(저민감).
--     화면 표시는 클라이언트가 center 로 필터(index.html/admin.html 드롭다운에 .eq('center_id') 추가).
--   · sql/21 과 동일한 갓모드 제거(qual='true' / 'auth.uid() IS NOT NULL') 도 두 테이블에 적용.
--
-- ⚠️⚠️ 남은 필수 작업(대시보드 전용 객체 — 레포 밖):
--   `admin_students()` 는 SECURITY DEFINER RPC(R15)라 RLS 를 '우회'한다(admin.html:1232 이 호출).
--   즉 이 파일의 students RLS 만으로는 그 RPC 경로가 안 좁혀진다. 대시보드에서 정의를 다음처럼 센터 스코프화할 것:
--     ... where is_super_admin() or center_id = current_admin_center()
--   (RPC 정의가 운영 대시보드에만 있어 레포에서 고칠 수 없음 — sql/22 의 dashboard-only 전례와 동일.)
-- =====================================================================

do $master$
declare
  t   text;
  pol record;
  tbls text[] := array['students', 'companies'];
begin
  foreach t in array tbls loop
    if to_regclass('public.' || t) is null then continue; end if;
    -- center_id 컬럼이 아직 없으면(=27 미적용) 스킵 = 회귀 0.
    if not exists (select 1 from information_schema.columns
                   where table_schema = 'public' and table_name = t and column_name = 'center_id') then
      continue;
    end if;

    execute format('alter table public.%I enable row level security', t);

    -- (a) 센터 무스코프 갓모드 정책 제거(sql/21 과 동일 기준). anon/공개읽기·본인행 정책은 qual 형태가 달라 보존.
    for pol in
      select policyname from pg_policies
      where schemaname = 'public' and tablename = t
        and (
              (cmd = 'ALL' and qual = 'true')
           or qual = '(auth.uid() IS NOT NULL)'
           or with_check = '(auth.uid() IS NOT NULL)'
        )
    loop
      execute format('drop policy if exists %I on public.%I', pol.policyname, t);
    end loop;

    -- (b) 센터 스코프 관리자 정책(멱등).
    execute format('drop policy if exists %I on public.%I', t || '_admin_center', t);
    execute format($f$
      create policy %I on public.%I
        for all to public
        using ( public.is_super_admin() or center_id = public.current_admin_center() )
        with check ( public.is_super_admin() or center_id = public.current_admin_center() )
    $f$, t || '_admin_center', t);
  end loop;

  -- (c) companies 만: anon '활성 회사 읽기'(가입폼 드롭다운 보존). 멱등.
  if to_regclass('public.companies') is not null then
    drop policy if exists "companies anon read active" on public.companies;
    create policy "companies anon read active" on public.companies
      for select to public using ( active );
  end if;

  -- (d) unverified_signups(가입도움 요청, center_id 보유): 레거시 무스코프 정책 제거.
  --   sql/25 가 센터 스코프 정책을 '추가'했지만, 기존 auth.uid()-only 관리자 정책(예: "admin manage help")이
  --   남아 permissive OR 로 센터 스코프를 무효화했다(교차센터 PII 노출). sql/21 배열 밖이라 누락됐던 것 보강.
  if to_regclass('public.unverified_signups') is not null then
    for pol in
      select policyname from pg_policies
      where schemaname='public' and tablename='unverified_signups'
        and (qual='(auth.uid() IS NOT NULL)' or with_check='(auth.uid() IS NOT NULL)')
    loop
      execute format('drop policy if exists %I on public.unverified_signups', pol.policyname);
    end loop;
  end if;
end
$master$;
