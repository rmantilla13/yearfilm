import { lookupInvite } from '@/lib/invite-lookup'
import { familyView, HttpError, membershipOf, readJson, requireUser, respond } from '@/lib/server'

// POST {token}: join the family behind a link.
//
// - Revoked or expired links fail here, not only on the preview.
// - Joining a family you're already in changes nothing; a producer opening their own link
//   is never downgraded.
// - One family per person: a link to a second family is refused, never added silently.

export const POST = (req: Request) =>
  respond(async () => {
    const { db, user } = await requireUser(req)
    const body = (await readJson(req)) as Record<string, unknown> | null
    const invite = await lookupInvite(db, body?.token)
    if (!invite) throw new HttpError(404, 'This invite link isn’t valid.')
    if (invite.state === 'revoked') throw new HttpError(410, 'This invite link was turned off.')
    if (invite.state === 'expired') throw new HttpError(410, 'This invite link has expired. Ask for a new one.')
    const { row } = invite

    const existing = await membershipOf(db, user.id)
    if (existing?.familyId === row.family_id) {
      return Response.json({ family: await familyView(db, existing), joined: false })
    }
    if (existing) {
      throw new HttpError(409, 'You’re already part of another family’s film. Leave it before joining this one.')
    }

    const { error } = await db.from('family_members').insert({
      family_id: row.family_id,
      user_id: user.id,
      role: row.role,
      weeks: row.weeks,
      weeks_year: row.weeks_year,
      invited_by: invite.row.created_by ?? null,
    })
    if (error) throw new HttpError(502, 'Couldn’t join the family.')
    await db.from('family_invites').update({ uses: row.uses + 1 }).eq('id', row.id)

    const m = { familyId: row.family_id, role: row.role, weeks: row.weeks, year: row.weeks_year }
    return Response.json({ family: await familyView(db, m), joined: true }, { status: 201 })
  })
