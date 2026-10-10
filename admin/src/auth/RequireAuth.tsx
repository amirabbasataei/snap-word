import { Navigate, Outlet, useLocation } from 'react-router-dom'
import { Skeleton } from '@/components/ui/Skeleton'
import { useAuth } from './AuthContext'

export function RequireAuth() {
  const { status } = useAuth()
  const location = useLocation()

  if (status === 'loading') {
    return (
      <div className="grid min-h-screen place-items-center" role="status" aria-label="در حال بارگذاری">
        <Skeleton className="h-10 w-40" />
      </div>
    )
  }
  if (status === 'anon') return <Navigate to="/login" replace state={{ from: location.pathname + location.search }} />
  return <Outlet />
}
