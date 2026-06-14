-- 09. 관리자·가입 UX 확장 — 발송기록 삭제 + 자료 파일 업로드(Storage) + 코드 단독 가입 + 달력 범위 RPC
-- ※ 02(코드)·07(관리도구) 실행 후 적용하세요. 재실행해도 안전(멱등).
-- ※ 이 프로젝트 규칙: 정책은 to public + auth.uid() 조건(publishable 키에서 to authenticated가 안 먹는 전례),
--    함수는 오버로드 금지(PostgREST 모호성) → 새 이름으로 추가.

-- ── A. 발송기록(push_logs) 관리자 삭제 ──
do $$ begin
  if to_regclass('public.push_logs') is not null then
    drop policy if exists "admin delete" on public.push_logs;
    create policy "admin delete" on public.push_logs
      for delete to public using (auth.uid() is not null);
  end if;
end $$;

-- ── B. 자료실 파일 업로드용 Storage 버킷 'library' (비공개 / 관리자만 쓰기) ──
-- ⚠️ 0단계 하드닝(2026-06): 과거엔 public=true + anon 공개읽기였으나, 이는 20_storage_isolation
--    (비공개 전환)을 매 실행 덮어써 공개 URL 을 되살렸다(절대규칙8 위반). → 비공개로 고정하고
--    공개읽기 정책을 제거한다. 센터별 경로 스코프 정책은 20 에서, 학생 다운로드는 서명기(sign-library)로.
-- SQL Editor(postgres 롤)에서 실행되므로 buckets upsert는 안전. 클라이언트에서 createBucket 호출 금지.
insert into storage.buckets (id, name, public) values ('library', 'library', false)
  on conflict (id) do nothing;

-- 과거 공개읽기 정책이 남아있으면 제거(멱등). 재생성하지 않는다.
drop policy if exists "library public read" on storage.objects;
drop policy if exists "library admin insert" on storage.objects;
create policy "library admin insert" on storage.objects
  for insert to public with check (bucket_id = 'library' and auth.uid() is not null);
drop policy if exists "library admin update" on storage.objects;
create policy "library admin update" on storage.objects
  for update to public using (bucket_id = 'library' and auth.uid() is not null);
drop policy if exists "library admin delete" on storage.objects;
create policy "library admin delete" on storage.objects
  for delete to public using (bucket_id = 'library' and auth.uid() is not null);

-- ── C. 코드 단독 검증 (이름 입력 없이 가입/복원) ──
-- 트레이드오프: 코드가 유출되면 '이름 대조'라는 2차 장벽 없이 명단 정보(이름·전화·직무·기업·담당자)가 반환된다.
-- 완화: 코드는 합격 통보에 개별 동봉(1:1 전달), 8자·31문자(≈5×10^11 조합), IP당 10분 30회 rate-limit
-- (기존 'code:' 버킷 공유 = 기존+솔로 합산 30회), 유출 의심 시 가입자표에서 재발급하면 즉시 무효화.
create or replace function public.verify_code_solo(p_code text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  sc record;
  ip text;
begin
  ip := coalesce(current_setting('request.headers', true)::jsonb ->> 'x-forwarded-for', 'unknown');
  perform check_verify_rate('code:' || ip);

  select * into sc from student_codes
   where code = upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'))
     and active;
  if not found then
    return jsonb_build_object('matched', false, 'reason', 'code');
  end if;
  -- 명단 검증 RPC 재사용 + 이름·정규 휴대폰을 함께 반환(클라이언트 자동 채움용)
  return (select verify_student(sc.name, sc.phone))::jsonb
         || jsonb_build_object('name', sc.name, 'phone', sc.phone);
end $$;
grant execute on function public.verify_code_solo(text) to anon, authenticated;

create or replace function public.verify_company_code_solo(p_code text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c record;
  ip text;
begin
  ip := coalesce(current_setting('request.headers', true)::jsonb ->> 'x-forwarded-for', 'unknown');
  perform check_verify_rate('cocode:' || ip);

  select * into c from company_codes
   where code = upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'))
     and active;
  if not found then
    return jsonb_build_object('ok', false);
  end if;
  return jsonb_build_object('ok', true, 'company', c.company);
end $$;
grant execute on function public.verify_company_code_solo(text) to anon, authenticated;

-- ── D. 달력 그리드용 — 명단 지정 일정을 과거 포함 범위로 (07의 my_targeted_calendar는 오늘 이후 고정) ──
-- 무제한 과거 조회 방지: 92일 전까지만.
create or replace function public.my_targeted_calendar_from(p_token text, p_from date)
returns setof public.calendar_events
language plpgsql security definer set search_path = public, extensions as $$
declare h text;
begin
  if p_token is null or length(p_token) < 8 then return; end if;
  h := substring(encode(digest(p_token, 'sha256'), 'hex') for 16);
  return query
    select * from calendar_events
    where job_key like 'tokv:%'
      and event_date >= greatest(coalesce(p_from, current_date), (current_date - interval '92 days')::date)
      and (substring(job_key from 6))::jsonb -> 'tok' ? h;
end $$;
grant execute on function public.my_targeted_calendar_from(text, date) to anon, authenticated;
