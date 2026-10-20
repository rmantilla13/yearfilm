import { lookupInvite } from '@/lib/invite-lookup'
import { HttpError, respond, supabaseAdmin } from '@/lib/server'

// GET ?token=… — what a link invites you to, before signing in. Public: the token is the
// secret, and the answer is only what the person who shared it meant you to see.

export const GET = (req: Request) =>
  respond(async () => {
    const db = supabaseAdmin()
    if (!db) throw new HttpError(503, 'Invites aren’t set up on this server yet.')
    const invite = await lookupInvite(db, new URL(req.url).searchParams.get('token'))
    if (!invite) throw new HttpError(404, 'This invite link isn’t valid.')
    const { row } = invite
    return Response.json(
      {
        familyName: invite.familyName,
        invitedBy: invite.invitedBy,
        role: row.role,
        weeks: row.weeks,
        year: row.weeks_year,
        expiresAt: row.expires_at,
        state: invite.state,
      },
      { headers: { 'Cache-Control': 'private, no-store' } },
    )
  })
