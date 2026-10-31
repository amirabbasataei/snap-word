import { useState } from 'react'
import { useAuth } from '@/auth/AuthContext'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/Tabs'
import { roleAtLeast } from '@/layout/nav'
import { Compose } from './notifications/Compose'
import { History } from './notifications/History'
import { Reach } from './notifications/Reach'

export function Notifications() {
  const { admin } = useAuth()
  const canSend = admin ? roleAtLeast(admin.role, 'operator') : false
  const [tab, setTab] = useState('compose')

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-text">اعلان‌ها</h1>
        <p className="text-xs text-muted">
          ارسال اعلان فوری (Push) و پیام درون‌برنامه به همهٔ کاربران، یک گروه، یا کاربران مشخص. اعلان فوری فقط به کسانی می‌رسد که در برنامه اجازهٔ اعلان داده‌اند؛ پیام درون‌برنامه به همهٔ حساب‌های ثبت‌نام‌شده می‌رسد.
        </p>
      </div>
      <Tabs value={tab} onValueChange={setTab}>
        <TabsList className="overflow-x-auto">
          <TabsTrigger value="compose">ارسال اعلان</TabsTrigger>
          <TabsTrigger value="history">سابقهٔ ارسال</TabsTrigger>
          <TabsTrigger value="reach">وضعیت مجوز اعلان</TabsTrigger>
        </TabsList>
        <div className="pt-6">
          <TabsContent value="compose">
            <Compose canSend={canSend} onSent={() => setTab('history')} />
          </TabsContent>
          <TabsContent value="history">
            <History />
          </TabsContent>
          <TabsContent value="reach">
            <Reach />
          </TabsContent>
        </div>
      </Tabs>
    </div>
  )
}
