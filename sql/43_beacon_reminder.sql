-- =====================================================================
-- 43_beacon_reminder.sql — 매일 아침 진도 100% 미만 학생에게 '비콘 체크' 개인 알림
-- 멱등. 전제: pg_cron·pg_net 확장, attendance_monthly(sql/42), 개인 공지 인프라(sql/07).
--  · 매일 08:30 KST(23:30 UTC) pg_cron 실행 → 이번 달 실적<예정 학생에게
--    target_scope='personal' 공지 + notice_recipients(본인 수치 포함) 생성.
--  · 어제 자동 알림은 삭제 후 재생성(공지함 누적 방지). created_by='auto:beacon' 태그.
--  · 발송은 기존 푸시 발송기(pushed=false 스캔)가 처리, pg_net 으로 킥.
--  · 함수는 크론 전용 — anon/authenticated 실행 권한 없음.
-- 운영 적용: 2026-08-19 (수동 1회 실행 검증: 12명 생성, 100% 달성 4명 제외 확인)
-- =====================================================================

create extension if not exists pg_cron;
create extension if not exists pg_net;

create or replace function public.send_beacon_reminders()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_center uuid; v_month date; v_notice uuid; cnt int := 0; r record;
begin
  select id into v_center from centers where slug = 'mju';
  v_month := date_trunc('month', (now() at time zone 'Asia/Seoul'))::date;

  delete from notice_recipients where notice_id in
    (select id from notices where created_by = 'auto:beacon' and center_id = v_center);
  delete from notices where created_by = 'auto:beacon' and center_id = v_center;

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
  values (v_center, '비콘 체크 알림',
          '이번 달 출석 진도가 아직 100%가 아니에요. 출퇴근할 때 비콘 체크를 잊지 마세요!',
          'personal', true, 'auto:beacon', false)
  returning id into v_notice;

  for r in select * from _lag loop
    insert into notice_recipients (notice_id, student_token, title, body, center_id)
    values (v_notice, make_student_token(r.name, r.phone), '비콘 체크 알림',
            format('이번 달 출석 진도 %s시간 / 배정 %s시간이에요. 출퇴근할 때 비콘 체크 잊지 마세요!',
                   r.actual_hours::int, r.planned_hours::int),
            v_center);
    cnt := cnt + 1;
  end loop;

  begin
    perform net.http_get('https://script.google.com/macros/s/AKfycbxMet7mrgG84A33lg3Kwc5j_Z2-MX7BR3EkdqIkEiPe1bMc-nLvFqGtqYmYOWgFeQvo2A/exec');
  exception when others then null;
  end;

  return jsonb_build_object('ok', true, 'sent', cnt, 'month', to_char(v_month, 'YYYY-MM'));
end $$;

revoke all on function public.send_beacon_reminders() from public, anon, authenticated;

select cron.unschedule(jobid) from cron.job where jobname = 'beacon-reminder-daily';
select cron.schedule('beacon-reminder-daily', '30 23 * * *', $$select public.send_beacon_reminders()$$);
