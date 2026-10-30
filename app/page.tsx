import Link from 'next/link'
import { Countdown } from './Countdown'
import { MemoryPool } from './MemoryPool'
import { WaitlistForm } from './WaitlistForm'
import { YearStory } from './YearStory'

// Clips from across a year, rising into the pool in the bulk-import band.
const RISING = [
  ['Jan 3', '#6f9fd8'], ['Feb 14', '#7fb3e6'], ['Mar 30', '#5fc4bd'], ['May 9', '#6fd1b8'],
  ['Jun 21', '#8fd6ff'], ['Jul 4', '#a3dcff'], ['Aug 17', '#8fc4f2'], ['Sep 2', '#8f9de6'],
  ['Oct 31', '#a49be8'], ['Nov 26', '#b6a6f0'],
]

// The film's running order, as a timeline under the premiere screen.
const CHAPTERS: [string, string, string][] = [
  ['00:00', 'Cold open', 'The year’s best moments, cut to the beat'],
  ['01:30', 'Winter', 'Snow days, your voice over the montage'],
  ['07:10', 'Spring', 'First steps, birthday candles, the garden'],
  ['13:40', 'Summer', 'The road trip, played with its own sound'],
  ['20:05', 'Fall', 'Back to school, Halloween, the long dinners'],
  ['26:20', 'The Holidays', 'Where this year’s film ends'],
  ['31:00', 'Credits', 'Starring everyone you love'],
]

const FAQ: [string, string][] = [
  [
    'Do I have to edit anything?',
    'No. You film and add clips; Yearfilm finds the moments worth keeping, cuts them on the beat of the music, and lays your voice notes over each season as the narration.',
  ],
  [
    'When is the film ready?',
    'On December 20, for every family at once, so you can watch it together over the holidays. You can watch a rough cut of the year so far whenever you like.',
  ],
  [
    'Where are my videos kept?',
    'On your iPhone. If you turn on backup, or make the film with family, they go to your own iCloud, in your storage, under your Apple ID. Yearfilm runs no server that holds your videos.',
  ],
  [
    'Can the rest of the family add their clips?',
    'Yes. Invite the people you choose and their clips from that year join your film through iCloud. They need an iPhone with Yearfilm, and their clips count toward your iCloud storage.',
  ],
  [
    'I already filmed most of this year. Is it too late?',
    'Not at all. Pick everything at once and each clip is filed under the week it was filmed, read from the video itself. Anything you’ve already added is skipped.',
  ],
]

export default function Home() {
  return (
    <>
      <header className="hero">
        <MemoryPool centerY={0.48} />
        <nav className="nav wrap">
          <Link href="/" className="mark">
            year<span>film</span>
          </Link>
          <a className="small" href="#how">How it works</a>
        </nav>
        <div className="hero-body wrap">
          <p className="eyebrow">For iPhone · Premiering December 20</p>
          <h1>
            Your family’s year, made into <em>a film</em>.
          </h1>
          <div className="hero-card">
            <p className="lede">
              Film a little every week. In December, sit down together and watch the movie of
              your year — cut, scored, and narrated in your own words.
            </p>
            <WaitlistForm />
          </div>
        </div>
        <a className="scroll-cue" href="#how" aria-label="See how it works">
          <span>A year, in four moments</span>
          <i aria-hidden="true" />
        </a>
      </header>

      <main className="wrap">
        <YearStory />

        <section className="rise">
          <div className="rise-pool" aria-hidden="true">
            {RISING.map(([day, tint], i) => (
              <span key={day} className="rise-clip" style={{ '--i': i, '--tint': tint } as React.CSSProperties}>
                {day}
              </span>
            ))}
            <span className="rise-glow" />
          </div>
          <div className="rise-copy">
            <p className="eyebrow">Already filming</p>
            <h2>Bring the whole year in at once.</h2>
            <p className="sub">
              Choose a few hundred videos from your library. Each one floats into the pool and
              settles in the week it was filmed, read from the video itself. Anything you’ve already
              added is skipped, and nothing else from your library is ever touched.
            </p>
          </div>
        </section>

        <section className="premiere">
          <p className="eyebrow">Premiere night</p>
          <h2>Not a slideshow. A film.</h2>
          <p className="sub">
            Real chapters, scenes that keep their own sound, montages cut on the beat — the way a
            documentary is made. Then everyone sits down on the same night.
          </p>
          <div className="screen" aria-hidden="true">
            <MemoryPool centerY={0.5} />
            <div className="screen-title">
              <small>A Yearfilm</small>
              <span>The Garcias</span>
              <small>2026</small>
            </div>
          </div>
          <ol className="timeline">
            {CHAPTERS.map(([time, name, about]) => (
              <li key={name}>
                <span className="t-time">{time}</span>
                <span className="t-name">{name}</span>
                <span className="t-about">{about}</span>
              </li>
            ))}
          </ol>
          <p className="premiere-date">
            <span className="m-eyebrow">December 20</span>
            <Countdown />
          </p>
        </section>

        <section className="trio">
          <div className="trio-item">
            <p className="eyebrow">Made for the TV</p>
            <h3>Phone footage, big-screen ready.</h3>
            <p>Widescreen and steady in volume, chapter by chapter. Vertical clips are framed for the TV, not squeezed between black bars.</p>
          </div>
          <div className="trio-item">
            <p className="eyebrow">Scored to your year</p>
            <h3>Every cut on the beat.</h3>
            <p>Music chosen for each season, with the music dipping whenever someone speaks — so the voices carry the story.</p>
          </div>
          <div className="trio-item">
            <p className="eyebrow">The whole family films</p>
            <h3>Everyone’s footage, one film.</h3>
            <p>Grandparents, siblings, partners: the people you invite add their clips from the year, and they become part of your film.</p>
          </div>
        </section>

        <section className="promise">
          <span className="promise-mark" aria-hidden="true" />
          <p className="eyebrow">Your footage stays yours</p>
          <h2>On your iPhone. In your iCloud. Nowhere else.</h2>
          <p className="sub">
            Your clips and voice notes live on your iPhone. Backup and family sharing go through
            your own iCloud, under your Apple ID. Yearfilm runs no server that holds your videos —
            there’s nothing of yours on ours to lose, sell, or leak.
          </p>
          <Link className="small-link" href="/privacy">Read the privacy policy →</Link>
        </section>

        <section className="faq">
          <h2>Questions</h2>
          {FAQ.map(([q, a]) => (
            <details key={q}>
              <summary>{q}</summary>
              <p>{a}</p>
            </details>
          ))}
        </section>

        <section className="closing">
          <MemoryPool centerY={0.55} />
          <span className="closing-mark" aria-hidden="true" />
          <h2>Next year’s film starts in January.</h2>
          <p className="sub">Join the waitlist and be ready to film from week one.</p>
          <WaitlistForm cta="Save my seat" />
        </section>
      </main>

      <footer>
        <div className="wrap row">
          <span>© {new Date().getFullYear()} Yearfilm</span>
          <nav>
            <Link href="/privacy">Privacy</Link>
            <Link href="/support">Support</Link>
          </nav>
        </div>
      </footer>
    </>
  )
}
