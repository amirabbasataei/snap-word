import { describe, expect, it } from 'vitest'
import { ApiError, errorMessageFor, messageOf } from './errors'

const CODES = [
  'invalid_credentials', 'rate_limited', 'csrf_required', 'admin_unauthorized',
  'insufficient_role', 'validation_error', 'internal_error',
]

describe('errorMessageFor', () => {
  it.each(CODES)('has a Persian message for %s', (code) => {
    const msg = errorMessageFor(code)
    expect(msg).toMatch(/[؀-ۿ]/)
    expect(msg).not.toBe(errorMessageFor('some_unknown_code'))
  })
  it('falls back for unknown or missing codes', () => {
    expect(errorMessageFor('whatever')).toBe(errorMessageFor(undefined))
  })
})

describe('messageOf', () => {
  it('uses the ApiError message and never leaks raw errors', () => {
    expect(messageOf(new ApiError(401, 'invalid_credentials'))).toBe(errorMessageFor('invalid_credentials'))
    expect(messageOf(new Error('boom: SQL syntax'))).toBe(errorMessageFor('unknown_error'))
  })
})
