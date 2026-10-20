import { isUuid } from '@/lib/media'
import { HttpError, membershipOf, requireProducer, requireUser, respond } from '@/lib/server'

// DELETE: revoke a link (producers). People who already joined stay in the family.

export const DELETE = (req: Request, ctx: { params: Promise<{ id: string }> }) =>
  respond(async () => {
    const { id } = await ctx.params
    if (!isUuid(id)) throw new HttpError(404, 'No such invite.')
    const { db, user } = await requireUser(req)
    const m = requireProducer(await membershipOf(db, user.id))
    const { data, error } = await db
      .from('family_invites')
      .update({ revoked_at: new Date().toISOString() })
      .eq('id', id)
      .eq('family_id', m.familyId)
      .is('revoked_at', null)
      .select('id')
    if (error) throw new HttpError(502, 'Couldn’t revoke the link.')
    return Response.json({ revoked: (data ?? []).length > 0 })
  })
