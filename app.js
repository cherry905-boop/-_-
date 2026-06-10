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
