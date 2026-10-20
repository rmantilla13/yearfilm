import Link from 'next/link'
import { MemoryPool } from './MemoryPool'
import { WaitlistForm } from './WaitlistForm'

// One frame per week, tinted by season within the pool's blues, so the strip reads as a year going by.
const SEASONS: [number, string, string][] = [
  [9, '#13243f', '#6f9fd8'],   // winter
  [22, '#0f3036', '#5fc4bd'],  // spring
  [35, '#123754', '#8fd6ff'],  // summer
  [48, '#1d2649', '#8f9de6'],  // fall
  [53, '#241d42', '#bfb0ff'],  // holidays
]
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

function frames() {
  return Array.from({ length: 52 }, (_, i) => {
    const week = i + 1
    const [, a, b] = SEASONS.find(([end]) => week < end) ?? SEASONS[SEASONS.length - 1]
    const month = MONTHS[Math.min(11, Math.floor((i * 12) / 52))]
    return { week, label: `${month} · wk ${week}`, bg: `linear-gradient(135deg, ${a}, ${b})` }
  })
}

const CHAPTERS = [
  ['00:00', 'Cold open', 'The year’s best moments, cut to the beat'],
  ['01:30', 'Winter', 'Snow days, your voice over the montage'],
  ['07:10', 'Spring', 'First steps, birthday candles, the garden'],
  ['13:40', 'Summer', 'The road trip, played with its own sound'],
  ['20:05', 'Fall', 'Back to school, Halloween, the long dinners'],
  ['26:20', 'The Holidays', 'Where this year’s film ends — and next year’s begins'],
  ['31:00', 'Credits', 'Starring everyone you love'],
]

export default function Home() {
  const strip = frames()
  return (
    <>
      <div className="wrap">
        <nav className="nav">
          <Link href="/" className="mark">
            year<span>film</span>
          </Link>
          <a className="small" href="#how">
            How it works
          </a>
        </nav>

        <header className="hero">
          <MemoryPool />
          <div className="hero-copy">
            <p className="eyebrow">Premiering on the holidays</p>
            <h1>
              Your family’s year, made into <em>a film</em>.
            </h1>
            <p className="lede">
              Film a little every week. In December, sit down together and watch the movie of your
              year — cut, scored, and narrated in your own words.
            </p>
            <WaitlistForm />
          </div>
        </header>

        <div className="reel" aria-hidden="true">
          <div className="strip">
            {[...strip, ...strip].map((f, i) => (
              <div key={i} className="frame" style={{ background: f.bg }}>
                {f.label}
              </div>
            ))}
          </div>
        </div>

        <section id="how">
          <h2>Fifty-two weeks. One premiere.</h2>
          <p className="sub">
            You don’t edit anything. You just keep filming the life you’re already living, and we
            make it into something worth sitting down for.
          </p>
          <div className="steps">
            <div className="step">
              <h3>Film every week</h3>
              <p>
                A gentle nudge each week with a shot to try — the first snow, a reaction, one wide
                shot of where you are. Add a few clips. That’s it.
              </p>
            </div>
            <div className="step">
              <h3>Say what happened</h3>
              <p>
                Record twenty seconds: “What happened this week?” By December, those notes are the
                narration — the story told by the people who lived it.
              </p>
            </div>
            <div className="step">
              <h3>Premiere night</h3>
              <p>
                Your film unlocks for the holidays. Put it on the TV, gather everyone, and watch
                the year come back.
              </p>
            </div>
          </div>
        </section>

        <section>
          <h2>Not a slideshow. A film.</h2>
          <p className="sub">
            Real chapters, real scenes with their own sound, and montages cut on the beat — the way
            a documentary is made.
          </p>
          <ol className="chapters">
            {CHAPTERS.map(([t, n, d]) => (
              <li key={n}>
                <span className="t">{t}</span>
                <span className="n">{n}</span>
                <span className="d">{d}</span>
              </li>
            ))}
          </ol>
        </section>

        <section>
          <div className="features">
            <div className="feature">
              <h3>Made for the TV</h3>
              <p>Widescreen, steady volume, chapter by chapter. Phone footage that looks right on the big screen.</p>
            </div>
            <div className="feature">
              <h3>Scored to your year</h3>
              <p>Music chosen for each season, with every cut landing on the beat and the music dipping when someone speaks.</p>
            </div>
            <div className="feature">
              <h3>The whole family films</h3>
              <p>Invite grandparents, siblings, partners. Everyone’s footage, one film.</p>
            </div>
            <div className="feature">
              <h3>Private by default</h3>
              <p>Your footage is yours. Nothing is public, nothing is sold, and you can delete everything at any time.</p>
            </div>
          </div>
        </section>

        <section className="closing">
          <h2>Next year’s film starts in January.</h2>
          <p className="sub">Join the waitlist and be ready to film from week one.</p>
          <WaitlistForm cta="Save my seat" />
        </section>
      </div>

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
