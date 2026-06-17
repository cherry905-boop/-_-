-- =====================================================================
-- 36_tighten_public_and_anon_policies.sql
-- [멀티테넌트 보안 보강] 공개읽기 센터 스코프 강제 + anon 직접 쓰기 폐쇄
--
-- ⚠️ 적용 순서:
--   1) sql/35 적용
--   2) 프론트가 새 RPC/requireCenterId 로 배포된 것 확인
--   3) 이 파일 적용
-- =====================================================================

begin;

-- ── A. 공개 콘텐츠 SELECT 정책을 x-ilhak-center 기반으로 교체 ────────
do $pub$
declare
  t text;
  pol record;
  q text;
  tbls text[] := array[
    'notices','library','calendar_events','job_postings','success_cases',
    'surveys','polls','jobs','companies','tasks'
  ];
begin
  foreach t in array tbls loop
    if to_regclass('public.' || t) is null then
      continue;
    end if;
    if not exists (
      select 1 from information_schema.columns
       where table_schema='public' and table_name=t and column_name='center_id'
    ) then
      raise exception '%.center_id missing', t;
    end if;

    execute format('alter table public.%I enable row level security', t);

    -- 기존 공개 SELECT 정책 제거.
    for pol in
      select policyname
        from pg_policies
       where schemaname = 'public'
         and tablename = t
         and cmd = 'SELECT'
         and roles && array['public','anon']::name[]
    loop
      execute format('drop policy if exists %I on public.%I', pol.policyname, t);
    end loop;

    -- 레거시 관리자 갓모드(auth.uid()-only/bare true)가 남아 있으면 permissive OR 로
    -- 센터 스코프를 무력화한다. 공개 콘텐츠 테이블은 여기서도 한 번 더 제거한다.
    for pol in
      select policyname
        from pg_policies
       where schemaname = 'public'
         and tablename = t
         and (
              (cmd = 'ALL' and qual = 'true')
           or (qual = 'true' and roles @> array['authenticated']::name[])
           or (with_check = 'true' and roles @> array['authenticated']::name[])
           or qual = '(auth.uid() IS NOT NULL)'
           or with_check = '(auth.uid() IS NOT NULL)'
         )
    loop
      execute format('drop policy if exists %I on public.%I', pol.policyname, t);
    end loop;

    execute format('drop policy if exists %I on public.%I', t || '_admin_center', t);
    execute format($f$
      create policy %I on public.%I
        for all to public
        using (public.is_super_admin() or center_id = public.current_admin_center())
        with check (public.is_super_admin() or center_id = public.current_admin_center())
    $f$, t || '_admin_center', t);

    q := 'center_id = public.request_center_id()';
    if exists (select 1 from information_schema.columns where table_schema='public' and table_name=t and column_name='published') then
      q := 'published = true and ' || q;
    elsif t = 'surveys' and exists (select 1 from information_schema.columns where table_schema='public' and table_name=t and column_name='open') then
      q := 'open = true and ' || q;
    elsif t = 'polls' and exists (select 1 from information_schema.columns where table_schema='public' and table_name=t and column_name='open') then
      q := 'open = true and ' || q;
    elsif exists (select 1 from information_schema.columns where table_schema='public' and table_name=t and column_name='active') then
      q := 'active = true and ' || q;
    end if;

    execute format('drop policy if exists %I on public.%I', t || '_public_center_read', t);
    execute format('create policy %I on public.%I for select to public using (%s)', t || '_public_center_read', t, q);
  end loop;
end
$pub$;

-- 센터 선택용 centers 는 active=true 공개 읽기 유지.
do $centers$
begin
  if to_regclass('public.centers') is not null then
    alter table public.centers enable row level security;
    drop policy if exists "centers public read" on public.centers;
    create policy "centers public read" on public.centers
      for select to public using (coalesce(active, true) = true);
  end if;
end
$centers$;

-- ── B. anon 직접 INSERT 폐쇄: 쓰기는 SECURITY DEFINER RPC 만 허용 ────
do $writes$
declare
  t text;
  pol record;
  tbls text[] := array[
    'registrations','push_tokens','poll_votes','survey_answers',
    'company_survey_responses','unverified_signups'
  ];
begin
  foreach t in array tbls loop
    if to_regclass('public.' || t) is null then
      continue;
    end if;
    for pol in
      select policyname
        from pg_policies
       where schemaname = 'public'
         and tablename = t
         and cmd = 'INSERT'
         and roles && array['public','anon']::name[]
    loop
      execute format('drop policy if exists %I on public.%I', pol.policyname, t);
    end loop;
  end loop;
end
$writes$;

commit;

-- 검증 예시:
-- 1) 아래 결과가 0건이어야 한다.
-- select tablename, policyname, cmd, roles, qual, with_check
--   from pg_policies
--  where schemaname='public'
--    and tablename in ('registrations','push_tokens','poll_votes','survey_answers','company_survey_responses','unverified_signups')
--    and cmd='INSERT'
--    and roles && array['public','anon']::name[];
--
-- 2) 공개 SELECT 정책은 모두 request_center_id() 를 포함해야 한다.
-- select tablename, policyname, qual
--   from pg_policies
--  where schemaname='public'
--    and tablename in ('notices','library','calendar_events','job_postings','success_cases','surveys','polls','jobs','companies','tasks')
--    and cmd='SELECT';
