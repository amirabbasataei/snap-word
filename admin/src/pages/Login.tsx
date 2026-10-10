import { AlertCircle, Eye, EyeOff, Lock, User } from 'lucide-react'
import { useEffect, useState, type FormEvent } from 'react'
import { Navigate, useLocation } from 'react-router-dom'
import { useAuth } from '@/auth/AuthContext'
import { Logo } from '@/components/Logo'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'
import { ApiError, messageOf } from '@/lib/errors'
import { toFa } from '@/lib/fa'

function formatCountdown(sec: number): string {
  const m = Math.floor(sec / 60)
  const s = sec % 60
  return toFa(`${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`)
}

export function Login() {
  const { status, login } = useAuth()
  const location = useLocation()
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [show, setShow] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  // Seconds left of a server-imposed lockout (`Retry-After`); 0 = not locked.
  const [lockSec, setLockSec] = useState(0)

  useEffect(() => {
    if (lockSec <= 0) return
    const t = setTimeout(() => setLockSec((s) => s - 1), 1000)
    return () => clearTimeout(t)
  }, [lockSec])

  if (status === 'authed') {
    const from = (location.state as { from?: string } | null)?.from
    return <Navigate to={from && from !== '/login' ? from : '/'} replace />
  }

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    if (busy || lockSec > 0) return
    setBusy(true)
    setError(null)
    try {
      await login(username.trim(), password)
    } catch (err) {
      setError(messageOf(err))
      if (err instanceof ApiError && err.code === 'rate_limited' && err.retryAfter) setLockSec(err.retryAfter)
    } finally {
      setBusy(false)
    }
  }

  const locked = lockSec > 0
  return (
    <div className="grid min-h-screen place-items-center px-4 py-10">
      <div className="w-full max-w-md">
        <div className="mb-8 flex justify-center">
          <Logo className="scale-125" />
        </div>
        <div className="rounded-card border border-border bg-surface p-6 shadow-pop sm:p-8">
          <h1 className="text-xl font-semibold text-text">ورود به پنل مدیریت</h1>
          <p className="mt-1 text-sm text-muted">برای ادامه با حساب مدیریتی خود وارد شوید.</p>

          <form onSubmit={onSubmit} className="mt-6 flex flex-col gap-4" noValidate>
            {error && (
              <div role="alert" className="flex items-start gap-2.5 rounded-lg border border-pink bg-[color-mix(in_srgb,var(--pink)_12%,transparent)] p-3 text-sm text-text">
                <AlertCircle className="mt-0.5 size-4 shrink-0 text-pink" aria-hidden />
                <div>
                  <p>{error}</p>
                  {locked && (
                    <p className="tabular mt-1 text-xs text-muted">
                      زمان باقی‌مانده: <span dir="ltr">{formatCountdown(lockSec)}</span>
                    </p>
                  )}
                </div>
              </div>
            )}
            <Input
              label="نام کاربری"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              autoComplete="username"
              autoCapitalize="none"
              spellCheck={false}
             
              startAdornment={<User className="size-4" aria-hidden />}
              required
              autoFocus
            />
            <Input
              label="گذرواژه"
              type={show ? 'text' : 'password'}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              autoComplete="current-password"
             
              startAdornment={<Lock className="size-4" aria-hidden />}
              endAdornment={
                <button
                  type="button"
                  onClick={() => setShow((s) => !s)}
                  aria-label={show ? 'پنهان کردن گذرواژه' : 'نمایش گذرواژه'}
                  className="grid size-8 cursor-pointer place-items-center rounded-md text-muted hover:bg-active hover:text-text"
                >
                  {show ? <EyeOff className="size-4" aria-hidden /> : <Eye className="size-4" aria-hidden />}
                </button>
              }
              required
            />
            <Button type="submit" size="lg" loading={busy} disabled={locked || !username.trim() || !password} className="mt-1 w-full">
              ورود
            </Button>
          </form>
        </div>
        <p className="mt-6 text-center text-xs text-muted">دسترسی فقط برای مدیران مجاز است. فعالیت‌ها ثبت می‌شود.</p>
      </div>
    </div>
  )
}
