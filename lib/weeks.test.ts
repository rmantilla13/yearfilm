import { test } from 'node:test'
import assert from 'node:assert/strict'
import { weeksLabel } from './weeks.ts'

test('weeks read like a person wrote them', () => {
  assert.equal(weeksLabel(null, null), 'from any week of the year')
  assert.equal(weeksLabel([30], 2026), 'from week 30 of 2026')
  assert.equal(weeksLabel([47, 48], 2026), 'from weeks 47–48 of 2026')
  assert.equal(weeksLabel([1, 2, 3, 10, 12, 13], 2026), 'from weeks 1–3, 10, 12–13 of 2026')
})
