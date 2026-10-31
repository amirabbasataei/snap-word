# Releasing Zanjir on Cafe Bazaar

State as of 2026-10-31. Items marked **YOU** need the Bazaar panel, the production server, or a phone — nothing here can be done from the repo.

## 1. What is already done in the repo

- **Release signing.** `client/android/app/build.gradle.kts` reads `client/android/key.properties` (gitignored). A release build **fails** without it instead of falling back to the debug key. Keystore: `~/keystores/zanjir-release.jks`, alias `zanjir`, valid ~33 years, SHA-256 `DF:F3:28:C2:DF:96:6A:25:FE:AC:C8:6F:3E:24:E8:54:D2:06:BE:ED:04:DF:89:35:13:C5:FF:60:CA:5C:8B:CE`.
  **Back up the `.jks` and `key.properties` somewhere off this machine.** Bazaar only accepts updates signed with the same key; if it is lost the app can never be updated.
- **Version** `1.0.0+5` (`pubspec.yaml`). Every upload to Bazaar needs a higher `+N`.
- **Real billing** (replaces the mock that showed «خرید با موفقیت انجام شد!» without charging): Poolakey on the client, server-side verification against Bazaar's developer API, idempotent crediting. See CLAUDE.md § Cafe Bazaar billing.
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
3. **Developer API client** (panel → تنظیمات → API): create a client, register an `https` redirect URI you control (localhost is rejected). Note the client id and secret.
4. **One-time refresh token** (the server refreshes access tokens itself afterwards):
   1. Open in a browser, logged in as the app owner:
      `https://pardakht.cafebazaar.ir/devapi/v2/auth/authorize/?response_type=code&access_type=offline&redirect_uri=<REDIRECT_URI>&client_id=<CLIENT_ID>`
   2. Approve; copy `code` from the redirect URL.
   3. `curl -s -X POST https://pardakht.cafebazaar.ir/devapi/v2/auth/token/ -d grant_type=authorization_code -d code=<CODE> -d client_id=<CLIENT_ID> -d client_secret=<SECRET> -d redirect_uri=<REDIRECT_URI>` → keep `refresh_token`.
5. Put these in `/opt/wordchain/.env` on the server (root-only), then redeploy:
   ```
   BAZAAR_CLIENT_ID=…
   BAZAAR_CLIENT_SECRET=…
   BAZAAR_REFRESH_TOKEN=…
   ```
   `BAZAAR_PACKAGE_NAME` defaults to `com.ataei.zanjir`. Until all three are set `POST /payments/bazaar/verify` answers `503 payments_unavailable` and nothing is credited.

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
4. On the server: `docker compose logs app | grep "store purchase"`. A `store_unavailable` / `purchase_invalid` for a payment you really made means one of the unverified API details below is wrong.

**Unverified assumptions** (taken from a community client; Bazaar's own docs are not machine-readable): the token endpoint, `GET …/devapi/v2/api/validate/{pkg}/inapp/{product}/purchases/{token}/` with a `purchaseState` field (0 = purchased), and `GET …/devapi/v2/api/applications/{pkg}/subscriptions/{product}/purchases/{token}/` with the expiry in `validUntilTimestampMsec`. If step 1 or 3 fails, compare with the official page <https://developers.cafebazaar.ir/en/guidelines/in-app-billing/api> and adjust `backend/internal/service/bazaar.go` (tests in `purchases_test.go` use a fake server that mirrors the same assumptions).

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
