-- 07. 관리자 운영 도구 — 콘텐츠 삭제 + '명단 지정' 발송(서버측 접근통제)
-- ※ R15(notice_recipients)·05(qna 등)보다 나중에 실행하세요.

create extension if not exists pgcrypto;

-- ── ① 다 쓴 콘텐츠 삭제 — 관리자(authenticated)에게 delete 권한 ──
do $$
declare t text;
begin
  foreach t in array array['notices','notice_recipients','library','calendar_events','board_posts','consultations','consultation_messages'] loop
    if to_regclass('public.' || t) is not null then
      execute format('drop policy if exists "admin delete" on public.%I', t);
      execute format('create policy "admin delete" on public.%I for delete to authenticated using (true)', t);
    end if;
  end loop;
end $$;

-- ── ② 명단 지정 발송 — 자료·일정을 '선택한 사람'에게만 (서버측 보호) ──
-- 설계: 명단 지정 행은 job_key = 'tokv:'+JSON({tok:[해시…]}) 로 저장.
--   · anon SELECT 정책에서 'tokv:%' 행을 전면 차단 → 누구나 키로 조회해도 안 보임.
--   · 대상 학생만 my_targeted_* RPC(토큰 검증)로 자기 행을 받아온다.
-- 해시 = 학생 기기 토큰(서명토큰, 비밀)의 sha256 앞 16자. 관리자는 이름·번호로 해시를 만들고(admin_recipient_hashes),
-- 학생은 자기 토큰을 RPC로 보내 서버가 같은 방식으로 해시 → 일치 비교(양쪽 모두 pgcrypto, 인코딩 일치 보장).

-- anon 공개 읽기 정책 재정의 — 명단 지정(tokv:) 행 차단
do $$
declare pol record;
begin
  -- library: 발행됨 + 명단지정 아닌 것만 anon 공개
  for pol in select policyname from pg_policies
    where schemaname='public' and tablename='library' and cmd='SELECT'
      and (roles @> array['anon']::name[] or roles @> array['public']::name[])
  loop execute format('drop policy %I on public.library', pol.policyname); end loop;
  create policy "anon read public library" on public.library for select to anon
    using (published = true and (job_key is null or job_key not like 'tokv:%'));

  -- calendar_events: 명단지정 아닌 것만 anon 공개
  for pol in select policyname from pg_policies
    where schemaname='public' and tablename='calendar_events' and cmd='SELECT'
      and (roles @> array['anon']::name[] or roles @> array['public']::name[])
  loop execute format('drop policy %I on public.calendar_events', pol.policyname); end loop;
  create policy "anon read public events" on public.calendar_events for select to anon
    using (job_key is null or job_key not like 'tokv:%');
end $$;

-- 관리자: 선택 인원(이름·번호)을 명단 검증해 토큰 해시 배열로 — 인원별 결과 포함
create or replace function public.admin_recipient_hashes(p_people jsonb)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  p jsonb; v jsonb; tok text;
  hashes text[] := '{}';
  missed jsonb := '[]'::jsonb;
begin
  if auth.role() is distinct from 'authenticated' then raise exception 'forbidden'; end if;
  for p in select * from jsonb_array_elements(coalesce(p_people, '[]'::jsonb)) loop
    begin
      v := (select verify_student(p->>'name', p->>'phone'))::jsonb;
      tok := v->>'token';
      if (v->>'matched')::boolean and tok is not null then
        hashes := array_append(hashes, substring(encode(digest(tok, 'sha256'), 'hex') for 16));
      else
        missed := missed || jsonb_build_array(jsonb_build_object('name', p->>'name', 'reason', 'no_token'));
      end if;
    exception when others then
      missed := missed || jsonb_build_array(jsonb_build_object('name', p->>'name', 'reason', 'error'));
    end;
  end loop;
  return jsonb_build_object('hashes', to_jsonb(hashes), 'missed', missed);
end $$;
revoke execute on function public.admin_recipient_hashes(jsonb) from public, anon;
grant execute on function public.admin_recipient_hashes(jsonb) to authenticated;

-- 학생: 내 토큰으로 '나에게 지정된 자료/일정'만 받기 (anon 공개 차단을 우회하는 유일 경로)
create or replace function public.my_targeted_library(p_token text)
returns setof public.library
language plpgsql security definer set search_path = public, extensions as $$
declare h text;
begin
  if p_token is null or length(p_token) < 8 then return; end if;
  h := substring(encode(digest(p_token, 'sha256'), 'hex') for 16);
  return query
    select * from library
    where published = true and job_key like 'tokv:%'
      and (substring(job_key from 6))::jsonb -> 'tok' ? h;
end $$;
grant execute on function public.my_targeted_library(text) to anon, authenticated;

create or replace function public.my_targeted_calendar(p_token text)
returns setof public.calendar_events
language plpgsql security definer set search_path = public, extensions as $$
declare h text;
begin
  if p_token is null or length(p_token) < 8 then return; end if;
  h := substring(encode(digest(p_token, 'sha256'), 'hex') for 16);
  return query
    select * from calendar_events
    where job_key like 'tokv:%'
      and event_date >= current_date
      and (substring(job_key from 6))::jsonb -> 'tok' ? h;
end $$;
grant execute on function public.my_targeted_calendar(text) to anon, authenticated;
