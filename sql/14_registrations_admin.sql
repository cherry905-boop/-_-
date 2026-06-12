-- 14_registrations_admin.sql — 가입자(registrations) 관리자 조회·삭제 정책
-- 검수 발견: 이 두 정책은 R12 마이그레이션(Desktop\r12-migration.txt)으로만 적용돼
-- 저장소 sql/ 에는 없었음 → Supabase를 새로 구축하면 가입자 표·삭제 버튼이 전부 막힘.
-- 운영 DB에는 이미 적용돼 있으므로 재실행해도 무해(멱등).

drop policy if exists "admin read registrations" on public.registrations;
create policy "admin read registrations" on public.registrations
  for select to public using (auth.uid() is not null);

drop policy if exists "admin delete registrations" on public.registrations;
create policy "admin delete registrations" on public.registrations
  for delete to public using (auth.uid() is not null);
