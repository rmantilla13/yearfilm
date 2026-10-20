import 'server-only'
import type { SupabaseClient } from '@supabase/supabase-js'
import { hashToken, inviteState, isToken, type InviteRow } from '@/lib/invites'

/** The invite behind a token, with its family's name. Null for anything that doesn't match. */
export async function lookupInvite(db: SupabaseClient, token: unknown) {
  if (!isToken(token)) return null
  const { data } = await db
    .from('family_invites')
    .select('id, family_id, role, weeks, weeks_year, expires_at, revoked_at, uses, created_by, families(name)')
    .eq('token_hash', hashToken(token))
    .maybeSingle()
  if (!data) return null
  const row = data as unknown as InviteRow & { created_by: string | null; families: { name: string } | null }
  let invitedBy: string | null = null
  if (row.created_by) {
    const { data: p } = await db.from('profiles').select('display_name').eq('user_id', row.created_by).maybeSingle()
    invitedBy = p?.display_name ?? null
  }
  return { row, familyName: row.families?.name ?? 'A family', invitedBy, state: inviteState(row) }
}
