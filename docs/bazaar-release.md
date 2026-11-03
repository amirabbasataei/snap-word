# Releasing Zanjir on Cafe Bazaar

State as of 2026-10-31. Items marked **YOU** need the Bazaar panel, the production server, or a phone — nothing here can be done from the repo.

## 1. What is already done in the repo

- **Release signing.** `client/android/app/build.gradle.kts` reads `client/android/key.properties` (gitignored). A release build **fails** without it instead of falling back to the debug key. Keystore: `~/keystores/zanjir-release.jks`, alias `zanjir`, valid ~33 years, SHA-256 `DF:F3:28:C2:DF:96:6A:25:FE:AC:C8:6F:3E:24:E8:54:D2:06:BE:ED:04:DF:89:35:13:C5:FF:60:CA:5C:8B:CE`.
  **Back up the `.jks` and `key.properties` somewhere off this machine.** Bazaar only accepts updates signed with the same key; if it is lost the app can never be updated.
- **Version** `1.0.0+5` (`pubspec.yaml`). Every upload to Bazaar needs a higher `+N`.
- **Real billing** (replaces the mock that showed «خرید با موفقیت انجام شد!» without charging): Poolakey on the client, the server verifies Bazaar's RSA signature on the purchase receipt, idempotent crediting. See CLAUDE.md § Cafe Bazaar billing.
- «Remove ads» is **not for sale** (the app has no ad-free state). Do not create that product.
- Legal pages (`/terms`, `/privacy`) already exist and are linked in the app.

## 2. Bazaar panel (pishkhan.cafebazaar.ir) — YOU

1. Create the app with package name **`com.ataei.zanjir`**.
2. **Products** (Bazaar panel → درون‌برنامه‌ای). Ids must match exactly:

   | Id | Type | Price (Toman) |
   |---|---|---|
   | `coins_100` | مصرفی (consumable) | ۹٬۰۰۰ |
   | `coins_350` | مصرفی | ۲۵٬۰۰۰ |
   | `coins_1500` | مصرفی | ۷۹٬۰۰۰ |
   | `premium_monthly` | اشتراک (subscription), monthly | ۱۹٬۰۰۰ |

   Bazaar prices are in Rial (×10). The in-app buy sheet shows the prices from `profile_sheets.dart`; keep them equal to the panel.
3. **RSA public key** (panel → درون‌برنامه‌ای → کلید RSA / RSA key): copy the base64 key. It is the app's *public* key, not a secret. There is no OAuth client to create; the key is all that is needed.
4. Put it on the server in `/opt/wordchain/.env` (root-only), then redeploy:
   ```
   BAZAAR_RSA_PUBLIC_KEY=MIIBIjANBgkq…
   ```
   `BAZAAR_PACKAGE_NAME` defaults to `com.ataei.zanjir`. Until the key is set `POST /payments/bazaar/verify` answers `503 payments_unavailable` and nothing is credited.
5. Paste the same key into `PoolakeyGateway.rsaKey` (`client/lib/core/services/billing_gateway.dart`) so Poolakey also rejects forged results on the device (optional; the server checks regardless). It must be the key of **this** app (`com.ataei.zanjir`).

## 3. Server — YOU

- `bash scripts/deploy_backend.sh` (migration `018_store_purchases` runs at startup).
- **OTP must be real before launch.** In `/opt/wordchain/.env` set `KAVENEGAR_API_KEY` and `KAVENEGAR_OTP_TEMPLATE=zanjir`, and make sure the admin panel switch «تنظیمات» is **on**. While it is off (or no key is set) anyone who knows a phone number can sign in as that player with `1111`. No real SMS has ever been delivered to a handset — send yourself one and confirm the template is approved before submitting the app.

## 4. Build

```
cd client
flutter build apk --release --split-per-abi      # arm64-v8a, armeabi-v7a, x86_64
# or one fat APK:
flutter build apk --release
```
Outputs in `client/build/app/outputs/flutter-apk/`. Upload the **arm64-v8a** and **armeabi-v7a** files (or the single fat APK, ~28 MB). Verify the signer before uploading:
`$ANDROID_HOME/build-tools/<ver>/apksigner verify --print-certs <apk>` → CN=Zanjir.

## 5. Test the money path before publishing — YOU

Bazaar only lets Poolakey buy for apps it knows, so upload the APK as a draft/beta first, install it on a phone that has the Bazaar app and a test account, then:

1. Sign in, Profile → coin pill → buy `coins_100`. Expect: Bazaar sheet → «۱۰۰ سکه به حسابت اضافه شد!», balance up by 100, purchase consumed (you can buy it again immediately).
2. Kill the app right after paying (before the toast) and reopen: the coins must still arrive (`restore`).
3. Buy `premium_monthly`: the crown + «اشتراک ویژه فعال است» appear.
4. On the server: `docker compose logs app | grep "store purchase"`. A `purchase_invalid` (400) for a payment you really made means the RSA key on the server is not the one of this app, or the receipt JSON field names differ from the ones below.

**How verification works / unverified assumptions:** Bazaar signs each purchase (`originalJson` + `dataSignature`, SHA1withRSA). The app sends both to the server, which checks the signature with `BAZAAR_RSA_PUBLIC_KEY` and reads `productId`, `purchaseToken`, `packageName`, `purchaseState` (0 = purchased), `developerPayload` and `purchaseTime` from the signed JSON (`backend/internal/service/bazaar.go`). Those JSON field names are Poolakey's/Bazaar's documented receipt fields but have not been seen against a real purchase. The receipt carries **no subscription expiry**: while Bazaar's app still lists the subscription as active the client re-reports it at sign-in and every resume, and each report keeps `premium_until` 72 h ahead (`config.PremiumReverifyWindow`); a lapsed subscription stops being reported and premium ends within 72 h. A modified client could replay an old signed receipt to keep premium (a cosmetic-only perk) — closing that needs Bazaar's developer API.

## 6. Store listing

Bazaar needs (check the panel for the current exact sizes): icon 512×512, a feature banner, 4+ phone screenshots, short and long description, category (بازی › کلمه), age rating, privacy-policy URL.

- Privacy policy: `https://amirabbasataei.ir/privacy` · Terms: `https://amirabbasataei.ir/terms`
- Screenshots: **YOU** (need a device/emulator with the release build): Home, an active game, game-over, Daily Challenge, leaderboard, profile.

**Short description**
> بازی زنجیرهٔ کلمه‌ها؛ با آخرین حرفِ کلمهٔ قبلی، کلمهٔ جدید بساز و با دوستانت رقابت کن.

**Long description**
> زنجیر یک بازی کلمه‌ای فارسی است: هر کلمه باید با آخرین حرفِ کلمهٔ قبلی شروع شود، کلمه‌ها تکراری نباشند و در فرهنگ لغت وجود داشته باشند.
>
> • تک‌نفره و بدون نیاز به ثبت‌نام، حتی بدون اینترنت
> • بازی با هوش مصنوعی در سه سطح آسان، متوسط و سخت
> • بازی آنلاین دو نفره با حریف واقعی و زنجیرهٔ مشترک
> • چالش روزانه با جدول امتیازات و جایزه برای نفرات برتر
> • جدول رتبه‌بندی هفتگی و همیشگی، دوستان و دعوت از آن‌ها
> • امتیاز سرعت، امتیاز ویژه برای کلمه‌های بلند و کمک‌های درون بازی
> • اشتراک ویژه با آواتارهای اختصاصی، نشان تاج و پیام‌های سریع در بازی
>
> ورود با شمارهٔ موبایل و کد تأیید پیامکی. خرید درون‌برنامه‌ای (سکه و اشتراک) اختیاری است و هیچ‌چیز برای بازی کردن اجباری نیست.

**What's new (v1.0.0)**
> نخستین نسخهٔ زنجیر در کافه‌بازار.

## 7. Known gaps to decide on (not fixed here)

- **Solo «continue with coins»** (`z_over_screen.dart`) spends from a local, non-persistent mock balance (100 coins per launch), not the server balance — it is effectively free and does not use coins a player bought. Needs a server spend endpoint.
- **No in-app account deletion** (the privacy page promises deletion by email within 30 days; no tooling exists).
- **Bazaar-only devices have no Google Play services**: FCM pushes will not arrive there and the app must keep working without them (Firebase init is already off the first-frame path; verify on a Google-free device).
- The lawyer-review list in CLAUDE.md § Legal Pages still applies, and Bazaar may ask for an enamad / developer verification.
- A premium purchase is not revoked on refund/cancel until it lapses naturally (validity is the expiry Bazaar reports at the last verify).
