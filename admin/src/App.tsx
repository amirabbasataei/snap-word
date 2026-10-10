import { lazy, Suspense } from 'react'
import { Route, Routes } from 'react-router-dom'
import { RequireAuth } from '@/auth/RequireAuth'
import { AppLayout } from '@/layout/AppLayout'
import { PLACEHOLDERS } from '@/layout/nav'
import { Login } from '@/pages/Login'
import { NotFound } from '@/pages/NotFound'
import { Placeholder } from '@/pages/Placeholder'

// ECharts makes the dashboard the heaviest page; keep it out of the login bundle.
const Dashboard = lazy(() => import('@/pages/Dashboard').then((m) => ({ default: m.Dashboard })))

const Users = lazy(() => import('@/pages/Users').then((m) => ({ default: m.Users })))
const UserDetail = lazy(() => import('@/pages/UserDetail').then((m) => ({ default: m.UserDetail })))

// Dev-only: `import.meta.env.DEV` is a build-time constant, so the gallery is dropped from prod bundles.
const Kit = import.meta.env.DEV ? lazy(() => import('@/pages/Kit').then((m) => ({ default: m.Kit }))) : null

export function App() {
  return (
    <Routes>
      <Route path="/login" element={<Login />} />
      <Route element={<RequireAuth />}>
        <Route element={<AppLayout />}>
          <Route index element={<Suspense fallback={null}><Dashboard /></Suspense>} />
          <Route path="/users" element={<Suspense fallback={null}><Users /></Suspense>} />
          <Route path="/users/:id" element={<Suspense fallback={null}><UserDetail /></Suspense>} />
          {PLACEHOLDERS.map((p) => (
            <Route key={p.to} path={p.to} element={<Placeholder title={p.title} stage={p.stage} icon={p.icon} />} />
          ))}
          {Kit && (
            <Route path="/kit" element={<Suspense fallback={null}><Kit /></Suspense>} />
          )}
          <Route path="*" element={<NotFound />} />
        </Route>
      </Route>
    </Routes>
  )
}
