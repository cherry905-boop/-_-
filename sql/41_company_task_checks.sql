-- 41. TASKS v2 Step 5 — 기업 단위 완료체크 + 진행률 기업 지원 + tasks 관리자 쓰기 center_id 자동주입
-- 계획: docs/TASKS_V2_PLAN.md Q4 확정안(기업코드 재검증 → 기업 단위 완료. 담당자 개인 구분 없음).
-- 전제: sql/40 적용됨(task_checks·_task_subject_hash·admin_task_progress v1). 멱등: 재실행 안전.
-- 식별: subject_kind='company' 행의 subject_hash 에는 해시가 아니라 company_codes.company 문자열을 그대로 저장한다
--       (양쪽 모두 company_codes 에서 도출하므로 문자열이 정확히 일치 — 별도 정규화 불필요. PII 아님).

-- ── ① 기업담당자: 완료 체크 — 기업코드 재검증(신원=코드 소지) 후 기업 단위 upsert ──
create or replace function public.complete_company_task(p_task_id uuid, p_code text)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_center uuid; v_co text; v_task record;
begin
  if p_task_id is null or p_code is null or length(trim(p_code)) < 4 then
    return jsonb_build_object('ok', false, 'reason', 'bad_request');
  end if;
  v_center := public.request_center_id();
  if v_center is null then return jsonb_build_object('ok', false, 'reason', 'center_required'); end if;
  if to_regprocedure('public.check_verify_rate(text)') is not null then
    perform public.check_verify_rate('cotaskchk:' || upper(trim(p_code)));
  end if;
  select company into v_co from public.company_codes
   where upper(code) = upper(trim(p_code)) and active and center_id = v_center
   limit 1;
  if not found then return jsonb_build_object('ok', false, 'reason', 'bad_code'); end if;
  select id, center_id, audience, published into v_task from public.tasks where id = p_task_id;
  if not found or v_task.published is distinct from true or v_task.center_id is distinct from v_center then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;
  if coalesce(v_task.audience, '전체') <> '기업' then
    return jsonb_build_object('ok', false, 'reason', 'audience_mismatch');   -- 학생용은 complete_task 로
  end if;
  insert into public.task_checks (center_id, task_id, subject_kind, subject_hash)
  values (v_center, p_task_id, 'company', v_co)
  on conflict (center_id, task_id, subject_kind, subject_hash) do nothing;
  if not found then return jsonb_build_object('ok', true, 'duplicate', true, 'company', v_co); end if;
  return jsonb_build_object('ok', true, 'company', v_co);
end $$;
grant execute on function public.complete_company_task(uuid, text) to anon, authenticated;

-- ── ② 기업담당자: 완료 해제 — 마감 경과 후 불가(Q3, 학생과 동일 게이트) ──
create or replace function public.uncheck_company_task(p_task_id uuid, p_code text)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_center uuid; v_co text; v_due date;
begin
  if p_task_id is null or p_code is null or length(trim(p_code)) < 4 then
    return jsonb_build_object('ok', false, 'reason', 'bad_request');
  end if;
  v_center := public.request_center_id();
  if v_center is null then return jsonb_build_object('ok', false, 'reason', 'center_required'); end if;
  select company into v_co from public.company_codes
   where upper(code) = upper(trim(p_code)) and active and center_id = v_center
   limit 1;
  if not found then return jsonb_build_object('ok', false, 'reason', 'bad_code'); end if;
  select due_date into v_due from public.tasks where id = p_task_id and center_id = v_center;
  if not found then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  if v_due is not null and v_due < current_date then
    return jsonb_build_object('ok', false, 'reason', 'locked');
  end if;
  delete from public.task_checks
   where center_id = v_center and task_id = p_task_id and subject_kind = 'company' and subject_hash = v_co;
  return jsonb_build_object('ok', true, 'removed', found);
end $$;
grant execute on function public.uncheck_company_task(uuid, text) to anon, authenticated;

-- ── ③ 기업담당자: 우리 회사 완료 상태 조회 (read-model) ──
create or replace function public.my_company_task_checks(p_code text, p_task_ids uuid[] default null)
returns setof uuid
language plpgsql stable security definer set search_path = public, extensions as $$
declare v_center uuid; v_co text;
begin
  if p_code is null or length(trim(p_code)) < 4 then return; end if;
  v_center := public.request_center_id();
  if v_center is null then return; end if;
  select company into v_co from public.company_codes
   where upper(code) = upper(trim(p_code)) and active and center_id = v_center
   limit 1;
  if not found then return; end if;
  return query
    select tc.task_id from public.task_checks tc
     where tc.center_id = v_center and tc.subject_kind = 'company' and tc.subject_hash = v_co
       and (p_task_ids is null or tc.task_id = any(p_task_ids));
end $$;
grant execute on function public.my_company_task_checks(text, uuid[]) to anon, authenticated;

-- ── ④ 관리자 진행률 v2 — audience='기업' 지원 (40의 함수를 확장 교체) ──
--    기업 분모 = 활성 기업코드 보유 기업(체크 가능 주체와 동일 기준). 학생 로직은 40과 동일.
create or replace function public.admin_task_progress(p_task_id uuid)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_task record; v_center uuid; r record; v jsonb; tok text; h text;
  done_names text[] := '{}'; pending_names text[] := '{}'; unknown_names text[] := '{}';
begin
  if auth.role() is distinct from 'authenticated' then raise exception 'forbidden'; end if;
  select id, center_id, audience into v_task from public.tasks where id = p_task_id;
  if not found then raise exception 'not_found'; end if;
  if to_regprocedure('public.current_admin_center()') is not null then
    v_center := public.current_admin_center();
    if v_task.center_id is distinct from v_center
       and not (to_regprocedure('public.is_super_admin()') is not null and public.is_super_admin()) then
      raise exception 'forbidden';
    end if;
  end if;

  if coalesce(v_task.audience, '전체') = '기업' then
    for r in select company from public.company_codes
      where active and center_id = v_task.center_id order by company
    loop
      if exists (select 1 from public.task_checks tc
                  where tc.task_id = v_task.id and tc.subject_kind = 'company' and tc.subject_hash = r.company) then
        done_names := array_append(done_names, r.company);
      else
        pending_names := array_append(pending_names, r.company);
      end if;
    end loop;
    return jsonb_build_object(
      'ok', true, 'company', true,
      'total', coalesce(array_length(done_names, 1), 0) + coalesce(array_length(pending_names, 1), 0),
      'done', coalesce(array_length(done_names, 1), 0),
      'done_names', to_jsonb(done_names), 'pending_names', to_jsonb(pending_names),
      'unknown_names', '[]'::jsonb);
  end if;

  if to_regprocedure('public.verify_student(text,text)') is null then
    raise exception 'verify_student 미적용(R계열) — 시스템 담당자에게 서버 설정 적용을 요청해주세요';
  end if;
  for r in
    select name, phone from public.registrations
     where center_id = v_task.center_id
       and coalesce(target_type, 'student') = 'student'
       and coalesce(status, '진행중') = '진행중'
  loop
    begin
      v := (select public.verify_student(r.name, r.phone))::jsonb;
      tok := v->>'token';
      if coalesce((v->>'matched')::boolean, false) and tok is not null then
        h := public._task_subject_hash(tok);
        if exists (select 1 from public.task_checks tc
                    where tc.task_id = v_task.id and tc.subject_kind = 'student' and tc.subject_hash = h) then
          done_names := array_append(done_names, r.name);
        else
          pending_names := array_append(pending_names, r.name);
        end if;
      else
        unknown_names := array_append(unknown_names, r.name);
      end if;
    exception when others then
      unknown_names := array_append(unknown_names, r.name);
    end;
  end loop;
  return jsonb_build_object(
    'ok', true,
    'total', coalesce(array_length(done_names, 1), 0)
           + coalesce(array_length(pending_names, 1), 0)
           + coalesce(array_length(unknown_names, 1), 0),
    'done', coalesce(array_length(done_names, 1), 0),
    'done_names', to_jsonb(done_names),
    'pending_names', to_jsonb(pending_names),
    'unknown_names', to_jsonb(unknown_names));
end $$;
revoke execute on function public.admin_task_progress(uuid) from public, anon;
grant execute on function public.admin_task_progress(uuid) to authenticated;

-- ── ⑤ tasks 관리자 쓰기에 center_id 자동주입 — 콘솔 '할 일 등록' UI 지원 (sql/25 트리거 재사용) ──
do $$
begin
  if to_regproc('public._set_center_id_on_write') is not null and to_regclass('public.tasks') is not null then
    if not exists (select 1 from pg_trigger where tgname = 'set_center_id_tasks' and tgrelid = 'public.tasks'::regclass) then
      create trigger set_center_id_tasks before insert on public.tasks
        for each row execute function public._set_center_id_on_write();
    end if;
  end if;
end $$;
