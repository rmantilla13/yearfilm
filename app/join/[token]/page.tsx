import type { Metadata } from 'next'
import Link from 'next/link'
import { lookupInvite } from '@/lib/invite-lookup'
import { supabaseAdmin } from '@/lib/server'
import { weeksLabel } from '@/lib/weeks'

// Where a shared invite link lands. It says whose film it is and which weeks, then hands
// off to the app, which does the joining after the person signs in.

export const dynamic = 'force-dynamic'

// Don't let a family's invite show up in search or link previews with its name.
export const metadata: Metadata = {
  title: 'You’re invited — Yearfilm',
  robots: { index: false, follow: false },
  referrer: 'no-referrer',
}

export default async function Join({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params
  const db = supabaseAdmin()
  const invite = db ? await lookupInvite(db, token) : null

  return (
    <div className="wrap doc join">
      <nav className="nav">
        <Link href="/" className="mark">
          year<span>film</span>
        </Link>
      </nav>

      {!invite ? (
        <>
          <h1>This link doesn’t work</h1>
          <p>It may have been mistyped. Ask whoever sent it for a new one.</p>
        </>
      ) : invite.state !== 'open' ? (
        <>
          <h1>This link has {invite.state === 'expired' ? 'expired' : 'been turned off'}</h1>
          <p>Ask {invite.invitedBy ?? 'whoever sent it'} for a new one.</p>
        </>
      ) : (
        <>
          <p className="eyebrow">You’re invited</p>
          <h1>
            Help make <em>{invite.familyName}</em>’s film
          </h1>
          <div className="join-card">
            <p>
              {invite.invitedBy ? `${invite.invitedBy} invited you` : 'You’re invited'} to{' '}
              {invite.row.role === 'viewer'
                ? 'watch the film when it premieres.'
                : `add your videos ${weeksLabel(invite.row.weeks, invite.row.weeks_year)}.`}
            </p>
            {invite.row.role !== 'viewer' && (
              <p className="note">
                Yearfilm files each clip under the week it was filmed, so you can send a whole batch at
                once. The film’s producers will see what you add.
              </p>
            )}
            <a className="join-open" href={`yearfilm://join/${token}`}>
              Open in Yearfilm
            </a>
          </div>
          <p className="note">
            Don’t have the app yet? Yearfilm is in beta — ask {invite.invitedBy ?? 'whoever sent this'} for the
            TestFlight link, install it, then come back and tap Open in Yearfilm.
          </p>
        </>
      )}
    </div>
  )
}
