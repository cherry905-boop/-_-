-- 49_code_only_entry.sql — 초대코드 전용 진입 강화
-- 복원(내 정보 불러오기)의 이름+휴대폰 경로 폐지(index.html)와 짝 — 사칭 방지.
-- verify_student(text,text) 익명 실행 회수. 서버 내부(SECURITY DEFINER) 호출·관리자 사용 무영향.
-- 운영 적용: 2026-08-20 (코드 가입 정상·이름조회 차단 검증 완료)
revoke execute on function public.verify_student(text, text) from anon;
