-- 10. 기업용 만족도 설문 (기업현장교사·HRD담당자) — 응답 테이블
-- 문항 정의는 config.js COMPANY_SURVEYS (보기 순서가 답변 인덱스와 1:1 — 보기 순서를 바꾸면 기존 응답 해석이 틀어집니다).
-- 익명 insert만 허용, 응답 열람·삭제는 관리자(auth.uid())만. 재실행 안전(멱등).

create table if not exists public.company_survey_responses (
  id         uuid primary key default gen_random_uuid(),
  survey_key text not null check (survey_key in ('teacher', 'hrd')),
  round      text,                          -- 회차 (예: 2026 상반기)
  company    text,                          -- 문항1 기업명 (응답자가 확인·수정한 값)
  answers    jsonb not null,                -- {"q2":["0","5"],"q2_etc":"...","q6":"1",...} (보기 인덱스)
  comment    text,                          -- 마지막 주관식(바라는 점·건의)
  device_id  text,                          -- 1인1표용 기기 식별값(PII 아님)
  created_at timestamptz not null default now()
);

-- 무결성: answers는 객체여야 하고, 비정상 대용량 페이로드 차단
alter table public.company_survey_responses drop constraint if exists cosurvey_answers_shape;
alter table public.company_survey_responses add constraint cosurvey_answers_shape check (
  jsonb_typeof(answers) = 'object' and pg_column_size(answers) < 20000
);

-- 1인1표: 같은 기기가 같은 설문·회차에 중복 제출 불가
create unique index if not exists cosurvey_one_vote
  on public.company_survey_responses (survey_key, round, device_id);

alter table public.company_survey_responses enable row level security;

-- 익명: 제출만 가능 (읽기 전면 차단 = 응답 비공개)
drop policy if exists "anyone submit cosurvey" on public.company_survey_responses;
create policy "anyone submit cosurvey" on public.company_survey_responses
  for insert to public with check (true);

-- 관리자: 열람·삭제 (publishable 키 함정 회피 — to public + auth.uid() 패턴)
drop policy if exists "admin read cosurvey" on public.company_survey_responses;
create policy "admin read cosurvey" on public.company_survey_responses
  for select to public using (auth.uid() is not null);
drop policy if exists "admin delete cosurvey" on public.company_survey_responses;
create policy "admin delete cosurvey" on public.company_survey_responses
  for delete to public using (auth.uid() is not null);
