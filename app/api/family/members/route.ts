import { HttpError, membershipOf, requireUser, respond } from '@/lib/server'

// GET: who's in the family, for the account screen. Any member may see it.

export const GET = (req: Request) =>
  respond(async () => {
    const { db, user } = await requireUser(req)
    const m = await membershipOf(db, user.id)
    if (!m) throw new HttpError(409, 'You’re not in a family yet.')

    const { data: members, error } = await db
      .from('family_members')
      .select('user_id, role, weeks, weeks_year, created_at')
      .eq('family_id', m.familyId)
      .order('created_at')
    if (error) throw new HttpError(502, 'Couldn’t read your family.')

    const ids = (members ?? []).map((x) => x.user_id)
    const { data: profiles } = await db.from('profiles').select('user_id, display_name').in('user_id', ids)
    const names = new Map((profiles ?? []).map((p) => [p.user_id, p.display_name as string | null]))

    return Response.json({
      members: (members ?? []).map((x) => ({
        id: x.user_id,
        name: names.get(x.user_id) ?? null,
        role: x.role,
        weeks: x.weeks,
        year: x.weeks_year,
        isYou: x.user_id === user.id,
      })),
    })
  })
