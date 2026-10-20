import { del, list } from '@vercel/blob'
import type { SupabaseClient } from '@supabase/supabase-js'
import { blobToken, HttpError, requireUser, respond } from '@/lib/server'

// DELETE: delete my account (App Store Guideline 5.1.1(v): deletion must be possible in the app
// and must remove server data, not just sign out).
//
// A family whose last producer leaves goes with them: every clip and note in Blob, then the
// rows. Otherwise the person leaves the family; what they added stays in the family's film,
// no longer attributed to them.

export const DELETE = (req: Request) =>
  respond(async () => {
    const { db, user } = await requireUser(req)

    const { data: memberships, error } = await db
      .from('family_members')
      .select('family_id, role')
      .eq('user_id', user.id)
    if (error) throw new HttpError(502, 'Couldn’t read your family.')

    for (const m of memberships ?? []) {
      const { count } = await db
        .from('family_members')
        .select('user_id', { count: 'exact', head: true })
        .eq('family_id', m.family_id)
        .eq('role', 'producer')
        .neq('user_id', user.id)
      if (m.role === 'producer' && !count) {
        await deleteFamily(db, m.family_id)
      }
    }

    // Cascades remove remaining memberships; uploaded_by / recorded_by become null.
    const { error: authError } = await db.auth.admin.deleteUser(user.id)
    if (authError) throw new HttpError(502, 'Couldn’t delete your account. Try again in a minute.')
    return Response.json({ ok: true })
  })

async function deleteFamily(db: SupabaseClient, familyId: string) {
  // Files first: a row without a file is harmless, a file without a row is unfindable.
  const token = blobToken()
  let cursor: string | undefined
  do {
    const page = await list({ token, prefix: `${familyId}/`, cursor, limit: 1000 })
    if (page.blobs.length) await del(page.blobs.map((b) => b.url), { token })
    cursor = page.hasMore ? page.cursor : undefined
  } while (cursor)

  const { error } = await db.from('families').delete().eq('id', familyId)
  if (error) throw new HttpError(502, 'Couldn’t delete your family’s data.')
}
