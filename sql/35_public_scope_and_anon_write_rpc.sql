-- =====================================================================
-- 35_public_scope_and_anon_write_rpc.sql
-- [멀티테넌트 보안 보강] 공개읽기 센터 헤더 헬퍼 + anon 쓰기 RPC + tasks 센터화
--
-- 적용 순서:
--   1) sql/19~34 적용 후 이 파일을 먼저 적용한다(추가형).
--   2) 프론트 배포가 새 RPC를 쓰는지 확인한다.
--   3) sql/36_tighten_public_and_anon_policies.sql 로 직접 anon 쓰기/무스코프 공개읽기를 조인다.
-- =====================================================================

-- ── A. 요청 헤더(x-ilhak-center) → center_id 해석 ───────────────────────
create or replace function public.request_center_id()
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  hdr jsonb := '{}'::jsonb;
  slug text;
begin
  begin
    hdr := coalesce(nullif(current_setting('request.headers', true), ''), '{}')::jsonb;
  exception when others then
    hdr := '{}'::jsonb;
  end;

  slug := coalesce(
    nullif(hdr ->> 'x-ilhak-center', ''),
    nullif(hdr ->> 'X-Ilhak-Center', ''),
    nullif(hdr ->> 'center', '')
  );
  if slug is null then
    return null;
  end if;
  return public.center_id_for_slug(slug);
end $$;
grant execute on function public.request_center_id() to anon, authenticated;

create or replace function public._center_from_slug_or_code(p_slug text, p_code text)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_code text;
  v_center uuid;
begin
  v_code := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  if v_code <> '' then
    select center_id into v_center from public.student_codes where code = v_code and active limit 1;
    if v_center is null then
      select center_id into v_center from public.company_codes where code = v_code and active limit 1;
    end if;
  end if;
  if v_center is null then
    v_center := public.center_id_for_slug(coalesce(nullif(p_slug, ''), nullif(current_setting('app.default_center', true), ''), 'mju'));
  end if;
  return v_center;
end $$;
revoke all on function public._center_from_slug_or_code(text, text) from public, anon, authenticated;

-- ── B. 공개/참조 테이블 center_id 보강 + 기존 row mju 백필 ─────────────
do $cid$
declare
  mju uuid;
  t text;
  tbls text[] := array[
    'notices','library','calendar_events','job_postings','success_cases',
    'surveys','polls','jobs','companies','tasks'
  ];
begin
  select id into mju from public.centers where slug = 'mju';
  if mju is null then
    raise exception 'mju center not found';
  end if;

  foreach t in array tbls loop
    if to_regclass('public.' || t) is null then
      continue;
    end if;
    if not exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = t and column_name = 'center_id'
    ) then
      execute format('alter table public.%I add column center_id uuid references public.centers(id)', t);
    end if;
    execute format('update public.%I set center_id = $1 where center_id is null', t) using mju;
    execute format('create index if not exists %I on public.%I (center_id)', t || '_center_idx', t);
  end loop;
end
$cid$;

-- 기존 자료실 public URL 저장값을 버킷 object path 로 정규화한다.
do $lib$
begin
  if to_regclass('public.library') is not null then
    update public.library
       set url = regexp_replace(url, '^https?://[^/]+/storage/v1/object/(?:public|sign)/library/', '')
     where url ~ '^https?://[^/]+/storage/v1/object/(public|sign)/library/';
  end if;
end
$lib$;

-- ── C. JSON row 동적 insert/update 헬퍼(실제 존재 컬럼만 반영) ──────────
create or replace function public._jsonb_insert_public(p_table text, p_row jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  cols text;
begin
  if p_table !~ '^[a-z_][a-z0-9_]*$' then
    raise exception 'bad_table';
  end if;

  select string_agg(quote_ident(k), ',') into cols
    from jsonb_object_keys(coalesce(p_row, '{}'::jsonb)) k
   where exists (
     select 1 from information_schema.columns c
      where c.table_schema = 'public' and c.table_name = p_table and c.column_name = k
   );
  if cols is null then
    raise exception 'no_columns';
  end if;

  execute format(
    'insert into public.%I (%s) select %s from jsonb_populate_record(null::public.%I, $1)',
    p_table, cols, cols, p_table
  ) using p_row;
end $$;
revoke all on function public._jsonb_insert_public(text, jsonb) from public, anon, authenticated;

create or replace function public._jsonb_update_by_text_public(
  p_table text,
  p_row jsonb,
  p_key_col text,
  p_key_val text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  setexpr text;
  n int;
begin
  if p_table !~ '^[a-z_][a-z0-9_]*$' or p_key_col !~ '^[a-z_][a-z0-9_]*$' then
    raise exception 'bad_identifier';
  end if;

  select string_agg(format('%1$I = r.%1$I', k), ',') into setexpr
    from jsonb_object_keys(coalesce(p_row, '{}'::jsonb)) k
   where k <> p_key_col
     and exists (
       select 1 from information_schema.columns c
        where c.table_schema = 'public' and c.table_name = p_table and c.column_name = k
     );
  if setexpr is null then
    return false;
  end if;

  execute format(
    'update public.%I as t set %s
       from (select * from jsonb_populate_record(null::public.%I, $1)) as r
      where t.%I = $2',
    p_table, setexpr, p_table, p_key_col
  ) using p_row, p_key_val;
  get diagnostics n = row_count;
  return n > 0;
end $$;
revoke all on function public._jsonb_update_by_text_public(text, jsonb, text, text) from public, anon, authenticated;

create or replace function public._jsonb_pick_keys(p_row jsonb, p_keys text[])
returns jsonb
language sql
stable
as $$
  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb)
    from jsonb_each(coalesce(p_row, '{}'::jsonb))
   where key = any(p_keys)
$$;
revoke all on function public._jsonb_pick_keys(jsonb, text[]) from public, anon, authenticated;

do $revoke_old_helpers$
begin
  if to_regprocedure('public._insert_registration(jsonb)') is not null then
    execute 'revoke all on function public._insert_registration(jsonb) from public, anon, authenticated';
  end if;
end
$revoke_old_helpers$;

-- ── D. 가입/도움요청/푸시/응답 RPC ─────────────────────────────────────

-- 학생/기업 가입: 초대코드에서 center_id/대상/권위값을 도출하고 허용 필드만 등록한다.
create or replace function public.register_with_code(p_code text, p_row jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
  v_center uuid;
  v_name text;
  v_phone text;
  v_company text;
  v_target text;
  v_row jsonb;
  ip text;
begin
  begin
    ip := coalesce(current_setting('request.headers', true)::jsonb ->> 'x-forwarded-for', 'unknown');
  exception when others then
    ip := 'unknown';
  end;
  perform check_verify_rate('reg:' || ip);

  v_code := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));

  select center_id, name, phone into v_center, v_name, v_phone
    from public.student_codes
   where code = v_code and active
   limit 1;
  if v_center is not null then
    v_target := 'student';
  else
    select center_id, company into v_center, v_company
      from public.company_codes
     where code = v_code and active
     limit 1;
    if v_center is not null then
      v_target := 'company';
    end if;
  end if;

  if v_center is null then
    return jsonb_build_object('ok', false, 'reason', 'code');
  end if;

  v_row := public._jsonb_pick_keys(coalesce(p_row, '{}'::jsonb), array[
      'name','phone','job_key','company','type1','manager','src',
      'consent_collect','consent_transfer','consent_at','user_agent'
    ])
    || jsonb_build_object('center_id', v_center, 'target_type', v_target);

  if v_target = 'student' then
    v_row := v_row || jsonb_build_object('name', v_name, 'phone', v_phone);
  elsif v_target = 'company' then
    v_row := v_row || jsonb_build_object('company', v_company);
  end if;

  perform public._insert_registration(v_row);
  return jsonb_build_object('ok', true, 'center_id', v_center,
                            'center_slug', (select slug from public.centers where id = v_center));
exception when unique_violation then
  return jsonb_build_object('ok', true, 'duplicate', true, 'center_id', v_center,
                            'center_slug', (select slug from public.centers where id = v_center));
end $$;
grant execute on function public.register_with_code(text, jsonb) to anon, authenticated;

-- 지원자 가입: 센터 해석 실패 시 center_id NULL 행을 만들지 않는다.
create or replace function public.register_applicant(p_slug text, p_row jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_center uuid;
  v_row jsonb;
  ip text;
begin
  begin
    ip := coalesce(current_setting('request.headers', true)::jsonb ->> 'x-forwarded-for', 'unknown');
  exception when others then
    ip := 'unknown';
  end;
  perform check_verify_rate('regapp:' || ip);

  v_center := public.center_id_for_slug(coalesce(nullif(p_slug, ''), 'mju'));
  if v_center is null then
    return jsonb_build_object('ok', false, 'reason', 'center');
  end if;

  v_row := public._jsonb_pick_keys(coalesce(p_row, '{}'::jsonb), array[
      'name','phone','job_key','company','type1','manager','interest_jobs','dept','src',
      'consent_collect','consent_transfer','consent_at','user_agent'
    ])
    || jsonb_build_object('target_type', 'applicant', 'center_id', v_center);
  perform public._insert_registration(v_row);
  return jsonb_build_object('ok', true, 'center_id', v_center,
                            'center_slug', (select slug from public.centers where id = v_center));
exception when unique_violation then
  return jsonb_build_object('ok', true, 'duplicate', true, 'center_id', v_center,
                            'center_slug', (select slug from public.centers where id = v_center));
end $$;
grant execute on function public.register_applicant(text, jsonb) to anon, authenticated;

create or replace function public.create_unverified_signup(p_slug text, p_row jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_center uuid;
  v_row jsonb;
begin
  v_center := public.center_id_for_slug(coalesce(nullif(p_slug, ''), 'mju'));
  if v_center is null then
    return jsonb_build_object('ok', false, 'reason', 'center');
  end if;
  v_row := public._jsonb_pick_keys(coalesce(p_row, '{}'::jsonb), array[
      'name','phone','target_type','reason'
    ])
    || jsonb_build_object('center_id', v_center);
  perform public._jsonb_insert_public('unverified_signups', v_row);
  return jsonb_build_object('ok', true, 'center_id', v_center);
end $$;
grant execute on function public.create_unverified_signup(text, jsonb) to anon, authenticated;

create or replace function public.register_push_token(p_slug text, p_code text, p_row jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_center uuid;
  v_token text;
  v_row jsonb;
  updated boolean;
begin
  v_center := public._center_from_slug_or_code(p_slug, p_code);
  if v_center is null then
    return jsonb_build_object('ok', false, 'reason', 'center');
  end if;
  v_token := coalesce(p_row ->> 'token', '');
  if v_token = '' then
    return jsonb_build_object('ok', false, 'reason', 'token');
  end if;

  v_row := public._jsonb_pick_keys(coalesce(p_row, '{}'::jsonb), array[
      'token','target_type','job_key','company','type1','manager','device_key',
      'interest_jobs','platform','updated_at'
    ])
    || jsonb_build_object('center_id', v_center, 'token', v_token);
  updated := public._jsonb_update_by_text_public('push_tokens', v_row, 'token', v_token);
  if not updated then
    begin
      perform public._jsonb_insert_public('push_tokens', v_row);
    exception when unique_violation then
      perform public._jsonb_update_by_text_public('push_tokens', v_row, 'token', v_token);
      return jsonb_build_object('ok', true, 'duplicate', true, 'center_id', v_center);
    end;
  end if;
  return jsonb_build_object('ok', true, 'center_id', v_center);
end $$;
grant execute on function public.register_push_token(text, text, jsonb) to anon, authenticated;

create or replace function public.submit_poll_vote(p_poll uuid, p_choices jsonb, p_device_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_center uuid;
begin
  select center_id into v_center
    from public.polls
   where id = p_poll
     and open
     and (close_at is null or now() < close_at);
  if v_center is null then
    return jsonb_build_object('ok', false, 'reason', 'closed');
  end if;
  perform public._jsonb_insert_public('poll_votes', jsonb_build_object(
    'poll_id', p_poll, 'choices', p_choices, 'device_id', p_device_id, 'center_id', v_center
  ));
  return jsonb_build_object('ok', true, 'center_id', v_center);
exception when unique_violation then
  return jsonb_build_object('ok', true, 'duplicate', true, 'center_id', v_center);
end $$;
grant execute on function public.submit_poll_vote(uuid, jsonb, text) to anon, authenticated;

create or replace function public.submit_survey_answer(
  p_survey uuid,
  p_answers jsonb,
  p_comment text,
  p_job_key text,
  p_device_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_center uuid;
begin
  select center_id into v_center
    from public.surveys
   where id = p_survey and open;
  if v_center is null then
    return jsonb_build_object('ok', false, 'reason', 'closed');
  end if;
  perform public._jsonb_insert_public('survey_answers', jsonb_build_object(
    'survey_id', p_survey, 'answers', p_answers, 'comment', nullif(p_comment, ''),
    'job_key', nullif(p_job_key, ''), 'device_id', p_device_id, 'center_id', v_center
  ));
  return jsonb_build_object('ok', true, 'center_id', v_center);
exception when unique_violation then
  return jsonb_build_object('ok', true, 'duplicate', true, 'center_id', v_center);
end $$;
grant execute on function public.submit_survey_answer(uuid, jsonb, text, text, text) to anon, authenticated;

create or replace function public.submit_company_survey_response(p_slug text, p_code text, p_row jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_center uuid;
  v_row jsonb;
begin
  v_center := public._center_from_slug_or_code(p_slug, p_code);
  if v_center is null then
    return jsonb_build_object('ok', false, 'reason', 'center');
  end if;
  v_row := public._jsonb_pick_keys(coalesce(p_row, '{}'::jsonb), array[
      'survey_key','round','company','answers','comment','device_id'
    ])
    || jsonb_build_object('center_id', v_center);
  perform public._jsonb_insert_public('company_survey_responses', v_row);
  return jsonb_build_object('ok', true, 'center_id', v_center);
exception when unique_violation then
  return jsonb_build_object('ok', true, 'duplicate', true, 'center_id', v_center);
end $$;
grant execute on function public.submit_company_survey_response(text, text, jsonb) to anon, authenticated;

-- ── E. 기존 SECURITY DEFINER 조회 RPC도 센터 스코프로 보강 ────────────
create or replace function public.my_targeted_library(p_token text)
returns setof public.library
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  h text;
  v_center uuid;
begin
  v_center := public.request_center_id();
  if v_center is null or p_token is null or length(p_token) < 8 then
    return;
  end if;
  h := substring(encode(digest(p_token, 'sha256'), 'hex') for 16);
  return query
    select *
      from public.library
     where published = true
       and center_id = v_center
       and job_key like 'tokv:%'
       and (substring(job_key from 6))::jsonb -> 'tok' ? h;
end $$;
grant execute on function public.my_targeted_library(text) to anon, authenticated;

create or replace function public.my_targeted_calendar(p_token text)
returns setof public.calendar_events
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  h text;
  v_center uuid;
begin
  v_center := public.request_center_id();
  if v_center is null or p_token is null or length(p_token) < 8 then
    return;
  end if;
  h := substring(encode(digest(p_token, 'sha256'), 'hex') for 16);
  return query
    select *
      from public.calendar_events
     where center_id = v_center
       and job_key like 'tokv:%'
       and event_date >= current_date
       and (substring(job_key from 6))::jsonb -> 'tok' ? h;
end $$;
grant execute on function public.my_targeted_calendar(text) to anon, authenticated;

create or replace function public.my_targeted_calendar_from(p_token text, p_from date)
returns setof public.calendar_events
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  h text;
  v_center uuid;
begin
  v_center := public.request_center_id();
  if v_center is null or p_token is null or length(p_token) < 8 then
    return;
  end if;
  h := substring(encode(digest(p_token, 'sha256'), 'hex') for 16);
  return query
    select *
      from public.calendar_events
     where center_id = v_center
       and job_key like 'tokv:%'
       and event_date >= greatest(coalesce(p_from, current_date), (current_date - interval '92 days')::date)
       and (substring(job_key from 6))::jsonb -> 'tok' ? h;
end $$;
grant execute on function public.my_targeted_calendar_from(text, date) to anon, authenticated;

create or replace function public.poll_results(p_poll uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  pl record;
  cnts jsonb;
  tot bigint;
  v_center uuid;
begin
  v_center := coalesce(public.request_center_id(), public.current_admin_center());
  select * into pl from public.polls where id = p_poll;
  if not found then return null; end if;
  if not public.is_super_admin() and (v_center is null or pl.center_id is distinct from v_center) then
    return null;
  end if;

  select count(*) into tot from public.poll_votes where poll_id = p_poll;
  if not pl.results_public and auth.uid() is null then
    return jsonb_build_object('total', tot, 'counts', null);
  end if;
  select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) into cnts from (
    select v.value as k, count(*) as n
      from public.poll_votes pv, jsonb_array_elements_text(pv.choices) v
     where pv.poll_id = p_poll
     group by v.value
  ) s;
  return jsonb_build_object('total', tot, 'counts', cnts);
end $$;
grant execute on function public.poll_results(uuid) to anon, authenticated;

create or replace function public.my_company_stage(p_company text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cs record;
  norm_in text;
  v_center uuid;
begin
  v_center := coalesce(public.request_center_id(), public.current_admin_center());
  if v_center is null then return null; end if;
  norm_in := replace(replace(replace(replace(lower(coalesce(p_company, '')), '㈜', ''), '(주)', ''), '주식회사', ''), ' ', '');
  select * into cs from public.company_stages
   where center_id = v_center
     and replace(replace(replace(replace(lower(company), '㈜', ''), '(주)', ''), '주식회사', ''), ' ', '') = norm_in;
  if not found then return null; end if;
  return jsonb_build_object('company', cs.company, 'stage_key', cs.stage_key, 'memo', cs.memo, 'updated_at', cs.updated_at);
end $$;
grant execute on function public.my_company_stage(text) to anon, authenticated;

create or replace function public.my_company_info(p_company text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  norm_in text;
  ci record;
  v_center uuid;
begin
  v_center := coalesce(public.request_center_id(), public.current_admin_center());
  if v_center is null then return null; end if;
  norm_in := replace(replace(replace(replace(lower(coalesce(p_company, '')), '㈜', ''), '(주)', ''), '주식회사', ''), ' ', '');
  if norm_in = '' then return null; end if;

  select * into ci from public.company_info
   where center_id = v_center
     and replace(replace(replace(replace(lower(company), '㈜', ''), '(주)', ''), '주식회사', ''), ' ', '') = norm_in
   limit 1;

  return jsonb_build_object(
    'company', coalesce(ci.company, p_company),
    'info', case when ci.company is null then null else
      jsonb_build_object('beacon', ci.beacon, 'commute', ci.commute, 'schedule', ci.schedule, 'extra', ci.extra, 'updated_at', ci.updated_at) end,
    'contacts', coalesce((
      select jsonb_agg(jsonb_build_object('role', cc.role, 'name', cc.name) order by cc.role)
        from public.company_contacts cc
       where cc.center_id = v_center
         and coalesce(cc.status, '') <> '종료'
         and cc.name is not null and cc.name <> ''
         and replace(replace(replace(replace(lower(cc.company), '㈜', ''), '(주)', ''), '주식회사', ''), ' ', '') = norm_in
    ), '[]'::jsonb)
  );
end $$;
grant execute on function public.my_company_info(text) to anon, authenticated;
