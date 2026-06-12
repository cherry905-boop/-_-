# Supabase 마이그레이션 (지원자·초대코드·공고·트래커·QnA)

Supabase 대시보드 → SQL Editor 에서 **번호 순서대로** 실행하세요.
실행 전까지 앱은 기존 방식으로 동작합니다(신규 기능은 자동으로 숨겨지거나 기존 가입 방식으로 폴백).

| 파일 | 내용 | 실행 후 켜지는 기능 |
|---|---|---|
| 01_applicant.sql | registrations에 지원자 허용 + 관심직무·학과 컬럼 | 지원자 가입 |
| 02_codes.sql | 학생/기업 초대코드 + verify_by_code + 시도 제한 | 코드 가입 (관리자 가입자표에서 코드 발급) |
| 03_recruit.sql | 채용공고·선배사례 테이블 | 모집기업 열람·사례 페이지, 관리자 공고/사례 등록 |
| 04_stages.sql | 기업 진행단계 테이블 + 조회 RPC | 기업담당자 홈 진행단계 카드, 관리자 기업 탭 |
| 05_qna.sql | QnA 사례 테이블 | QnA 페이지, 상담 '사례로 공개' |
| 06_qna_seed.sql | QnA 초기 시드 | 자주 묻는 질문 초기 콘텐츠 |
| 07_admin_tools.sql | 관리자 도구 보강 | 관리자 명단·콘텐츠 관리 |
| 08_cases_seed.sql | 선배사례 16건 시드(전체교체 방식) | 사례 페이지 — 관리자 직접등록 후 재실행 금지 |
| 09_admin_extras.sql | 자료 파일업로드·발송기록 삭제·코드만 가입 RPC | 관리자 업로드/기록 삭제, 코드 단독 가입 |
| 10_company_survey.sql | 기업용 만족도 응답 테이블 | 기업현장교사·HRD담당자 만족도 |
| 11_company_faq_seed.sql | 기업담당자용 FAQ 시드 | FAQ 페이지 기업 답변 |
| 12_company_contacts.sql | 노션 HRD담당자 명단 미러(관리자만 조회) | 가입자 탭 기업담당자 가입/미가입 체크 — Apps Script 동기화 코드도 갱신 필요 |
| 13_code_only_signup.sql | verify_company_code_solo가 HRD담당자 이름·연락처도 반환 | 초대코드 전용 가입(기업 코드만으로 담당자 정보 자동 채움) |

주의사항
- 02의 `verify_by_code`는 기존 `verify_student(name, phone)` RPC를 내부 호출합니다.
  verify_student의 반환 타입이 json이 아니어서 오류가 나면 함수 끝의 `::jsonb` 캐스팅을 조정하세요.
- 푸시 발송 워커(5분 트리거)가 `targets:['applicant']` 세그먼트를 처리하는지 확인하세요.
  워커가 기존 matchSel(union) 로직을 그대로 쓴다면 추가 작업이 없고,
  target_type 화이트리스트가 있다면 'applicant'를 추가해야 지원자 푸시가 나갑니다.
- 실행 후 admin.html 가입자 탭에서 학생 선택 → "코드 발급"으로 합격자 코드를 만들고,
  기업 탭에서 기업별 코드를 발급해 지정완료 메일에 동봉하세요.
