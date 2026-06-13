// supabase/functions/sign-library/index.ts
// [P2/P7] 학생(anon)용 자료 다운로드 서명기.
//
// 왜 필요한가: 학생은 비로그인(anon)이고 클라이언트가 보낸 center 는 신뢰하지 않는다.
//   library 버킷을 비공개로 바꾼 뒤(sql/20), 학생이 파일을 열려면 '서버가 센터 자격을
//   검증한 뒤' 짧은 수명의 서명 URL 을 발급해야 교차센터 열람을 막을 수 있다.
//
// 자격 증거: 가입 시 발급되는 push_tokens.token (행에 center_id 보유) 또는 초대코드.
//   요청한 자료(library 행)의 center_id 와 일치할 때만 서명 URL 발급.
//
// ⚠️ 배포 전 로컬 테스트: `supabase functions serve sign-library --env-file .env.local`
//   환경변수 SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY 필요(서비스 키는 서버 전용 — 절대 클라/레포 금지).
//   library 행에 객체 경로가 필요하다. admin.html 신규 업로드는 `<center>/lib/...` 경로를
//   저장 url 에 포함하므로 아래에서 추출한다(향후 `path` 컬럼을 두면 더 깔끔).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "content-type": "application/json" } });

// 저장된 url(또는 path)에서 버킷 내 객체 경로(<center>/lib/...)만 추출
function objectPath(urlOrPath: string): string | null {
  if (!urlOrPath) return null;
  const m = urlOrPath.match(/\/library\/(.+)$/);          // 공개/비공개 URL 모두 매칭
  const p = m ? m[1] : urlOrPath;                          // 이미 path 면 그대로
  try { return decodeURIComponent(p.split("?")[0]); } catch { return p.split("?")[0]; }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  let payload: { rowId?: number; token?: string; code?: string };
  try { payload = await req.json(); } catch { return json({ error: "bad json" }, 400); }
  const { rowId, token, code } = payload || {};
  if (!rowId || (!token && !code)) return json({ error: "rowId + token/code required" }, 400);

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,        // 서버 전용 키
    { auth: { persistSession: false } },
  );

  // 1) 요청한 자료 행 → center_id + 경로
  const { data: row, error: rowErr } = await admin
    .from("library").select("id, url, center_id, published").eq("id", rowId).maybeSingle();
  if (rowErr) return json({ error: "lookup failed" }, 500);
  if (!row || row.published === false) return json({ error: "not found" }, 404);
  const path = objectPath(row.url || "");
  if (!path) return json({ error: "not a stored file" }, 422);

  // 2) 요청자의 센터 자격 검증 — 토큰/코드의 center_id 가 자료의 center_id 와 일치해야 함
  let entitledCenter: string | null = null;
  if (token) {
    const { data: t } = await admin.from("push_tokens").select("center_id").eq("token", token).maybeSingle();
    entitledCenter = t?.center_id ?? null;
  }
  if (!entitledCenter && code) {
    const { data: sc } = await admin.from("student_codes").select("center_id").eq("code", code).maybeSingle();
    entitledCenter = sc?.center_id ?? null;
  }
  if (!entitledCenter || entitledCenter !== row.center_id) return json({ error: "forbidden" }, 403);

  // 3) 자격 확인됨 → 60초 서명 URL 발급
  const { data: signed, error: signErr } = await admin.storage.from("library").createSignedUrl(path, 60);
  if (signErr || !signed) return json({ error: "sign failed" }, 500);
  return json({ url: signed.signedUrl });
});
