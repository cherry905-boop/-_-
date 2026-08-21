// =====================================================================
// sync-attendance — 노션 「OJT 월별 — 학생」 → attendance_monthly 반영
//
// 호출 경로 2개:
//  ① 관리자 버튼 (admin.html 요약 탭) — 호출자 JWT 를 그대로 전달해
//     bulk_upsert_attendance RPC(sql/42)가 admin_users 검사·center 주입을 수행.
//  ② pg_cron 자동 동기화 (sql/53) — 헤더 x-cron-key 를 verify_cron_key RPC 로 검증.
//     비콘 알림(09:00)보다 먼저(08:45) 돌려서, 푸시 본문의 시수가 하루 이틀
//     묵은 값으로 나가던 문제를 없앤다. 이 경로는 center 를 slug 로 직접 지정한다.
//
//  · NOTION_TOKEN 은 함수 secret 에만 존재(클라이언트 미노출).
//  · verify_jwt=false 배포: CORS preflight 통과 + cron 호출용. 인증은 아래에서 직접 수행.
// =====================================================================
import { createClient } from 'npm:@supabase/supabase-js@2'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-cron-key',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } })

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  if (req.method !== 'POST') return json({ error: 'method' }, 405)
  try {
    const url = Deno.env.get('SUPABASE_URL')!
    const cronKey = req.headers.get('x-cron-key') ?? ''

    // 1) 인증 — cron 경로 우선, 없으면 관리자 JWT 경로
    let supa           // 노션 결과를 upsert 할 클라이언트
    let center: string | null = null   // cron 경로에서만 명시적으로 넘긴다

    if (cronKey) {
      const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } })
      const { data: ok } = await admin.rpc('verify_cron_key', { p_key: cronKey })
      if (ok !== true) return json({ error: 'bad_cron_key' }, 401)

      let slug = 'mju'
      try { slug = (await req.json())?.slug || 'mju' } catch (_) { /* 본문 없음 */ }
      const { data: c } = await admin.from('centers').select('id').eq('slug', slug).maybeSingle()
      if (!c?.id) return json({ error: 'unknown_center' }, 404)
      center = c.id
      supa = admin
    } else {
      const auth = req.headers.get('Authorization') ?? ''
      if (!auth.startsWith('Bearer ')) return json({ error: 'not_authed' }, 401)
      // 로그인된 사용자여야 노션 조회를 시작(익명 반복 호출로 노션 API 낭비 방지)
      supa = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: auth } } })
      const { data: { user } } = await supa.auth.getUser()
      if (!user) return json({ error: 'not_authed' }, 401)
    }

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

    // 3) upsert — 관리자 경로는 호출자 권한으로(비관리자면 not_admin 거부),
    //    cron 경로는 service_role + center 명시(sql/53).
    const { data: result, error } = await supa.rpc('bulk_upsert_attendance',
      center ? { p_rows: rows, p_center: center } : { p_rows: rows })
    if (error) return json({ error: error.message }, 403)
    return json({ ok: true, via: cronKey ? 'cron' : 'admin', notion_rows: rows.length, ...(result ?? {}) })
  } catch (e) {
    return json({ error: String(e).slice(0, 300) }, 500)
  }
})
