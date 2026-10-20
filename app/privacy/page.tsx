import type { Metadata } from 'next'
import Link from 'next/link'

export const metadata: Metadata = { title: 'Privacy — Yearfilm' }

// DRAFT for legal review. This page is the App Store "Privacy Policy URL", so it must
// stay true to what the shipped app does: update it in the same change as any new
// data flow, especially anything sent to a third party or a third-party AI service.
export default function Privacy() {
  return (
    <div className="wrap doc">
      <nav className="nav">
        <Link href="/" className="mark">
          year<span>film</span>
        </Link>
      </nav>
      <h1>Privacy</h1>
      <p className="updated">Last updated October 20, 2026</p>

      <p>
        Yearfilm makes a film from your family’s videos. Those videos are some of the most personal
        things you own, so the short version is: they are yours, they are private, and you can
        delete them whenever you want.
      </p>

      <h2>The waitlist</h2>
      <p>
        If you join the waitlist we store your email address and the page you signed up from. We
        use it to tell you when Yearfilm is available, and for nothing else. We don’t sell or share
        it. Email <a href="mailto:privacy@yearfilm.com">privacy@yearfilm.com</a> to be removed.
      </p>

      <h2>The app</h2>
      <ul>
        <li>
          <strong>Your videos and voice notes</strong> stay on your device, and in your own iCloud
          if you turn on backup. You choose each clip; the app never scans your photo library.
        </li>
        <li>
          <strong>Microphone</strong> is used only while you record a voice note.
        </li>
        <li>
          <strong>Notifications</strong> are used for your weekly reminder, only if you allow them.
        </li>
        <li>
          <strong>No tracking.</strong> No advertising identifiers, no third-party analytics, no
          data brokers.
        </li>
      </ul>

      <h2>iCloud backup and family</h2>
      <p>
        There is no Yearfilm account, and Yearfilm has no server that holds your videos or voice
        notes. If you turn on iCloud backup, the app keeps a copy in your own iCloud, under your
        Apple ID and your iCloud storage. Apple stores it; we can’t see it.
      </p>
      <p>
        If you invite family to a year’s film, that year of your iCloud backup is shared with the
        people who accept, through iCloud sharing. They can see it, and the clips they add from
        that year go into it and use your iCloud storage. If someone invites you, the clips you
        send — from that year, and the weeks they asked for — go into their iCloud, and they can
        see them. The name you enter in Settings shows next to what you add. Nothing else on your
        phone is sent.
      </p>

      <h2>Third-party services, including AI</h2>
      <p>
        Some features may use outside services — for example, transcribing a voice note or
        choosing music. Before any of your videos, voice notes or other personal data is sent to a
        third party, including a third-party AI service, the app will tell you exactly what is
        sent and to whom, and ask for your permission. You can say no and keep using the app, and
        you can withdraw permission in Settings at any time.
      </p>

      <h2>Faces</h2>
      <p>
        Any feature that recognises people in your videos will be off until each person (or a
        parent, for a child) agrees to it.
      </p>

      <h2>Deleting your data</h2>
      <p>
        In the app, Settings → Delete all my data removes every clip, voice note and film from your
        iPhone. Settings → iCloud → Delete iCloud backup removes your backup from your iCloud, and
        ends any year you shared for everyone in it. You can also manage it in your iPhone’s
        Settings → your name → iCloud.
      </p>

      <h2>Children</h2>
      <p>
        Yearfilm is for adults to record their families. It isn’t directed at children and
        children shouldn’t create accounts.
      </p>

      <h2>Contact</h2>
      <p>
        <a href="mailto:privacy@yearfilm.com">privacy@yearfilm.com</a>
      </p>
    </div>
  )
}
