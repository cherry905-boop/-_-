// survey-ui.js — 설문 문항 렌더/수집 공용 모듈
// 문항 스키마(config.js COMPANY_SURVEYS와 동일): {key, type:'single'|'multi', label, options[], score[], etc}
// company-survey.html의 인라인 로직을 일반화(원본 페이지는 그대로 둠) — survey.html·admin.html에서 사용.
import { esc, setStatus } from './app.js';

// 문항들을 qEl 안에 렌더 (.q-block / .opt 마크업 — 페이지에 해당 스타일 필요)
export function renderQuestions(qEl, questions, opts = {}) {
  const start = opts.startIndex == null ? 1 : opts.startIndex;
  qEl.innerHTML = '';
  (questions || []).forEach((q, qi) => {
    const block = document.createElement('div'); block.className = 'q-block'; block.dataset.qkey = q.key;
    const type = q.type === 'multi' ? 'checkbox' : 'radio';
    let html = `<span class="field-label">${qi + start}. ${esc(q.label)}${q.type === 'multi' ? ' <span style="font-weight:500;color:var(--text-muted)">(중복 선택 가능)</span>' : ''} <span class="req">*</span></span>`;
    (q.options || []).forEach((opt, i) => {
      html += `<label class="opt"><input type="${type}" name="${q.key}" value="${i}"><span>${esc(opt)}</span></label>`;
    });
    if (q.etc) html += `<label class="opt"><input type="${type}" name="${q.key}" value="etc"><span>기타 (직접입력)</span></label><input type="text" class="etc-input" data-etc="${q.key}" placeholder="기타 내용을 입력해주세요" />`;
    block.innerHTML = html;
    qEl.appendChild(block);
    if (q.etc) block.addEventListener('change', () => {
      const on = block.querySelector(`input[name="${q.key}"][value=etc]`).checked;
      block.querySelector(`[data-etc="${q.key}"]`).style.display = on ? 'block' : 'none';
    });
  });
}

// 응답 수집 — 누락 시 해당 블록 표시·상태 메시지 후 null, 성공 시 answers(보기 인덱스 기반) 반환
export function collectAnswers(qEl, questions, statusEl) {
  const answers = {};
  for (const q of (questions || [])) {
    const block = qEl.querySelector(`.q-block[data-qkey="${q.key}"]`);
    if (!block) continue;
    block.classList.remove('miss');
    const sel = [...block.querySelectorAll(`input[name="${q.key}"]:checked`)].map(i => i.value);
    if (!sel.length) {
      block.classList.add('miss'); block.scrollIntoView({ behavior: 'smooth', block: 'center' });
      setStatus(statusEl, `'${(q.label || '').slice(0, 24)}' 문항에 응답해주세요.`, 'error');
      return null;
    }
    if (sel.includes('etc')) {
      const etcEl = block.querySelector(`[data-etc="${q.key}"]`);
      const etcVal = ((etcEl && etcEl.value) || '').trim();
      if (!etcVal) {
        block.classList.add('miss'); block.scrollIntoView({ behavior: 'smooth', block: 'center' });
        setStatus(statusEl, `'${(q.label || '').slice(0, 24)}' 문항의 '기타' 내용을 입력해주세요.`, 'error');
        return null;
      }
      answers[q.key + '_etc'] = etcVal.slice(0, 500);
    }
    answers[q.key] = q.type === 'multi' ? sel : sel[0];
  }
  return answers;
}

// 5점 척도 기본 보기 (관리자 빌더 '5점 척도' 자동 채움과 공유)
export const SCALE5 = { options: ['매우 만족', '만족', '보통', '불만족', '매우 불만족'], score: [5, 4, 3, 2, 1] };
