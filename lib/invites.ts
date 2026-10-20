import 'server-only'
import { createHash, randomBytes } from 'node:crypto'

// Invite links carry a random token; only its hash is stored.

export function newToken(): string {
  return randomBytes(24).toString('base64url')
}

export function hashToken(token: string): string {
  return createHash('sha256').update(token).digest('hex')
}

/** Rejects anything that isn't shaped like a token before it reaches the database. */
export function isToken(s: unknown): s is string {
  return typeof s === 'string' && /^[A-Za-z0-9_-]{32}$/.test(s)
}

/** The link to share. A preview deployment shares links to itself. */
export function inviteUrl(req: Request, token: string): string {
  const origin = process.env.VERCEL_ENV === 'production' ? 'https://www.yearfilm.com' : new URL(req.url).origin
  return `${origin}/join/${token}`
}

export type InviteRow = {
  id: string
  family_id: string
  role: 'contributor' | 'viewer'
  weeks: number[] | null
  weeks_year: number | null
  expires_at: string
  revoked_at: string | null
  uses: number
}

export function inviteState(row: Pick<InviteRow, 'expires_at' | 'revoked_at'>): 'open' | 'expired' | 'revoked' {
  if (row.revoked_at) return 'revoked'
  return Date.parse(row.expires_at) <= Date.now() ? 'expired' : 'open'
}
