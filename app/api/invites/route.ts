import { parseInviteRequest } from '@/lib/media'
import { hashToken, inviteState, inviteUrl, newToken, type InviteRow } from '@/lib/invites'
import { HttpError, membershipOf, readJson, requireProducer, requireUser, respond } from '@/lib/server'

// POST {role?, weeks?, year?, days?}: a new shareable link (producers). The token is returned
//   once, in the URL; only its hash is kept, so a lost link is revoked and replaced, not shown again.
// GET: the family's invites, for revoking.

export const POST = (req: Request) =>
  respond(async () => {
    const { db, user } = await requireUser(req)
    const m = requireProducer(await membershipOf(db, user.id))
    const parsed = parseInviteRequest(await readJson(req))
    if (!parsed.ok) throw new HttpError(400, parsed.error)
    const r = parsed.value

    const token = newToken()
    const expiresAt = new Date(Date.now() + r.days * 86_400_000).toISOString()
    const { data, error } = await db
      .from('family_invites')
      .insert({
        family_id: m.familyId,
        token_hash: hashToken(token),
        role: r.role,
        weeks: r.weeks,
        weeks_year: r.year,
        created_by: user.id,
        expires_at: expiresAt,
      })
      .select('id')
      .single()
    if (error || !data) throw new HttpError(502, 'Couldn’t make the link.')

    return Response.json(
      { id: data.id, url: inviteUrl(req, token), role: r.role, weeks: r.weeks, year: r.year, expiresAt },
      { status: 201 },
    )
  })

export const GET = (req: Request) =>
  respond(async () => {
    const { db, user } = await requireUser(req)
    const m = requireProducer(await membershipOf(db, user.id))
    const { data, error } = await db
      .from('family_invites')
      .select('id, family_id, role, weeks, weeks_year, expires_at, revoked_at, uses')
      .eq('family_id', m.familyId)
      .order('created_at', { ascending: false })
      .limit(50)
    if (error) throw new HttpError(502, 'Couldn’t read your invites.')
    return Response.json({
      invites: (data as InviteRow[]).map((i) => ({
        id: i.id,
        role: i.role,
        weeks: i.weeks,
        year: i.weeks_year,
        expiresAt: i.expires_at,
        uses: i.uses,
        state: inviteState(i),
      })),
    })
  })
