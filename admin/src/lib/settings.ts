import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { api } from './api'

export interface OtpStatus {
  /** The switch: real SMS delivery on (default) or off. */
  sms_enabled: boolean
  /** A Kavenegar API key is configured on the server. */
  provider_configured: boolean
  /** Codes are not sent and `dev_code` is accepted (switch off, or no provider). */
  bypass_active: boolean
  dev_code: string
  updated_at: string | null
  updated_by: string
}

const KEY = ['admin', 'settings', 'otp']

export function useOtpStatus() {
  return useQuery({
    queryKey: KEY,
    queryFn: ({ signal }) => api<OtpStatus>('/settings/otp', { signal }),
  })
}

export function useSetOtpSms() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (v: { enabled: boolean; reason: string }) =>
      api<OtpStatus>('/settings/otp', { method: 'PUT', body: { sms_enabled: v.enabled, reason: v.reason } }),
    onSuccess: (data) => qc.setQueryData(KEY, data),
  })
}
