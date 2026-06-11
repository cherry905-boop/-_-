/* =====================================================================
 *  app.js  —  여러 페이지가 함께 쓰는 공용 도우미 (보통 고칠 일 없음)
 *  ES 모듈입니다. 각 HTML에서 <script type="module"> 로 불러 씁니다.
 * ===================================================================== */
import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

const cfg = window.APP_CONFIG || {};

// Supabase 클라이언트 (config.js 값이 비어 있으면 null)
export const supabase =
  (cfg.SUPABASE_URL && cfg.SUPABASE_URL.startsWith('http'))
    ? createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY)
    : null;

export function configReady() {
  return !!supabase;
}

// URL 쿼리 파라미터 읽기 (예: ?src=2026spring)
export function getQueryParam(name) {
  return new URLSearchParams(location.search).get(name) || '';
}

// 홈 화면에 추가(설치)된 상태로 실행 중인가?
export function isStandalone() {
  return window.matchMedia('(display-mode: standalone)').matches
      || window.navigator.standalone === true; // iOS
}

// 플랫폼 판별
export function getPlatform() {
  const ua = navigator.userAgent || '';
  if (/iPad|iPhone|iPod/.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)) return 'ios';
  if (/Android/.test(ua)) return 'android';
  return 'other';
}

// 카카오톡/인스타 등 "인앱 브라우저" 감지 (여기서는 푸시·홈화면추가가 막힘)
export function isInAppBrowser() {
  const ua = (navigator.userAgent || '').toLowerCase();
  return /kakaotalk|instagram|fban|fbav|naver|line\/|daumapps|everytimeapp|band/.test(ua);
}

// 학과 라벨 찾기
export function deptLabel(key) {
  const d = (window.DEPARTMENTS || []).find(x => x.key === key);
  return d ? d.label : key;
}

// 간단한 토스트/상태 메시지
export function setStatus(el, msg, type = 'info') {
  if (!el) return;
  el.textContent = msg;
  el.className = 'status ' + type; // info / ok / error
}

// HTML 이스케이프 (각 페이지에 흩어져 있던 esc()의 공용 버전)
export function esc(s) {
  const e = document.createElement('div'); e.textContent = s || ''; return e.innerHTML;
}

// 이 기기의 가입 프로필 (없으면 {})
export function getProfile() {
  try { return JSON.parse(localStorage.getItem('ilhak_profile') || '{}') || {}; } catch (_) { return {}; }
}

// 회사명 표기차이 흡수 — 공지/자료/일정 타게팅 매칭 공용
export const normCo = (s) => (s || '').replace(/㈜|\(주\)|주식회사|\s/g, '');
// withManagers: 담당자 세그먼트 매칭은 공지에서만 사용(자료/일정의 기존 동작 보존)
export function matchSel(sel, profile, withManagers = false) {
  if (!sel) return false;
  if (sel.targets && sel.targets.includes(profile.target_type)) return true;
  if (sel.jobs && profile.job_key && sel.jobs.includes(profile.job_key)) return true;
  if (sel.companies && profile.company && sel.companies.map(normCo).includes(normCo(profile.company))) return true;
  if (sel.types && profile.type1 && sel.types.includes(profile.type1)) return true;
  if (withManagers && sel.managers && sel.managers.length && profile.manager && sel.managers.includes(profile.manager.trim())) return true;
  return false;
}
// 공지(notices) 행이 이 기기에 보여야 하는가 — notice.html과 배지 카운트가 같은 규칙을 공유
export function noticeMatches(n, profile) {
  switch (n.target_scope) {
    case 'all':     return true;
    case 'job':     return profile.job_key === n.target_value;
    case 'company': return normCo(profile.company) === normCo(n.target_value);
    case 'target':  return profile.target_type === n.target_value;
    case 'type':    return profile.type1 === n.target_value;
    case 'custom':  { try { return matchSel(JSON.parse(n.target_value || '{}'), profile, true); } catch (_) { return false; } }
    default:        return false;
  }
}

// 휴대폰 입력 자동 하이픈 (010-1234-5678) — 중간 편집 시에도 커서 위치 보존
export function attachPhoneFormat(el) {
  if (!el) return;
  el.addEventListener('input', () => {
    const before = el.value;
    const pos = el.selectionStart == null ? before.length : el.selectionStart;
    const digitsBeforeCaret = before.slice(0, pos).replace(/\D/g, '').length;
    const d = before.replace(/\D/g, '').slice(0, 11);
    let v = d;
    if (d.length > 7)      v = d.slice(0, 3) + '-' + d.slice(3, 7) + '-' + d.slice(7);
    else if (d.length > 3) v = d.slice(0, 3) + '-' + d.slice(3);
    if (before === v) return;
    el.value = v;
    // 커서 복원: 재포맷 전 커서 앞에 있던 '숫자 개수'가 같아지는 지점으로
    let np = 0, cnt = 0;
    while (np < v.length && cnt < digitsBeforeCaret) { if (/\d/.test(v[np])) cnt++; np++; }
    try { el.setSelectionRange(np, np); } catch (_) {}
  });
}

// 목록 로딩 스켈레톤 — 데이터 도착 전 자리표시
export function skeletonList(el, n = 3) {
  if (!el) return;
  el.setAttribute('aria-busy', 'true');
  el.innerHTML = Array.from({ length: n }, () =>
    '<div class="skel-card" style="margin-bottom:14px"><div class="skel skel-line w40"></div>' +
    '<div class="skel skel-line w80"></div><div class="skel skel-line w60"></div></div>').join('');
}
export function clearSkeleton(el) {
  if (!el) return;
  el.removeAttribute('aria-busy');
  el.innerHTML = '';
}

/* ── 공지 읽음 추적 (이 기기 localStorage — 서버 변경 없음) ── */
const READ_KEY = 'ilhak_read_notices';
export function getReadSet() {
  try { return new Set(JSON.parse(localStorage.getItem(READ_KEY) || '[]')); } catch (_) { return new Set(); }
}
export function markNoticesRead(ids) {
  try {
    const s = getReadSet();
    ids.forEach(id => s.add(id));
    localStorage.setItem(READ_KEY, JSON.stringify([...s].slice(-800))); // 무한 증식 방지
  } catch (_) {}
}
// 내 대상 공지 중 아직 안 읽은 개수 (최근 100건 기준)
export async function unreadNoticeCount() {
  if (!supabase) return 0;
  const profile = getProfile();
  if (!profile.name) return 0;
  try {
    const { data, error } = await supabase.from('notices')
      .select('id,target_scope,target_value')
      .eq('published', true).order('created_at', { ascending: false }).limit(100);
    if (error || !data) return 0;
    const read = getReadSet();
    return data.filter(n => noticeMatches(n, profile) && !read.has(n.id)).length;
  } catch (_) { return 0; }
}
// 탭바 '공지' 탭과 홈 '공지사항' 타일에 미확인 배지 표시
export async function updateUnreadBadges() {
  const cnt = await unreadNoticeCount();
  document.querySelectorAll('[data-unread-badge]').forEach(el => { el.remove(); });
  if (!cnt) return;
  const label = cnt > 99 ? '99+' : String(cnt);
  const tab = document.querySelector('.tabbar a[href="./notice.html"]');
  if (tab) {
    const b = document.createElement('span');
    b.className = 'count-badge'; b.dataset.unreadBadge = '1'; b.textContent = label;
    b.setAttribute('aria-label', `안 읽은 공지 ${cnt}건`);
    tab.appendChild(b);
  }
  const tile = document.querySelector('.menu-tile[href="./notice.html"]');
  if (tile) {
    const b = document.createElement('span');
    b.className = 'count-badge mbadge'; b.dataset.unreadBadge = '1'; b.textContent = label;
    b.setAttribute('aria-label', `안 읽은 공지 ${cnt}건`);
    tile.appendChild(b);
  }
}

// Supabase/네트워크 오류를 사용자 언어로 변환 (영문 원문은 콘솔로만)
export function friendlyError(error) {
  const m = (error && (error.message || error.msg)) || String(error || '');
  try { console.error(error); } catch (_) {}
  if (/Failed to fetch|NetworkError|network|timeout|타임아웃/i.test(m)) return '인터넷 연결을 확인한 뒤 다시 시도해주세요.';
  if (/JWT|expired|로그인|session|invalid token/i.test(m)) return '로그인이 만료됐어요. 다시 로그인해주세요.';
  if (/row-level security|permission denied|42501/i.test(m)) return '일시적인 문제가 있어요. 잠시 후 다시 시도하거나 담당자에게 문의해주세요.';
  if (/duplicate|23505|already exists/i.test(m)) return '이미 처리된 내용이에요.';
  return '문제가 발생했어요. 잠시 후 다시 시도해주세요.';
}

// PWA 서비스워커 등록 (홈 화면 추가 시 앱처럼 동작)
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('./sw.js').catch(() => {});
  });
}

// 하단 탭 네비게이션 — .ph-body 가 있는 학생 페이지에만 주입(관리자 콘솔 등은 제외)
(function injectTabbar() {
  try {
    if (!document.querySelector('.ph-body')) return;
    if (document.querySelector('.tabbar')) return;
    const page = location.pathname.split('/').pop() || 'index.html';
    const items = [
      ['index.html', 'home', '홈'],
      ['notice.html', 'megaphone', '공지'],
      ['library.html', 'folder', '자료'],
      ['calendar.html', 'calendar-days', '일정'],
      ['consult.html', 'message-circle', '상담'],
    ];
    const nav = document.createElement('nav');
    nav.className = 'tabbar';
    nav.setAttribute('aria-label', '주요 메뉴');
    nav.innerHTML = items.map(([href, ic, label]) =>
      `<a href="./${href}"${page === href ? ' class="on" aria-current="page"' : ''}><i data-lucide="${ic}"></i>${label}</a>`).join('');
    document.body.appendChild(nav);
    document.body.classList.add('has-tabbar');
    if (window.lucide && window.lucide.createIcons) window.lucide.createIcons();
    // 가입된 기기면 '공지' 탭에 미확인 배지 (공지 페이지 자신은 읽음 처리 후 직접 갱신)
    if (page !== 'notice.html') updateUnreadBadges();
  } catch (_) {}
})();

// 접근성 — 상태 메시지를 스크린리더가 자동 낭독하도록
(function a11yStatus() {
  try {
    document.querySelectorAll('.status').forEach(el => {
      if (!el.hasAttribute('role')) { el.setAttribute('role', 'status'); el.setAttribute('aria-live', 'polite'); }
    });
  } catch (_) {}
})();
