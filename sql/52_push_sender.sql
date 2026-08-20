-- 52_push_sender.sql — 발송기 이전: 개인 Apps Script → Supabase 엣지 함수 push-sender
-- (절대규칙 9 해소 — 푸시 인프라의 개인 구글 계정 의존 제거)
--  · push-sender: 미발송 공지 → FCM v1 발송(secret FIREBASE_SERVICE_ACCOUNT), personal/타게팅
--    매칭, 무효 토큰 자동 정리, push_logs 기록, 클릭 시 새 주소(notice.html) 열림.
--  · 5분 폴링 크론(push-sender-poll) + 비콘 알림(sql/48)·config.js 킥을 새 발송기로 교체.
--  · 구 발송기는 service_role 키 재발급으로 자연 무력화(운영자 수행).
-- 운영 적용: 2026-08-20. 함수 소스: supabase/functions/push-sender/index.ts
select cron.unschedule(jobid) from cron.job where jobname = 'push-sender-poll';
select cron.schedule('push-sender-poll', '*/5 * * * *',
  $$select net.http_get('https://ggitgqijycvnhhraxzgn.supabase.co/functions/v1/push-sender')$$);
-- send_beacon_reminders 킥 URL 교체본은 마이그레이션 이력(push_sender_cron)·DB 참조.
