-- =====================================================================
-- 22_baseline_hardening.sql  —  [멀티테넌트 0단계: 토대 하드닝]
-- 멱등(idempotent). 적용 순서: 19·21 이후(centers·admin_users·헬퍼·center_id·센터스코프 RLS 존재 가정).
--
-- 목적: 멀티테넌트 단계(23~)를 쌓기 전에, 레포 sql/ 에 누락돼 있던 보안 토대를 '박제'한다.
--   registrations 의 anon INSERT 정책(=학생/지원자/기업 가입의 핵심 경로)이 레포에 없고
--   운영 대시보드에만 존재했다 → 가입 폴백 경로가 버전관리 밖이라 재구축/스테이징에서 깨질 수 있었다.
--
-- ⚠️ 남은 일(사용자): registrations 의 CREATE TABLE(컬럼 정의)·기존 정책 원본은 여전히 운영
--    대시보드에만 있다. 완전한 재구축 안전을 위해 운영 DB에서 스키마 덤프로 별도 캡처가 필요하다.
--    (이 파일의 정책은 permissive 라 운영의 기존 정책과 OR 로 합쳐져 무해하며, 기존 동작을 보존한다.)
-- =====================================================================

-- ── registrations: RLS 활성 + anon 가입(INSERT) 정책 박제 ──
-- · permissive 정책 → 운영에선 기존 anon insert 정책과 OR 로 합쳐져 무해(회귀 0), 재구축에선 가입 보장.
-- · SELECT 정책은 부여하지 않는다 → anon PII 차단 유지(rls-check MUST_BE_BLOCKED).
-- · 23단계: 가입을 register_with_code RPC(서버가 center_id 도출)로 전환.
-- · 28단계(NOT NULL 승격): with check 를 (center_id is not null) 로 조인다.
do $reg$
begin
  if to_regclass('public.registrations') is not null then
    execute 'alter table public.registrations enable row level security';
    drop policy if exists "registrations anon insert" on public.registrations;
    create policy "registrations anon insert" on public.registrations
      for insert to public with check (true);
  end if;
end
$reg$;
