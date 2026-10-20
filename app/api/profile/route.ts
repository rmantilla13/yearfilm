import { parseDisplayName } from '@/lib/media'
import { HttpError, readJson, requireUser, respond } from '@/lib/server'

// GET / PUT {displayName}: the name your family sees next to the clips you add.

export const GET = (req: Request) =>
  respond(async () => {
    const { db, user } = await requireUser(req)
    const { data } = await db.from('profiles').select('display_name').eq('user_id', user.id).maybeSingle()
    return Response.json({ displayName: data?.display_name ?? null })
  })

export const PUT = (req: Request) =>
  respond(async () => {
    const { db, user } = await requireUser(req)
    const name = parseDisplayName(await readJson(req))
    if (!name.ok) throw new HttpError(400, name.error)
    const { error } = await db
      .from('profiles')
      .upsert({ user_id: user.id, display_name: name.value, updated_at: new Date().toISOString() })
    if (error) throw new HttpError(502, 'Couldn’t save your name.')
    return Response.json({ displayName: name.value })
  })
