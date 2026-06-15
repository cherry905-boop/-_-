-- =====================================================================
-- 20_storage_isolation.sql  —  [P2] 자료실(library 버킷) 센터 격리
-- 적용 순서: 19 이후. 라이브 적용 + 동작 확인 필요(로컬에서 검증 불가).
--
-- 배경: 학생은 '비로그인(anon)'이고 클라이언트가 보낸 center 는 신뢰하지 않는다.
--   따라서 공개 버킷(getPublicUrl)으로는 교차센터 차단이 불가능하다(URL만 알면 누구나 열람).
--   진짜 격리 = (a) 버킷 비공개 + (b) 센터별 경로(<slug>/lib/...) + (c) 서버측 서명 URL.
--   (a),(b)는 여기서. (c) anon 서명기는 초대코드로 센터 자격을 검증하는 Edge Function 으로
--   P7에서 완성한다(SQL 함수로는 storage 서명 토큰을 만들 수 없음).
-- =====================================================================

-- ── 1) 버킷을 비공개로 (공개 URL 차단) ──
update storage.buckets set public = false where id = 'library';

-- ── 2) 기존 정책 정리(있으면) ──
drop policy if exists "library admin all" on storage.objects;
drop policy if exists "library public read" on storage.objects;
drop policy if exists "library admin manage own center" on storage.objects;
-- ⚠️ sql/09 의 센터 무스코프 쓰기 정책(= bucket_id='library' AND auth.uid() IS NOT NULL)도 반드시 제거.
--    안 지우면 permissive OR 로 '로그인한 어떤 관리자든' 타 센터 폴더(<other>/lib/..)에 업로드·수정·삭제 가능
--    → 아래 '자기 센터 폴더만' 정책이 무효화된다(쓰기 격리 실패).
drop policy if exists "library admin insert" on storage.objects;
drop policy if exists "library admin update" on storage.objects;
drop policy if exists "library admin delete" on storage.objects;

-- ── 3) 관리자: 자기 센터 폴더(<slug>/...)만 업로드·수정·삭제 ──
--   객체 경로 첫 폴더 = 센터 슬러그. admin_users 의 센터 슬러그와 일치해야 함.
create policy "library admin manage own center" on storage.objects
  for all to authenticated
  using (
    bucket_id = 'library'
    and (
      public.is_super_admin()
      or (storage.foldername(name))[1] = (
        select c.slug from public.centers c where c.id = public.current_admin_center()
      )
    )
  )
  with check (
    bucket_id = 'library'
    and (
      public.is_super_admin()
      or (storage.foldername(name))[1] = (
        select c.slug from public.centers c where c.id = public.current_admin_center()
      )
    )
  );

-- ── 4) 학생(anon) 읽기: 직접 SELECT 정책을 주지 않는다 ──
--   anon 에게 library 객체 SELECT 를 열면 경로만 알면 교차센터 열람이 되므로 금지.
--   학생용 다운로드는 P7 의 Edge Function 서명기(초대코드/토큰으로 센터 자격 확인 후
--   createSignedUrl 발급)를 통해서만. 그 전까지 학생 자료 열람은 기존 공개 URL 행에 한해
--   동작하며(과도기), 신규 업로드는 비공개이므로 서명기 배포 후 노출된다.
--   (library.html 의 렌더를 '저장된 path → 서명 URL' 로 바꾸는 작업은 P7 서명기와 함께.)
