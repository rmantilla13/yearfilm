import { head } from '@vercel/blob'
import { parseUploadRequest, pathFor, weekAllowed } from '@/lib/media'
import { blobToken, HttpError, membershipOf, readJson, requireUser, respond } from '@/lib/server'

// POST {kind, id, capturedOn, ext, byteSize, durationS} after the PUT finished.
//
// Records the clip or note only once Blob confirms the file is there, under this family's
// path. Safe to call again: the row is keyed by the phone's id, and a row that belongs to
// another family is never touched.

export const POST = (req: Request) =>
  respond(async () => {
    const { db, user } = await requireUser(req)
    const body = await readJson(req)
    const parsed = parseUploadRequest(body)
    if (!parsed.ok) throw new HttpError(400, parsed.error)
    const r = parsed.value
    const raw = (body as Record<string, unknown>).durationS
    const durationS = typeof raw === 'number' && Number.isFinite(raw) && raw >= 0 ? raw : null

    const m = await membershipOf(db, user.id)
    if (!m) throw new HttpError(409, 'Create your family first.')
    if (m.role === 'viewer') throw new HttpError(403, 'Viewers can’t add clips.')
    if (!weekAllowed(r.capturedOn, m)) {
      throw new HttpError(403, 'Your invite covers other weeks of the film.')
    }

    const pathname = pathFor(m.familyId, r)
    const blob = await head(pathname, { token: blobToken() }).catch(() => null)
    if (!blob) throw new HttpError(409, 'The upload hasn’t arrived yet.')

    const table = r.kind === 'footage' ? 'footage' : 'voice_notes'
    const row: Record<string, unknown> =
      r.kind === 'footage'
        ? {
            id: r.id,
            family_id: m.familyId,
            uploaded_by: user.id,
            original_path: pathname,
            captured_on: r.capturedOn,
            duration_s: durationS,
            byte_size: blob.size,
            content_type: blob.contentType,
          }
        : {
            id: r.id,
            family_id: m.familyId,
            recorded_by: user.id,
            path: pathname,
            recorded_on: r.capturedOn,
            duration_s: durationS,
            byte_size: blob.size,
          }

    const { error } = await db.from(table).upsert(row, { onConflict: 'id', ignoreDuplicates: true })
    if (error) throw new HttpError(502, 'Couldn’t save the clip.')
    const { data: saved } = await db.from(table).select('family_id').eq('id', r.id).single()
    if (!saved || saved.family_id !== m.familyId) throw new HttpError(409, 'That id is already in use.')

    return Response.json({ ok: true, pathname })
  })
