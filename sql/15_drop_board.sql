-- 15. 익명 건의함 폐지 — 페이지 삭제와 함께 데이터도 완전 삭제 (사용자 결정, 복구 불가)
-- cascade가 RLS 정책도 함께 제거. sql/07의 board_posts 참조는 to_regclass 가드라 영향 없음.
drop table if exists public.board_posts cascade;
