// =====================================================================
// sync-attendance — 노션 「OJT 월별 — 학생」 → attendance_monthly 반영
// admin.html 요약 탭 [노션 출석진도 반영] 버튼 전용.
//  · NOTION_TOKEN 은 함수 secret 에만 존재(클라이언트 미노출).
//  · 호출자 JWT 를 그대로 전달해 upsert 는 bulk_upsert_attendance RPC(sql/42)로 —
//    관리자 검사(admin_users)·center 서버 주입을 DB 계층에서 재사용한다.
//  · verify_jwt=false 배포: CORS preflight 통과용. 인증은 아래에서 직접 수행.
// =====================================================================
import { createClient } from 'npm:@supabase/supabase-js@2'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } })

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  if (req.method !== 'POST') return json({ error: 'method' }, 405)
  try {
    const auth = req.headers.get('Authorization') ?? ''
    if (!auth.startsWith('Bearer ')) return json({ error: 'not_authed' }, 401)

    // 1) 호출자 확인 — 로그인된 사용자여야 노션 조회를 시작(익명 반복 호출로 노션 API 낭비 방지)
    const supa = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: auth } },
    })
    const { data: { user } } = await supa.auth.getUser()
    if (!user) return json({ error: 'not_authed' }, 401)

    const notionToken = Deno.env.get('NOTION_TOKEN')
    if (!notionToken) return json({ error: 'no_notion_token' }, 500)
    const dbId = Deno.env.get('NOTION_ATTENDANCE_DB') ?? 'cd5b8cd3849f4a48a27b89deee1c6c27'

    // 2) 노션 학생월 DB 전체 조회 (페이지네이션). 제목 형식: "회사 · 이름 YYYY-MM"
    const rows: { name: string; month: string; planned: number | null; actual: number | null }[] = []
    let cursor: string | undefined
    do {
      const res = await fetch(`https://api.notion.com/v1/databases/${dbId}/query`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${notionToken}`,
          'Notion-Version': '2022-06-28',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ page_size: 100, ...(cursor ? { start_cursor: cursor } : {}) }),
      })
      if (!res.ok) return json({ error: 'notion_' + res.status, detail: (await res.text()).slice(0, 200) }, 502)
      const data = await res.json()
      for (const p of data.results ?? []) {
        const props = p.properties ?? {}
        const title = (props['제목']?.title ?? []).map((t: { plain_text: string }) => t.plain_text).join('')
        const month = props['월']?.date?.start?.slice(0, 7)
        const name = title.includes('·')
          ? title.split('·').pop()!.trim().replace(/\s+\d{4}-\d{2}\s*$/, '').trim()
          : ''
        if (!name || !month) continue
        rows.push({
          name, month,
          planned: props['예정 시수']?.number ?? null,
          actual: props['실적 시수']?.number ?? null,
        })
      }
      cursor = data.has_more ? data.next_cursor : undefined
    } while (cursor)
    if (!rows.length) return json({ error: 'no_rows' }, 422)

    // 3) upsert — 호출자 권한으로 RPC 호출(비관리자면 여기서 not_admin 거부)
    const { data: result, error } = await supa.rpc('bulk_upsert_attendance', { p_rows: rows })
    if (error) return json({ error: error.message }, 403)
    return json({ ok: true, notion_rows: rows.length, ...(result ?? {}) })
  } catch (e) {
    return json({ error: String(e).slice(0, 300) }, 500)
  }
})
