import { test } from 'node:test'
import assert from 'node:assert/strict'
import { filmWeek, parseDay, parseDisplayName, parseFamilyName, parseInviteRequest, parseUploadRequest, pathFor, weekAllowed } from './media.ts'

const id = '0b4e7a52-6c1f-4a8e-9a3d-2f6b1c9e8d70'
const clip = { kind: 'footage', id, capturedOn: '2026-03-14', ext: 'MOV', byteSize: 120_000_000 }

test('accepts a clip and normalises the extension', () => {
  const r = parseUploadRequest(clip)
  assert.ok(r.ok)
  assert.equal(r.value.ext, 'mov')
  assert.equal(r.value.contentType, 'video/quicktime')
})

test('the path comes from the verified family, the id and the filmed year', () => {
  const r = parseUploadRequest(clip)
  assert.ok(r.ok)
  assert.equal(pathFor('fam', r.value), `fam/2026/original/${id}.mov`)
  const note = parseUploadRequest({ kind: 'voice_note', id, capturedOn: '2025-12-31', ext: 'm4a', byteSize: 90_000 })
  assert.ok(note.ok)
  assert.equal(pathFor('fam', note.value), `fam/2025/notes/${id}.m4a`)
})

test('nothing path-like gets through', () => {
  assert.equal(parseUploadRequest({ ...clip, id: '../../other-family/x' }).ok, false)
  assert.equal(parseUploadRequest({ ...clip, id: id.toUpperCase() }).ok, false)
  assert.equal(parseUploadRequest({ ...clip, ext: 'mov/../../x' }).ok, false)
  assert.equal(parseUploadRequest({ ...clip, capturedOn: '2026-03-14T23:00:00Z' }).ok, false)
})

test('kinds only take their own file types', () => {
  assert.equal(parseUploadRequest({ ...clip, ext: 'm4a' }).ok, false)
  assert.equal(parseUploadRequest({ ...clip, kind: 'voice_note', ext: 'mov' }).ok, false)
  assert.equal(parseUploadRequest({ ...clip, kind: 'film' }).ok, false)
})

test('sizes are checked', () => {
  assert.equal(parseUploadRequest({ ...clip, byteSize: 0 }).ok, false)
  assert.equal(parseUploadRequest({ ...clip, byteSize: 1.5 }).ok, false)
  assert.equal(parseUploadRequest({ ...clip, byteSize: 501 * 1024 ** 2 }).ok, false)
})

test('dates must be real calendar days', () => {
  assert.equal(parseDay('2026-02-30').ok, false)
  assert.equal(parseDay('1999-12-31').ok, false)
  assert.ok(parseDay('2028-02-29').ok || new Date().getUTCFullYear() < 2027)
})

test('family names are trimmed and bounded', () => {
  assert.deepEqual(parseFamilyName({ name: '  The   Garcias ' }), { ok: true, value: 'The Garcias' })
  assert.equal(parseFamilyName({ name: '   ' }).ok, false)
  assert.equal(parseFamilyName({ name: 'x'.repeat(81) }).ok, false)
})

test('film weeks match FilmWeek.swift', () => {
  assert.deepEqual(filmWeek('2026-01-01'), { year: 2026, week: 1 })
  assert.equal(filmWeek('2026-01-07').week, 1)
  assert.equal(filmWeek('2026-01-08').week, 2)
  assert.deepEqual(filmWeek('2026-12-31'), { year: 2026, week: 52 })
  assert.equal(filmWeek('2028-12-31').week, 52) // leap year
  assert.equal(filmWeek('2026-03-14').week, 11)
})

test('week-limited members only add their weeks of their year', () => {
  const limit = { weeks: [47, 48], year: 2026 }
  assert.ok(weekAllowed('2026-11-26', limit)) // Thanksgiving, week 48
  assert.equal(weekAllowed('2026-03-14', limit), false)
  assert.equal(weekAllowed('2025-11-26', limit), false)
  assert.ok(weekAllowed('2026-03-14', { weeks: null, year: null }))
})

test('invites never carry producer, and weeks need a year', () => {
  const year = new Date().getUTCFullYear()
  assert.equal(parseInviteRequest({ role: 'producer' }).ok, false)
  assert.deepEqual(parseInviteRequest({}), { ok: true, value: { role: 'contributor', weeks: null, year: null, days: 14 } })
  assert.equal(parseInviteRequest({ weeks: [3] }).ok, false)
  assert.equal(parseInviteRequest({ weeks: [0], year }).ok, false)
  assert.equal(parseInviteRequest({ weeks: [53], year }).ok, false)
  const r = parseInviteRequest({ weeks: [48, 47, 48], year })
  assert.ok(r.ok)
  assert.deepEqual(r.value.weeks, [47, 48])
})

test('display names are trimmed; empty clears', () => {
  assert.deepEqual(parseDisplayName({ displayName: '  Ana  ' }), { ok: true, value: 'Ana' })
  assert.deepEqual(parseDisplayName({ displayName: '' }), { ok: true, value: null })
  assert.equal(parseDisplayName({ displayName: 'x'.repeat(61) }).ok, false)
})
