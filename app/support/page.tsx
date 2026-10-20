import type { Metadata } from 'next'
import Link from 'next/link'

export const metadata: Metadata = { title: 'Support — Yearfilm' }

// The App Store "Support URL". It must lead to real contact information.
export default function Support() {
  return (
    <div className="wrap doc">
      <nav className="nav">
        <Link href="/" className="mark">
          year<span>film</span>
        </Link>
      </nav>
      <h1>Support</h1>
      <p>
        Something not working, or an idea for your film? Email{' '}
        <a href="mailto:support@yearfilm.com">support@yearfilm.com</a> and a person will answer.
      </p>

      <h2>Common questions</h2>
      <h3>What should I film?</h3>
      <p>
        Whatever your week was. Each week the app suggests one shot to try. Hold the phone sideways
        and keep filming for ten seconds — the film is made from moments, and moments need a little
        room.
      </p>
      <h3>When is my film ready?</h3>
      <p>Your film premieres in December, in time for the holidays.</p>
      <h3>How do I delete my data?</h3>
      <p>
        Settings → Delete all my data. See the <Link href="/privacy">privacy page</Link> for
        details.
      </p>
    </div>
  )
}
