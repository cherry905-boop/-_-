-- 47_attendance_units.sql — 진도 카드에 월별 훈련 능력단위 표시 (일정 의존 제거)
-- 배경: 운영자가 달력을 능력단위·내부평가 일정 없이 비우기로 결정(2026-08-20) →
--       카드가 calendar_events 대신 attendance_monthly.units 를 직접 표시.
-- units 는 훈련과정개발보고서 월차 배정에서 채움(회사 기준, 프리시스는 학생별 과정 분리).
-- my_attendance 반환에 'units' 필드 추가. 운영 적용: 2026-08-20 (119행 전량 채움).
alter table public.attendance_monthly add column if not exists units text;
-- (units 데이터 적재는 운영 DB에서 완료 — 재구축 시 개발보고서 월차 배정으로 재적재)
-- my_attendance 갱신본은 sql/44 형태에 'units', a.units 필드만 추가 — 함수 원본은 DB 참조.
