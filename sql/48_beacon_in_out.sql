-- =====================================================================
-- 48_beacon_in_out.sql — 비콘 알림 입실·퇴실 2회 체제 (sql/43 대체)
-- 평일 09:00 입실 · 16:00 퇴실(KST = UTC 00:00·07:00 월~금).
-- 대상: 이번 달 실적<예정 학생(100% 달성자 자동 제외), 본인 진도 수치 포함 개인 공지.
-- 실행마다 이전 자동 알림(auto:beacon%) 전체 교체 — 공지함엔 항상 최신 1건.
-- 기존 08:30 단일 알림(beacon-reminder-daily)은 09:00 입실로 통합·폐지.
-- 운영 적용: 2026-08-20 (rollback 테스트로 함수 검증, 첫 실발송 = 당일 16:00 퇴실)
-- =====================================================================

drop function if exists public.send_beacon_reminders();

create or replace function public.send_beacon_reminders(p_kind text default 'in')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_center uuid; v_month date; v_notice uuid; cnt int := 0; r record;
        v_title text; v_body_fmt text; v_common text;
begin
  select id into v_center from centers where slug = 'mju';
  v_month := date_trunc('month', (now() at time zone 'Asia/Seoul'))::date;

  if p_kind = 'out' then
    v_title := '퇴실 비콘 알림';
    v_common := '퇴근 전 퇴실 비콘 꼭 찍어주세요! 오늘도 수고했어요.';
    v_body_fmt := '퇴근 전 퇴실 비콘 꼭 찍어주세요! 이번 달 출석 진도 %s시간 / 배정 %s시간이에요.';
  else
    v_title := '입실 비콘 알림';
    v_common := '좋은 아침이에요! 출근하면 입실 비콘부터 찍어주세요.';
    v_body_fmt := '출근하면 입실 비콘부터 찍어주세요! 이번 달 출석 진도 %s시간 / 배정 %s시간이에요.';
  end if;

  delete from notice_recipients where notice_id in
    (select id from notices where created_by like 'auto:beacon%' and center_id = v_center);
  delete from notices where created_by like 'auto:beacon%' and center_id = v_center;

  create temp table _lag on commit drop as
    select a.name, s.phone, a.planned_hours, coalesce(a.actual_hours, 0) as actual_hours
      from attendance_monthly a
      join students s on s.center_id = a.center_id
       and replace(trim(s.name), ' ', '') = replace(trim(a.name), ' ', '')
     where a.center_id = v_center and a.month = v_month
       and a.planned_hours > 0
       and coalesce(a.actual_hours, 0) < a.planned_hours;

  if not exists (select 1 from _lag) then
    return jsonb_build_object('ok', true, 'sent', 0, 'note', 'no_targets');
  end if;

  insert into notices (center_id, title, body, target_scope, published, created_by, pushed)
  values (v_center, v_title, v_common, 'personal', true, 'auto:beacon-' || p_kind, false)
  returning id into v_notice;

  for r in select * from _lag loop
    insert into notice_recipients (notice_id, student_token, title, body, center_id)
    values (v_notice, make_student_token(r.name, r.phone), v_title,
            format(v_body_fmt, r.actual_hours::int, r.planned_hours::int), v_center);
    cnt := cnt + 1;
  end loop;

  begin
    perform net.http_get('https://script.google.com/macros/s/AKfycbxMet7mrgG84A33lg3Kwc5j_Z2-MX7BR3EkdqIkEiPe1bMc-nLvFqGtqYmYOWgFeQvo2A/exec');
  exception when others then null;
  end;

  return jsonb_build_object('ok', true, 'kind', p_kind, 'sent', cnt, 'month', to_char(v_month, 'YYYY-MM'));
end $$;
revoke all on function public.send_beacon_reminders(text) from public, anon, authenticated;

select cron.unschedule(jobid) from cron.job where jobname in ('beacon-reminder-daily','beacon-in-daily','beacon-out-daily');
select cron.schedule('beacon-in-daily',  '0 0 * * 1-5', $$select public.send_beacon_reminders('in')$$);
select cron.schedule('beacon-out-daily', '0 7 * * 1-5', $$select public.send_beacon_reminders('out')$$);
