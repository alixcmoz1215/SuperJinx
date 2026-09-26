<div align="center">

# جینکس | 𝙎𝙪𝙥𝙚𝙧 𝗝𝗶𝗻𝗫

**پنل 3x-ui نسخه v2.9.4 — دیپلوی یک‌کلیکی روی Railway، بدون هیچ تنظیم دستی**

`3x-ui v2.9.4` · `VLESS + WebSocket + TLS` · `Auto Subscription` · `Protected Inbound` · `Railway Ready`

</div>

---

## ✨ امکانات

- 🚀 **فقط Deploy بزن**: پنل، اینباند و ساب‌لینک همه خودکار ساخته میشن
- 🌐 **دامنه خودکار**: دامنه‌ای که Railway میده خودش تشخیص داده میشه و داخل کانفیگ و ساب قرار می‌گیره
- 🔌 **فقط یک پورت (8080)**: پنل، کانفیگ و ساب‌لینک همه از همون دامنه روی 443 کار می‌کنن
- 🔒 **اینباند محافظت‌شده**: اینباند «جینکس | 𝙎𝙪𝙥𝙚𝙧 𝗝𝗶𝗻𝗫» قابل **حذف، تغییر نام، غیرفعال‌سازی یا ویرایش** نیست (سه لایه محافظت: مسدودسازی API، قفل دیتابیس، و بازسازی خودکار)
- 🔗 **ساب‌لینک آماده**: بدون ورود به تنظیمات، ساب‌لینک فعال و درست کار می‌کنه
- ⚡ **تنظیمات بهینه برای پینگ**: WS + TLS با fingerprint کروم، ALPN http/1.1، Sniffing فعال
- ♻️ **خودترمیم**: اگه پنل کرش کنه یا تنظیمات حیاتی تغییر کنه، خودش درست میشه

---

## 🚀 آموزش دیپلوی (۲ دقیقه)

1. این ریپو رو **Fork** کن (یا فایل‌ها رو توی یک ریپوی جدید آپلود کن)
2. وارد [Railway](https://railway.com) شو ← **New Project** ← **Deploy from GitHub repo** ← ریپو رو انتخاب کن
3. بعد از شروع بیلد، برو **Settings ← Networking ← Generate Domain**
   (پورت خودش **8080** تشخیص داده میشه، لازم نیست چیزی تایپ کنی)
4. اگه دامنه رو بعد از اولین دیپلوی ساختی، یک بار **Redeploy** بزن تا دامنه داخل کانفیگ بشینه
5. تمام! وارد پنل شو:

| مورد | آدرس |
|---|---|
| 🖥 پنل | `https://YOUR-DOMAIN.up.railway.app/` |
| 🔗 ساب‌لینک | `https://YOUR-DOMAIN.up.railway.app/sub/jinx` |
| 👤 یوزر / پسورد پیش‌فرض | `admin` / `admin` |

> کانفیگ رو از بخش **Inbounds** بگیر یا مستقیم ساب‌لینک رو داخل v2rayNG / Hiddify / Streisand / NekoBox بزن.
> لینک کامل کانفیگ و ساب داخل **Deploy Logs** هم چاپ میشه.

---

## ⚙️ متغیرها (همه اختیاری)

از بخش **Variables** در Railway:

| متغیر | پیش‌فرض | توضیح |
|---|---|---|
| `PANEL_USERNAME` | `admin` | یوزرنیم پنل |
| `PANEL_PASSWORD` | `admin` | پسورد پنل (**حتماً عوضش کن**) |
| `JINX_UUID` | `df70a084-...-3a0f41903f3a` | UUID کلاینت اصلی |
| `JINX_SUB_ID` | `jinx` | آیدی ساب‌لینک ← `/sub/jinx` |
| `DOMAIN` | دامنه Railway | فقط اگه دامنه اختصاصی وصل کردی |

> ⚠️ اسم اینباند عمداً قابل تنظیم نیست و همیشه «جینکس | 𝙎𝙪𝙥𝙚𝙧 𝗝𝗶𝗻𝗫» می‌مونه.

---

## 💾 ذخیره دائمی اطلاعات (پیشنهادی)

بدون Volume، با هر Redeploy کاربرای اضافه پاک میشن (اینباند اصلی همیشه خودکار برمی‌گرده).
برای ذخیره دائمی: روی سرویس راست‌کلیک ← **Attach Volume** ← مسیر: `/etc/x-ui`

---

## 📶 نکته پینگ

ریجن سرویس رو از **Settings ← Region** روی نزدیک‌ترین ریجن اروپا (مثلاً **EU West / Amsterdam**) بذار. معمولاً بهترین پینگ رو برای ایران میده.

---

## 🧩 مشخصات کانفیگ

```
Protocol : VLESS        Transport : WebSocket
Security : TLS (443)    ALPN      : http/1.1
Fingerprint : chrome    Path      : /ws/<UUID>
Host / SNI  : دامنه Railway
```

## 🏗 معماری

```
Client ──TLS 443──▶ Railway Edge ──▶ :8080 nginx ─┬─ /ws/<uuid>  → Xray (VLESS/WS/TLS)
                                                  ├─ /sub/jinx   → ساب‌لینک اصلی
                                                  ├─ /sub/*      → ساب داخلی 3x-ui
                                                  └─ /           → پنل 3x-ui
```

---

## 📜 English

**JinX | Super JinX** is a zero-touch Railway edition of [3x-ui v2.9.4](https://github.com/MHSanaei/3x-ui/releases/tag/v2.9.4).
Deploy → Generate Domain (port 8080 auto-detected) → open the panel. A protected VLESS/WS/TLS inbound and a working subscription link (`/sub/jinx`) are created automatically. The inbound cannot be deleted, renamed, disabled or edited from the panel. Default login `admin/admin`, change it via `PANEL_PASSWORD`.

---

## ❤️ Credits & License

- پنل اصلی: [MHSanaei/3x-ui](https://github.com/MHSanaei/3x-ui) تحت لایسنس **GPL-3.0**
- این پروژه یک wrapper رایگان و متن‌باز هست و تحت همان لایسنس GPL-3.0 منتشر میشه.
- استفاده مسئولانه و مطابق قوانین به عهده کاربره.

<div align="center">

**Made with 💜 by جینکس | 𝙎𝙪𝙥𝙚𝙧 𝗝𝗶𝗻𝗫**

</div>
