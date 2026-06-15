-- =====================================================================
-- 33_member_lifecycle.sql  —  [정합성] 가입자 생애주기: status 컬럼 + 편집·졸업 RPC
-- 멱등. 적용 순서: 19(center_id)·21(RLS)·27(students master)·31(cohort) 이후.
--
-- 배경(정합성 갭): 'status'(진행중/휴학/중도탈락/수료)는 config.js STATUSES 에만 있고 컬럼이 없었다.
--   cohort(기수)·status·manager·type1 은 표시·필터는 되는데 '생성 후 편집/전환' 경로가 없었다
--   (졸업=기수 이동도 마찬가지). 이 파일이 컬럼 + 서버 RPC(센터 스코프)를 추가한다.
--
-- 설계: 가입자 화면은 데이터 소스가 둘(students 마스터 = admin_students RPC, 또는 registrations 폴백)이라,
--   편집은 (center, 이름, 전화)로 두 테이블을 함께 갱신하는 SECURITY DEFINER RPC 로 통일한다.
--   · 스키마 안전: 패치 키 중 '실제 존재하는 컬럼'만 동적 set(마스터 스키마가 대시보드 관리라 가변).
--   · 화이트리스트: cohort/status/manager/type1 만 허용(center_id·role 등 변조 차단).
--   · 센터 스코프: current_admin_center() 로 한정(super_admin 도 자기 홈센터). 교차센터 편집 불가.
--
-- ⚠️ 후속(대시보드 전용): admin_students() RPC 가 cohort/status 를 '반환'하지 않아, 마스터 경로 행은
--    가입자 표에서 기수/상태가 '-' 로 보인다(편집은 RPC 로 정상 적용·저장됨). 편집기는 '바뀐 필드만'
--    전송(더티 트래킹)하므로 기존값을 덮어쓰진 않지만, 마스터 경로에서 현재값을 화면에 보이려면
--    admin_students() 가 cohort·status(가능하면 center_id)도 반환하도록 대시보드에서 보강할 것.
-- =====================================================================

-- ── A. status 컬럼 + (center_id, status) 인덱스 (registrations·students) ──
do $st$
declare t text; tbls text[] := array['registrations', 'students'];
begin
  foreach t in array tbls loop
    if to_regclass('public.' || t) is not null then
      execute format('alter table public.%I add column if not exists status text', t);
      -- center_id 컬럼이 있을 때만 복합 인덱스(없으면 status 단독)
      if exists (select 1 from information_schema.columns
                 where table_schema='public' and table_name=t and column_name='center_id') then
        execute format('create index if not exists %I on public.%I (center_id, status)', t || '_status_idx', t);
      else
        execute format('create index if not exists %I on public.%I (status)', t || '_status_idx', t);
      end if;
    end if;
  end loop;
end $st$;

-- ── B. update_student_lifecycle — 한 가입자의 cohort/status/manager/type1 편집(센터 스코프, 스키마 안전) ──
create or replace function public.update_student_lifecycle(p_name text, p_phone text, p_patch jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_center uuid; v_phone text; t text; setlist text; n int := 0; tot int := 0;
  tbls text[] := array['students', 'registrations'];
begin
  if not (is_super_admin() or current_admin_center() is not null) then raise exception 'not_admin'; end if;
  v_center := current_admin_center();                  -- 편집은 항상 자기 센터(super 도 홈센터)로 한정
  if v_center is null then raise exception 'no_center'; end if;
  v_phone := nullif(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), '');

  foreach t in array tbls loop
    if to_regclass('public.' || t) is null then continue; end if;
    -- 패치 키 ∩ 화이트리스트 ∩ 실제 컬럼만 동적 set. 값은 %L 로 안전 인용.
    select string_agg(format('%I = %L', k, p_patch->>k), ', ')
      into setlist
      from jsonb_object_keys(p_patch) k
      where k in ('cohort', 'status', 'manager', 'type1')
        and exists (select 1 from information_schema.columns c
                    where c.table_schema='public' and c.table_name=t and c.column_name=k);
    if setlist is null then continue; end if;
    -- 이름 일치 + (전화 미지정이면 통과, 지정이면 숫자정규화 후 일치) + 센터 스코프.
    execute format(
      'update public.%I set %s
         where center_id = $1 and name = $2
           and ($3 is null or regexp_replace(coalesce(phone, ''''), ''[^0-9]'', '''', ''g'') = $3)',
      t, setlist) using v_center, p_name, v_phone;
    get diagnostics n = row_count; tot := tot + n;
  end loop;
  return jsonb_build_object('ok', true, 'rows', tot);
end $$;
grant execute on function public.update_student_lifecycle(text, text, jsonb) to authenticated;

-- ── C. graduate_cohort — 기수 일괄 이동(졸업). p_set_completed=true 면 status='수료'도 표시 ──
create or replace function public.graduate_cohort(p_from text, p_to text, p_set_completed boolean default false)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_center uuid; t text; setexpr text; n int := 0; tot int := 0;
  tbls text[] := array['students', 'registrations'];
begin
  if not (is_super_admin() or current_admin_center() is not null) then raise exception 'not_admin'; end if;
  v_center := current_admin_center();
  if v_center is null then raise exception 'no_center'; end if;
  if nullif(btrim(coalesce(p_from, '')), '') is null or nullif(btrim(coalesce(p_to, '')), '') is null then
    raise exception 'from_to_required';
  end if;

  foreach t in array tbls loop
    if to_regclass('public.' || t) is null then continue; end if;
    -- cohort 컬럼이 있는 테이블만. status 는 컬럼이 있고 p_set_completed 일 때만 추가 set.
    if not exists (select 1 from information_schema.columns
                   where table_schema='public' and table_name=t and column_name='cohort') then continue; end if;
    setexpr := format('cohort = %L', p_to);
    if p_set_completed and exists (select 1 from information_schema.columns
                                   where table_schema='public' and table_name=t and column_name='status') then
      setexpr := setexpr || ', status = ' || quote_literal('수료');
    end if;
    execute format('update public.%I set %s where center_id = $1 and cohort = $2', t, setexpr)
      using v_center, p_from;
    get diagnostics n = row_count; tot := tot + n;
  end loop;
  return jsonb_build_object('ok', true, 'rows', tot);
end $$;
grant execute on function public.graduate_cohort(text, text, boolean) to authenticated;
