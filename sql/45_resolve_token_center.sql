-- 45_resolve_token_center.sql — sign-library 토큰 폴백 헬퍼 (서비스 전용)
-- 문제: 알림 미허용 기기(push_tokens 없음)·iOS 설치앱 복원 프로필은 서명기 자격 검증 실패
--       → 학습안내서 다운로드 403 (2026-08-20 실사고).
-- 해결: 서명토큰을 명단(make_student_token)과 대조해 센터 반환. sign-library 가 push_tokens
--       미스 시 이 함수로 폴백. service_role 전용(클라 직접 호출 불가).
-- 운영 적용: 2026-08-20 (토큰 경로 서명·다운로드 검증 완료)
create or replace function public.resolve_token_center(p_token text)
returns uuid
language sql security definer set search_path = public as $$
  select s.center_id from students s
   where char_length(coalesce(p_token, '')) >= 20
     and s.phone is not null
     and make_student_token(s.name, s.phone) = p_token
   limit 1
$$;
revoke all on function public.resolve_token_center(text) from public, anon, authenticated;
grant execute on function public.resolve_token_center(text) to service_role;
