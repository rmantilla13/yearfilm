import { test } from 'node:test'
import assert from 'node:assert/strict'
import { parseSignup } from './waitlist.ts'

test('accepts and normalises an address', () => {
  assert.deepEqual(parseSignup({ email: '  Ana@Example.COM ' }), { ok: true, email: 'ana@example.com' })
})

test('accepts plus addressing and long TLDs', () => {
  assert.equal(parseSignup({ email: 'a+films@family.photography' }).ok, true)
})

test('refuses things that are not an address', () => {
  for (const email of ['', 'ana', 'ana@', '@x.com', 'ana@example', 'a b@x.com', 42, undefined]) {
    assert.equal(parseSignup({ email }).ok, false, String(email))
  }
})

test('refuses a filled honeypot', () => {
  assert.equal(parseSignup({ email: 'ana@example.com', website: 'http://spam' }).ok, false)
})

test('refuses a non-object body', () => {
  assert.equal(parseSignup(null).ok, false)
  assert.equal(parseSignup('ana@example.com').ok, false)
})
