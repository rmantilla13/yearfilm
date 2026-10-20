// What the phone may upload, and where it goes. Pure, so the routes agree and it can be tested.
//
// The server builds every pathname itself from the family it verified, an id and a date.
// Nothing the client sends becomes part of a path unchecked.

export type Kind = 'footage' | 'voice_note'

export type UploadRequest = {
  kind: Kind
  id: string
  capturedOn: string // YYYY-MM-DD, the local calendar day; never a UTC instant
  ext: string
  contentType: string
  byteSize: number
}

export type Parsed<T> = { ok: true; value: T } | { ok: false; error: string }

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
const DAY = /^(\d{4})-(\d{2})-(\d{2})$/

// Content types per kind, keyed by the extension the file is stored under.
const TYPES: Record<Kind, Record<string, string>> = {
  footage: { mov: 'video/quicktime', mp4: 'video/mp4', m4v: 'video/x-m4v' },
  voice_note: { m4a: 'audio/mp4' },
}

// One presigned PUT is proven to 500 MB (a single 1.5 GB PUT gets 413 from Blob). Longer
// 4K clips need multipart uploads, which aren't built yet, so they're refused rather than
// retried forever.
export const MAX_BYTES: Record<Kind, number> = {
  footage: 500 * 1024 ** 2,
  voice_note: 50 * 1024 ** 2,
}

export function isUuid(s: unknown): s is string {
  return typeof s === 'string' && UUID.test(s)
}

/** A real calendar day within the years the app could have filmed. */
export function parseDay(s: unknown): Parsed<{ day: string; year: number }> {
  if (typeof s !== 'string') return { ok: false, error: 'Missing date.' }
  const m = DAY.exec(s)
  if (!m) return { ok: false, error: 'Date must be YYYY-MM-DD.' }
  const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])]
  const date = new Date(Date.UTC(y, mo - 1, d))
  if (date.getUTCFullYear() !== y || date.getUTCMonth() !== mo - 1 || date.getUTCDate() !== d) {
    return { ok: false, error: 'Not a real date.' }
  }
  // A phone's local day can run ahead of UTC by up to 14 hours.
  const thisYear = new Date().getUTCFullYear()
  if (y < 2000 || y > thisYear + 1) return { ok: false, error: 'Date is out of range.' }
  return { ok: true, value: { day: s, year: y } }
}

export function parseUploadRequest(body: unknown): Parsed<UploadRequest> {
  if (typeof body !== 'object' || body === null) return { ok: false, error: 'Expected JSON.' }
  const b = body as Record<string, unknown>
  if (b.kind !== 'footage' && b.kind !== 'voice_note') return { ok: false, error: 'Unknown kind.' }
  const kind = b.kind
  if (!isUuid(b.id)) return { ok: false, error: 'id must be a lowercase UUID.' }
  const day = parseDay(b.capturedOn)
  if (!day.ok) return day
  const ext = typeof b.ext === 'string' ? b.ext.toLowerCase() : ''
  const contentType = TYPES[kind][ext]
  if (!contentType) return { ok: false, error: `Can’t upload .${ext || '?'} as ${kind}.` }
  const byteSize = b.byteSize
  if (typeof byteSize !== 'number' || !Number.isInteger(byteSize) || byteSize <= 0) {
    return { ok: false, error: 'byteSize must be a positive integer.' }
  }
  if (byteSize > MAX_BYTES[kind]) return { ok: false, error: 'File is too large.' }
  return { ok: true, value: { kind, id: b.id, capturedOn: day.value.day, ext, contentType, byteSize } }
}

/** {family}/{year}/original/{id}.{ext} for footage, {family}/{year}/notes/{id}.m4a for notes. */
export function pathFor(familyId: string, r: Pick<UploadRequest, 'kind' | 'id' | 'capturedOn' | 'ext'>): string {
  const year = r.capturedOn.slice(0, 4)
  const folder = r.kind === 'footage' ? 'original' : 'notes'
  return `${familyId}/${year}/${folder}/${r.id}.${r.ext}`
}

export function parseFamilyName(body: unknown): Parsed<string> {
  const name = typeof body === 'object' && body !== null ? (body as Record<string, unknown>).name : undefined
  if (typeof name !== 'string') return { ok: false, error: 'Missing name.' }
  const clean = name.trim().replace(/\s+/g, ' ')
  if (!clean) return { ok: false, error: 'Missing name.' }
  if (clean.length > 80) return { ok: false, error: 'Name is too long.' }
  return { ok: true, value: clean }
}

/**
 * The film week of a calendar day, the same rule as FilmWeek.swift: counted from January 1,
 * seven days a week, with the last day or two of the year folded into week 52.
 */
export function filmWeek(day: string): { year: number; week: number } {
  const [y, m, d] = day.split('-').map(Number)
  const ordinal = (Date.UTC(y, m - 1, d) - Date.UTC(y, 0, 1)) / 86_400_000 + 1
  return { year: y, week: Math.min(Math.max(Math.floor((ordinal - 1) / 7) + 1, 1), 52) }
}

/** Whether a member limited to some weeks of one year may add something filmed on `day`. */
export function weekAllowed(day: string, limit: { weeks: number[] | null; year: number | null }): boolean {
  if (!limit.weeks) return true
  const w = filmWeek(day)
  return w.year === limit.year && limit.weeks.includes(w.week)
}

export type InviteRequest = { role: 'contributor' | 'viewer'; weeks: number[] | null; year: number | null; days: number }

/** POST /api/invites body. Weeks are optional; with weeks, a year is required. */
export function parseInviteRequest(body: unknown): Parsed<InviteRequest> {
  const b = (typeof body === 'object' && body !== null ? body : {}) as Record<string, unknown>
  const role = b.role ?? 'contributor'
  if (role !== 'contributor' && role !== 'viewer') return { ok: false, error: 'Invites are for contributors or viewers.' }
  const days = b.days ?? 14
  if (typeof days !== 'number' || !Number.isInteger(days) || days < 1 || days > 90) {
    return { ok: false, error: 'Links last between 1 and 90 days.' }
  }
  if (b.weeks === undefined || b.weeks === null) return { ok: true, value: { role, weeks: null, year: null, days } }
  if (!Array.isArray(b.weeks) || b.weeks.length === 0 || b.weeks.length > 52) {
    return { ok: false, error: 'Pick between 1 and 52 weeks.' }
  }
  if (!b.weeks.every((w) => Number.isInteger(w) && w >= 1 && w <= 52)) return { ok: false, error: 'Weeks run 1–52.' }
  const thisYear = new Date().getUTCFullYear()
  if (typeof b.year !== 'number' || !Number.isInteger(b.year) || b.year < thisYear - 1 || b.year > thisYear + 1) {
    return { ok: false, error: 'Pick the film year.' }
  }
  const weeks = [...new Set(b.weeks as number[])].sort((a, z) => a - z)
  return { ok: true, value: { role, weeks, year: b.year, days } }
}

export function parseDisplayName(body: unknown): Parsed<string | null> {
  const raw = typeof body === 'object' && body !== null ? (body as Record<string, unknown>).displayName : undefined
  if (raw === null) return { ok: true, value: null }
  if (typeof raw !== 'string') return { ok: false, error: 'Missing name.' }
  const clean = raw.trim().replace(/\s+/g, ' ')
  if (clean.length > 60) return { ok: false, error: 'Name is too long.' }
  return { ok: true, value: clean || null }
}
