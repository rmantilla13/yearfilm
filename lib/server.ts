import 'server-only'
import { createClient, type SupabaseClient, type User } from '@supabase/supabase-js'

// Server-side only: the service key and the Blob token never leave Vercel.

let admin: SupabaseClient | null = null

export function supabaseAdmin(): SupabaseClient | null {
  const url = process.env.SUPABASE_URL
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY
  if (!url || !key) return null
  admin ??= createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } })
  return admin
}

/**
 * The Blob token to sign with. The read-write token when it's set; otherwise undefined,
 * so the SDK falls back to the deployment's OIDC identity.
 */
export const blobToken = () => process.env.BLOB_READ_WRITE_TOKEN || undefined

export type Membership = {
  familyId: string
  role: 'producer' | 'contributor' | 'viewer'
  /** Contributors may be limited to some weeks of one year; null = any week. */
  weeks: number[] | null
  year: number | null
}

export class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message)
  }
}

/** The signed-in user, from the Supabase access token the app sends as a bearer token. */
export async function requireUser(req: Request): Promise<{ db: SupabaseClient; user: User }> {
  const db = supabaseAdmin()
  if (!db) throw new HttpError(503, 'Accounts aren’t set up on this server yet.')
  const header = req.headers.get('authorization') ?? ''
  const jwt = header.startsWith('Bearer ') ? header.slice(7) : ''
  if (!jwt) throw new HttpError(401, 'Sign in first.')
  const { data, error } = await db.auth.getUser(jwt)
  if (error || !data.user) throw new HttpError(401, 'Sign in again.')
  return { db, user: data.user }
}

/** One family per person: accepting an invite to a second family is refused. */
export async function membershipOf(db: SupabaseClient, userId: string): Promise<Membership | null> {
  const { data, error } = await db
    .from('family_members')
    .select('family_id, role, weeks, weeks_year')
    .eq('user_id', userId)
    .order('created_at')
    .limit(1)
    .maybeSingle()
  if (error) throw new HttpError(502, 'Couldn’t read your family.')
  return data ? { familyId: data.family_id, role: data.role, weeks: data.weeks, year: data.weeks_year } : null
}

export async function readJson(req: Request): Promise<unknown> {
  try {
    return await req.json()
  } catch {
    throw new HttpError(400, 'Expected JSON.')
  }
}

/** Runs a handler and turns HttpErrors into JSON responses; anything else is logged and hidden. */
export async function respond(handler: () => Promise<Response>): Promise<Response> {
  try {
    return await handler()
  } catch (e) {
    if (e instanceof HttpError) return Response.json({ error: e.message }, { status: e.status })
    console.error(e)
    return Response.json({ error: 'Something went wrong. Try again in a minute.' }, { status: 500 })
  }
}

export function requireProducer(m: Membership | null): Membership {
  if (!m) throw new HttpError(409, 'Create your family first.')
  if (m.role !== 'producer') throw new HttpError(403, 'Only the film’s producers can do that.')
  return m
}

/** What the app shows about the family it belongs to. */
export async function familyView(db: SupabaseClient, m: Membership) {
  const { data } = await db.from('families').select('id, name').eq('id', m.familyId).single()
  return data && { ...data, role: m.role, weeks: m.weeks, year: m.year }
}
