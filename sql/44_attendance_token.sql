-- =====================================================================
-- 44_attendance_token.sql — my_attendance 토큰 폴백
-- 문제: iOS 설치앱은 Safari와 저장소가 분리 → '내 정보 불러오기' 복원 프로필엔
--       초대코드가 없어 코드 전용이던 진도 카드가 안 뜸 (2026-08-20 실사고).
-- 해결: (p_code, p_token) 2인자 — 코드 우선, 없으면 서명토큰으로 명단 대조.
--       복원 프로필엔 토큰이 항상 있으므로 모든 진입 경로에서 카드 동작.
-- 운영 적용: 2026-08-20 (김승민 토큰 경로·코드 경로·오입력 거부 검증 완료)
-- =====================================================================

drop function if exists public.my_attendance(text);

create or replace function public.my_attendance(p_code text default null, p_token text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare ip text; rows jsonb; v_name text; v_center uuid;
begin
  ip := coalesce(current_setting('request.headers', true)::jsonb ->> 'x-forwarded-for', 'unknown');
  begin
    perform check_verify_rate('attn:' || ip);
  exception when undefined_function then null;
  end;
  if coalesce(p_code, '') <> '' then
    select sc.name, sc.center_id into v_name, v_center from student_codes sc
     where sc.code = upper(regexp_replace(p_code, '[^A-Za-z0-9]', '', 'g')) and sc.active;
  end if;
  if v_name is null and char_length(coalesce(p_token, '')) >= 20 then
    select s.name, s.center_id into v_name, v_center from students s
     where s.phone is not null and make_student_token(s.name, s.phone) = p_token
     limit 1;
  end if;
  if v_name is null then
    return jsonb_build_object('ok', false);
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'month', to_char(a.month, 'YYYY-MM'),
           'planned', a.planned_hours,
           'actual', a.actual_hours,
           'updated_at', a.updated_at) order by a.month), '[]'::jsonb)
    into rows
    from attendance_monthly a
   where a.center_id = v_center
     and replace(trim(a.name), ' ', '') = replace(trim(v_name), ' ', '');
  return jsonb_build_object('ok', true, 'rows', rows);
end $$;
grant execute on function public.my_attendance(text, text) to anon, authenticated;
