// Backend admin error codes are English (operator-only); the panel shows Persian.
const MESSAGES: Record<string, string> = {
  invalid_credentials: 'نام کاربری یا گذرواژه نادرست است.',
  rate_limited: 'تعداد تلاش‌های ناموفق زیاد بوده است. کمی بعد دوباره تلاش کنید.',
  csrf_required: 'درخواست نامعتبر است. صفحه را تازه‌سازی کنید.',
  admin_unauthorized: 'نشست شما منقضی شده است. دوباره وارد شوید.',
  invalid_admin_key: 'کلید دسترسی نامعتبر است.',
  insufficient_role: 'دسترسی لازم برای این کار را ندارید.',
  validation_error: 'اطلاعات واردشده معتبر نیست.',
  not_found: 'مورد درخواستی پیدا نشد.',
  internal_error: 'خطای داخلی سرور. کمی بعد دوباره تلاش کنید.',
  // client-side
  network_error: 'ارتباط با سرور برقرار نشد. اتصال اینترنت را بررسی کنید.',
  unknown_error: 'خطایی رخ داد. دوباره تلاش کنید.',
}

export function errorMessageFor(code: string | undefined | null): string {
  return (code && MESSAGES[code]) || MESSAGES.unknown_error
}

/** Error thrown by `api()` for any non-2xx response or network failure. */
export class ApiError extends Error {
  readonly status: number
  readonly code: string
  /** Seconds from `Retry-After`, when the server sent one. */
  readonly retryAfter?: number

  constructor(status: number, code: string, retryAfter?: number) {
    super(errorMessageFor(code))
    this.name = 'ApiError'
    this.status = status
    this.code = code
    this.retryAfter = retryAfter
  }
}

/** Persian text for anything thrown by the data layer. */
export function messageOf(err: unknown): string {
  if (err instanceof ApiError) return err.message
  return errorMessageFor('unknown_error')
}
