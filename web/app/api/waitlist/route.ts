import { parseSignup } from '@/lib/waitlist'

// Signups go to a Supabase table through its REST API with the service key, which
// never leaves the server. The table has RLS on and no policies, so the public
// anon key cannot read the list of who signed up.
export async function POST(req: Request) {
  let body: unknown
  try {
    body = await req.json()
  } catch {
    return Response.json({ error: 'Expected a form.' }, { status: 400 })
  }
  const parsed = parseSignup(body)
  if (!parsed.ok) return Response.json({ error: parsed.error }, { status: 400 })

  const url = process.env.SUPABASE_URL
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY
  if (!url || !key) {
    // Say so rather than pretend: a signup that looks saved and isn't is the worst outcome.
    return Response.json({ error: 'The waitlist isn’t open yet. Try again soon.' }, { status: 503 })
  }

  const res = await fetch(`${url}/rest/v1/waitlist`, {
    method: 'POST',
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      'Content-Type': 'application/json',
      // Signing up twice is not an error to the person doing it.
      Prefer: 'resolution=ignore-duplicates,return=minimal',
    },
    body: JSON.stringify({ email: parsed.email, source: req.headers.get('referer') ?? null }),
  })
  if (!res.ok) {
    console.error('waitlist insert failed', res.status, await res.text())
    return Response.json({ error: 'Something went wrong. Try again in a minute.' }, { status: 502 })
  }
  return Response.json({ ok: true })
}
