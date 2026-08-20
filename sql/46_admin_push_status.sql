-- 46_admin_push_status.sql — 가입자 탭 '알림 켠 기기' 현황 (관리자 전용)
-- push_tokens.device_key = make_student_token(명단 이름·전화) 대조로 학생별 알림 기기 수 집계.
-- 운영 적용: 2026-08-20
create or replace function public.admin_push_status()
returns table(name text, devices bigint, last_at timestamptz)
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from admin_users au where au.user_id = auth.uid()) then
    raise exception 'not_admin';
  end if;
  return query
    select s.name, count(pt.id)::bigint, max(coalesce(pt.updated_at, pt.created_at))
      from students s
      join push_tokens pt on pt.device_key = make_student_token(s.name, s.phone)
     where is_super_admin() or s.center_id = current_admin_center()
     group by s.name;
end $$;
revoke all on function public.admin_push_status() from public, anon;
grant execute on function public.admin_push_status() to authenticated;
