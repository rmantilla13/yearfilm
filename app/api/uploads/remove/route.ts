import { del } from '@vercel/blob'
import { isUuid } from '@/lib/media'
import { blobToken, HttpError, membershipOf, readJson, requireUser, respond } from '@/lib/server'

// POST {kind, id}: take a clip or voice note out of the family's film — its file in Blob and
// its row. Whoever added it, or a producer, may remove it. Removing something that's already
// gone is not an error, so the app can retry freely.

export const POST = (req: Request) =>
  respond(async () => {
    const { db, user } = await requireUser(req)
    const body = (await readJson(req)) as Record<string, unknown> | null
    const kind = body?.kind
    const id = body?.id
    if (kind !== 'footage' && kind !== 'voice_note') throw new HttpError(400, 'Unknown kind.')
    if (!isUuid(id)) throw new HttpError(400, 'id must be a lowercase UUID.')

    const m = await membershipOf(db, user.id)
    if (!m) return Response.json({ removed: false })

    const table = kind === 'footage' ? 'footage' : 'voice_notes'
    const pathColumn = kind === 'footage' ? 'original_path' : 'path'
    const byColumn = kind === 'footage' ? 'uploaded_by' : 'recorded_by'
    const { data: row } = await db
      .from(table)
      .select(`family_id, ${pathColumn}, ${byColumn}`)
      .eq('id', id)
      .maybeSingle()
    const r = row as Record<string, string | null> | null
    if (!r || r.family_id !== m.familyId) return Response.json({ removed: false })
    if (m.role !== 'producer' && r[byColumn] !== user.id) {
      throw new HttpError(403, 'Only the person who added it, or a producer, can remove it.')
    }

    // The file first: a row without a file is harmless, a file without a row is unfindable.
    const path = r[pathColumn]
    if (path) await del(path, { token: blobToken() }).catch(() => undefined)
    const { error } = await db.from(table).delete().eq('id', id)
    if (error) throw new HttpError(502, 'Couldn’t remove it. Try again in a minute.')
    return Response.json({ removed: true })
  })
