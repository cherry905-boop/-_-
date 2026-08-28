-- =====================================================================
-- 54_task_progress_roster.sql — 할 일 진행률 분모를 '명단(students)' 기준으로 교정
-- 멱등(create or replace). 적용 전제: sql/40(task_checks·_task_subject_hash)·41(v2) 적용됨.
--
-- 배경(버그): admin_task_progress 의 학생 분모가 registrations(=앱 '가입 행') 이었다.
--   registrations 는 register_with_code(sql/24) 가 매 가입마다 그냥 insert 하므로 유일성이 없다.
--   같은 학생이 기기를 바꾸거나 재설치하면(특히 iOS 설치앱↔Safari 저장소 분리, sql/44 참조) 행이 하나 더
--   생기고, 명단에서 빠진 옛 가입 행도 그대로 남는다 → 17명 명단인데 진행률 분모가 22로 부풀었다.
--   같은 사람이 완료자·미완료자 목록에 두 번 나타나는 문제도 동일 원인.
--
-- 교정: 학생 분모 = 명단(students, 센터 스코프, 상태 '진행중') 을 이름·전화 정규화로 중복 제거한 인원 수.
--   · done      = 명단 인원 중 완료 체크가 있는 사람
--   · pending   = 미완료 + 앱 가입 있음(독촉 공지 발송 가능)
--   · unknown   = 미완료 + 앱 가입 없음/토큰 대조 실패(= 앱 설치 안내 대상)
--   총계 계약(total = done + pending + unknown)은 41과 동일하게 유지 → 프론트 무회귀.
--   기업(audience='기업') 분기는 41 그대로(활성 기업코드 보유 기업 기준).
-- =====================================================================

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

  -- ── 기업 대상: 41과 동일(활성 기업코드 보유 기업 = 체크 가능 주체) ──
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

  -- ── 학생 대상: 분모 = 명단(students) 중복제거 ──
  -- 정규화: 이름은 공백 제거, 전화는 숫자만. 무폰 학생(sql/50)은 이름만으로 구분된다.
  for r in
    with roster as (
      select s.name, s.phone,
             row_number() over (
               partition by regexp_replace(coalesce(s.name, ''), '\s', '', 'g'),
                            regexp_replace(coalesce(s.phone, ''), '\D', '', 'g')
               order by s.name) as rn
        from public.students s
       where s.center_id = v_task.center_id
         and coalesce(s.status, '진행중') = '진행중'
    )
    select name, phone from roster where rn = 1 order by name
  loop
    begin
      v := (select public.verify_student(r.name, r.phone))::jsonb;
      tok := v->>'token';
      if coalesce((v->>'matched')::boolean, false) and tok is not null then
        h := public._task_subject_hash(tok);
        if exists (select 1 from public.task_checks tc
                    where tc.task_id = v_task.id and tc.subject_kind = 'student' and tc.subject_hash = h) then
          done_names := array_append(done_names, r.name);
        -- 미완료: 앱 가입 행이 있어야 독촉 공지가 닿는다 → pending, 아니면 설치 안내 대상(unknown)
        elsif exists (
          select 1 from public.registrations g
           where g.center_id = v_task.center_id
             and coalesce(g.target_type, 'student') = 'student'
             and regexp_replace(coalesce(g.name, ''), '\s', '', 'g')
               = regexp_replace(coalesce(r.name, ''), '\s', '', 'g')
             and regexp_replace(coalesce(g.phone, ''), '\D', '', 'g')
               = regexp_replace(coalesce(r.phone, ''), '\D', '', 'g')
        ) then
          pending_names := array_append(pending_names, r.name);
        else
          unknown_names := array_append(unknown_names, r.name);
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
