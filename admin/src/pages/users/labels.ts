import type { MatchKind } from '@/lib/users'

export const MATCH_KIND_LABEL: Record<MatchKind, string> = {
  solo: 'تک‌نفره / هوش مصنوعی (روی دستگاه)',
  versus: 'رودررو (۱ به ۱)',
  ai: 'هوش مصنوعی آنلاین',
  daily: 'چالش روزانه',
}

export const MATCH_STATUS_LABEL: Record<string, string> = {
  finished: 'تمام‌شده',
  active: 'در جریان',
  abandoned: 'رهاشده',
}

export const REWARD_KIND_LABEL: Record<string, string> = {
  referral_reward: 'پاداش دعوت',
  streak: 'پاداش روزهای پیاپی',
  weekly_rank: 'جدول هفتگی',
  daily_login: 'ورود روزانه',
  daily_done: 'شرکت در چالش روزانه',
  daily_rank: 'رتبهٔ چالش روزانه',
  admin_gift: 'هدیهٔ مدیر',
}
