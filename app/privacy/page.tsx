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
          <strong>Your videos and voice notes</strong> stay on your device unless you turn on
          backup. You choose each clip; the app never scans your photo library.
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

      <h2>Accounts and backup</h2>
      <p>
        You can use Yearfilm without an account. If you sign in, we use Sign in with Apple: Apple
        gives us an identifier for your account, and we don’t ask for your name or email. Signing
        in uploads nothing by itself.
      </p>
      <p>
        If you then turn on backup, the app uploads your clips and voice notes, with the day each
        was filmed and how long it is, so your family’s film can be made from them. They are kept
        in private storage that only your family can reach, and are used only to make your film.
        We never use them for advertising or to train AI models.
      </p>
      <p>
        If you add a name to your profile, people in your family see it next to the clips you
        add. Everyone in a family can see who else is in it. If you join someone’s film from an
        invite link, the clips you add go to their family’s film and its producers can see them;
        a link can be limited to certain weeks, and then only clips filmed in those weeks are
        sent.
      </p>
      <p>
        The companies that store this for us: Supabase (your account and the list of your clips,
        in the United States) and Vercel (the video and audio files, in the United States). They
        process it on our behalf and may not use it for anything else.
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
        iPhone. Settings → Backup → Delete account deletes your account and your family’s backed-up
        clips and voice notes from our servers. If someone else in your family also produces the
        film, what you added stays with the family’s film and is no longer linked to you.
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
