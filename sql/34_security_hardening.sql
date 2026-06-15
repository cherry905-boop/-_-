-- sql/34_security_hardening.sql
-- 2026-06-15 라이브 RLS 점검 결과, 잔존 '갓모드' 정책 3종(① DELETE / ② admin_logs / ③ 전센터 SELECT) 제거.
-- 대상: 운영 DB (서울 프로젝트 ggitgqijycvnhhraxzgn). 모두 되돌리기 가능. 원자적 적용을 위해 트랜잭션으로 감쌈.
-- 사전 점검으로 확인된 사실: 핵심 PII는 이미 "is_super_admin() OR center_id=current_admin_center()" 로 센터격리됨.
--                          아래 정책들만 그 위에 OR로 얹혀 격리를 무력화하던 레거시.

begin;

-- ========== [A] 레거시 갓모드 DELETE 정책 6건 제거 ==========
-- 정당한 관리자 삭제는 각 테이블의 센터격리 ALL 정책(DELETE 포함)이 이미 커버.
-- "admin delete" = [DELETE {authenticated} USING true] → '로그인한 누구나 타센터 삭제' 허용하던 잔존(sql/07).
drop policy if exists "admin delete" on public.consultations;
drop policy if exists "admin delete" on public.consultation_messages;
drop policy if exists "admin delete" on public.notices;
drop policy if exists "admin delete" on public.notice_recipients;
drop policy if exists "admin delete" on public.library;
drop policy if exists "admin delete" on public.calendar_events;

-- ========== [B] admin_logs: 센터격리 + 추가전용(append-only) 감사로그 ==========
-- 현재 "admin manage logs" = [ALL (auth.uid() IS NOT NULL)] → 로그인한 누구나 읽기·위조·삭제 가능.
-- 앱(admin.html)은 insert(기록) + 최근 8건 select 만 사용하므로 update/delete를 봉인해 감사 무결성 확보.
alter table public.admin_logs add column if not exists center_id uuid;
alter table public.admin_logs alter column center_id set default current_admin_center();  -- 신규 기록은 작성자 센터 자동 태깅
update public.admin_logs
   set center_id = 'deef2f26-2b37-4c2f-bea6-53be74212a51'   -- 기존 176건은 운영 센터(mju)로 백필
 where center_id is null;
drop policy if exists "admin manage logs" on public.admin_logs;
create policy "admin_logs select" on public.admin_logs
  for select using (is_super_admin() or center_id = current_admin_center());
create policy "admin_logs insert" on public.admin_logs
  for insert with check (is_super_admin() or center_id = current_admin_center());
-- update/delete 정책 없음 → 누구도(super_admin 포함) 로그 수정·삭제 불가 = 추가전용.

-- ========== [C] survey_responses / sync_log: '로그인한 누구나 열람' → '관리자만' ==========
-- 두 테이블은 center_id가 없어 '센터별' 격리는 추후 과제(소스 insert에 center_id 추가 필요).
-- 우선 비관리자(학생 등) 로그인 계정의 열람만 차단. (민감도 낮음: 평점/동기화 카운트)
drop policy if exists "admin read survey" on public.survey_responses;
create policy "admin read survey" on public.survey_responses
  for select using (is_super_admin() or current_admin_center() is not null);
drop policy if exists "admin read sync_log" on public.sync_log;
create policy "admin read sync_log" on public.sync_log
  for select using (is_super_admin() or current_admin_center() is not null);

commit;

-- ===== 적용 후 검증 (각각 0건이어야 정상) =====
-- A: select tablename, cmd from pg_policies where schemaname='public' and qual='true' and cmd='DELETE';
-- B/C: select tablename, cmd, qual from pg_policies
--      where schemaname='public' and qual='(auth.uid() IS NOT NULL)';
