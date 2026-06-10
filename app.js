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

// PWA 서비스워커 등록 (홈 화면 추가 시 앱처럼 동작)
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('./sw.js').catch(() => {});
  });
}
