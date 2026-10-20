import { parseFamilyName } from '@/lib/media'
import { familyView, HttpError, membershipOf, readJson, requireProducer, requireUser, respond } from '@/lib/server'

// GET: the signed-in person's family, or null.
// POST {name}: start a family (as its producer) if they have none — calling it twice is not an
//   error. Only called when a producer turns on backup; signing in alone never creates one.
// PATCH {name}: rename it (producers).

export const GET = (req: Request) =>
  respond(async () => {
    const { db, user } = await requireUser(req)
    const m = await membershipOf(db, user.id)
    return Response.json({ family: m && (await familyView(db, m)) })
  })

export const POST = (req: Request) =>
  respond(async () => {
    const { db, user } = await requireUser(req)
    const name = parseFamilyName(await readJson(req))
    if (!name.ok) throw new HttpError(400, name.error)

    const existing = await membershipOf(db, user.id)
    if (existing) return Response.json({ family: await familyView(db, existing) })

    const { data: family, error } = await db.from('families').insert({ name: name.value }).select('id').single()
    if (error || !family) throw new HttpError(502, 'Couldn’t create your family.')
    const { error: memberError } = await db
      .from('family_members')
      .insert({ family_id: family.id, user_id: user.id, role: 'producer' })
    if (memberError) {
      await db.from('families').delete().eq('id', family.id)
      throw new HttpError(502, 'Couldn’t create your family.')
    }
    const m = { familyId: family.id, role: 'producer' as const, weeks: null, year: null }
    return Response.json({ family: await familyView(db, m) }, { status: 201 })
  })

export const PATCH = (req: Request) =>
  respond(async () => {
    const { db, user } = await requireUser(req)
    const m = requireProducer(await membershipOf(db, user.id))
    const name = parseFamilyName(await readJson(req))
    if (!name.ok) throw new HttpError(400, name.error)
    const { error } = await db.from('families').update({ name: name.value }).eq('id', m.familyId)
    if (error) throw new HttpError(502, 'Couldn’t rename your family.')
    return Response.json({ family: await familyView(db, m) })
  })
