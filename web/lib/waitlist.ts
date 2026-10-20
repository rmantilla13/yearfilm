// What the waitlist accepts. Pure, so the form and the route agree and it can be tested.

export type Parsed = { ok: true; email: string } | { ok: false; error: string }

// Deliberately loose: one @, something on each side, a dot in the domain.
// Only a mail server can say an address is real; a strict pattern only refuses real ones.
const SHAPE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

export function parseSignup(body: unknown): Parsed {
  if (typeof body !== 'object' || body === null) return { ok: false, error: 'Expected a form.' }
  const { email, website } = body as Record<string, unknown>
  // Honeypot: a field people never see. Bots fill it in.
  if (typeof website === 'string' && website.trim() !== '') return { ok: false, error: 'Something went wrong.' }
  if (typeof email !== 'string') return { ok: false, error: 'Enter your email.' }
  const clean = email.trim().toLowerCase()
  if (clean.length > 254 || !SHAPE.test(clean)) return { ok: false, error: 'That email doesn’t look right.' }
  return { ok: true, email: clean }
}
