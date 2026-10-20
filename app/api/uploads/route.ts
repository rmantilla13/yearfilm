import { issueSignedToken, presignUrl } from '@vercel/blob'
import { parseUploadRequest, pathFor, weekAllowed } from '@/lib/media'
import { blobToken, HttpError, membershipOf, readJson, requireUser, respond } from '@/lib/server'

// POST {kind, id, capturedOn, ext, byteSize} → a presigned PUT for exactly one file.
//
// The phone uploads straight to Blob with it (a background URLSession task), so video never
// passes through a function. The URL is scoped to one pathname the server built, one content
// type, the declared size, and can't overwrite: a retry after a finished upload is a no-op
// the app treats as success, and nobody can replace someone else's clip.

// Background uploads can wait a while before they start; the app asks again if this lapses.
const VALID_MS = 6 * 60 * 60 * 1000

export const POST = (req: Request) =>
  respond(async () => {
    const { db, user } = await requireUser(req)
    const parsed = parseUploadRequest(await readJson(req))
    if (!parsed.ok) throw new HttpError(400, parsed.error)
    const r = parsed.value

    const m = await membershipOf(db, user.id)
    if (!m) throw new HttpError(409, 'Create your family first.')
    if (m.role === 'viewer') throw new HttpError(403, 'Viewers can’t add clips.')
    if (!weekAllowed(r.capturedOn, m)) {
      throw new HttpError(403, 'Your invite covers other weeks of the film.')
    }

    const pathname = pathFor(m.familyId, r)
    const validUntil = Date.now() + VALID_MS
    const token = await issueSignedToken({
      token: blobToken(),
      pathname,
      operations: ['put'],
      allowedContentTypes: [r.contentType],
      maximumSizeInBytes: r.byteSize,
      validUntil,
    })
    const { presignedUrl } = await presignUrl(token, {
      operation: 'put',
      pathname,
      access: 'private',
      allowedContentTypes: [r.contentType],
      maximumSizeInBytes: r.byteSize,
      allowOverwrite: false,
      addRandomSuffix: false,
      validUntil,
    })

    return Response.json({
      method: 'PUT',
      url: presignedUrl,
      headers: { 'content-type': r.contentType },
      pathname,
      expiresAt: new Date(validUntil).toISOString(),
    })
  })
