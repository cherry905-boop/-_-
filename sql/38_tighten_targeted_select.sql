-- =====================================================================
-- 38_tighten_targeted_select.sql
-- [데이터 원장 → 화면 분배] 타게팅 공지의 anon 직접 SELECT 노출 차단 (notices만)
--   설계: docs/READ_MODEL.md §5 Tier1 / §6 종착상태.
--   배경: sql/36 은 anon SELECT 를 published+center 까지만 조여, 타게팅 공지의 body/target_value 가
--         anon 에게 통째로 내려가고 브라우저(noticeMatches)가 거를 뿐이었다(실측 노출).
--   조치: anon 직접 SELECT 는 target_scope='all' 공지만. 타게팅 공지는 public_notices(RPC, sql/37)로만.
--
-- ⚠️ 적용 순서(엄수): sql/37 적용 + 프론트(notice.html·app.js)가 public_notices 사용 확인 + mju 회귀 0 검증 → 그 다음 이 파일.
--    역전 시: RPC 부재 폴백(직조회)이 'all' 공지만 보게 되어 타게팅 공지가 사라진다.
--
-- 후속(이 파일 범위 밖, docs/READ_MODEL.md §7 2~3단계): surveys·polls(target_scope='all') / library·calendar(job_key not like 'tokv:%').
-- =====================================================================

do $$
begin
  if to_regclass('public.notices') is null then
    return;
  end if;
  -- sql/36 이 만든 공개읽기 정책을 target_scope='all' 로 축소(멱등 재정의).
  drop policy if exists notices_public_center_read on public.notices;
  create policy notices_public_center_read on public.notices
    for select to public
    using (
      published = true
      and center_id = public.request_center_id()
      and coalesce(target_scope, 'all') = 'all'
    );
end $$;
