-- 51_beacon_nightly_clear.sql — 비콘 알림 저녁 자동 정리
-- 운영자 관찰: 개인 공지함에 비콘 알림이 하루 종일 상주 → 매일 20:00 KST(11:00 UTC)
-- auto:beacon% 공지·수신자 삭제. 근무시간(입실 09시 생성~20시)에만 노출되는 리듬.
-- 운영 적용: 2026-08-20
create or replace function public.clear_beacon_notices()
returns void language sql security definer set search_path = public as $$
  delete from notice_recipients where notice_id in
    (select id from notices where created_by like 'auto:beacon%');
  delete from notices where created_by like 'auto:beacon%';
$$;
revoke all on function public.clear_beacon_notices() from public, anon, authenticated;
select cron.unschedule(jobid) from cron.job where jobname = 'beacon-clear-nightly';
select cron.schedule('beacon-clear-nightly', '0 11 * * *', $$select public.clear_beacon_notices()$$);
