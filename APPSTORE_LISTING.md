# GrowSense — App Store listing (ready to paste)

Everything App Store Connect asks for, written out. Copy each block into the
matching field. Fields only you can do (upload files, create the demo account,
hit Submit) are marked **[YOU]** at the bottom.

App: **GrowSense Life** · Bundle `com.growsense.growsense` · Apple ID `6790710624`

---

## App Information

**Name** (30 max) — already set
```
GrowSense Life
```

**Subtitle** (30 max)
```
Child growth & height tracker
```

**Primary category:** Health & Fitness
**Secondary category:** Medical *(optional; leave blank if you'd rather avoid the extra Medical scrutiny)*

**Support URL:** https://www.growsense.life/support
**Marketing URL:** https://www.growsense.life
**Privacy Policy URL:** https://www.growsense.life/privacy

---

## Version 1.5.0 — What's New
```
GrowSense Premium can now be started right in the app.
• Premium monthly or yearly, with Restore Purchases on any device
• Daily food, activity and sleep logging stays free and unlimited
• Read your analytics over 90 days or six months, not just the last 30
• Annotate a bone-age X-ray — mark the carpals and growth plates on the scan
• Save and share the visit-summary PDF and CSV export from your phone
• Confirmation before deleting a lab, measurement, puberty or illness record
• Fixes: bone-age assessments now save, and the tab bar clears the home indicator
```

<details><summary>Version 1.0.0 — What's New (superseded)</summary>

```
First release of GrowSense.
• Daily readiness score from nutrition, activity and sleep
• WHO percentile growth charts with an honest projected range
• Serial bone-age history with an AI second opinion
• Fast food, activity and sleep logging + wearable sync
• AI growth coach for sleep, nutrition and clinic prep
```
</details>

## Promotional Text (170 max — updatable anytime without review)
```
Everyday meals, sleep and activity become a clear picture of your child's growth — WHO percentiles, a daily readiness score, and a bone-age history for clinic visits.
```

## Description (paste as-is)
```
GrowSense turns everyday meals, play and sleep into a clear, honest picture of your child's growth — grounded in WHO growth standards and pediatric research, not hype.

Most growth worries come down to one question: is my child on track? GrowSense answers it calmly. Log food, activity and sleep in seconds and see a single daily readiness score, WHO percentile channels, and a height projection that blends genetics with daily habits — always labelling what's measured versus estimated, so you're never misled.

WHAT YOU CAN DO
• Daily readiness — nutrition, activity and sleep wrap into one score, with a plain-language insight on which lever to pull today.
• Growth trajectory — plot measurements on WHO percentile channels and see an honest projected range, not just dots on a chart.
• Bone-age history — keep every bone-age X-ray from every clinic in one timeline, annotate the scan, and bring the full story to your next consult. An optional AI reading offers an educational second opinion as a confidence range, never a diagnosis, and always asks to be confirmed by a pediatric radiologist.
• Fast logging — protein-first food and impact-aware activity libraries make daily consistency easy; sync sleep and activity from a connected wearable.
• AI growth coach — practical, sourced answers about sleep, nutrition, growth trends, puberty and clinic prep.
• Analytics — weekly trends, height velocity, and a logging-quality view that's honest about gaps.

BUILT ON HONESTY
GrowSense is not a calorie counter and never promises to "boost" height. Good habits help a child reach their own potential — the arc bends over years, not weeks. We label measured vs estimated data, cite our sources, and keep your family's health data private: it is never sold and never used for advertising.

FOR PARENTS, ABOUT CHILDREN
Accounts are created and managed by a parent or guardian. Your data is encrypted in transit, isolated to your account, and you can export or delete everything at any time.

GrowSense is educational and does not replace medical advice. For any growth concern, talk to your pediatrician.

GROWSENSE PREMIUM — SUBSCRIPTION
Logging food, activity and sleep every day is free, and stays free. Premium is for the long record: unlimited measurements and your full growth history, analytics over 90 days or six months, the bone-age AI second opinion, lab interpretation, and the visit-summary PDF.
• GrowSense Premium Monthly — US$4.99 per month
• GrowSense Premium Yearly — US$39.99 per year
Payment is charged to your Apple Account when you confirm the purchase. The subscription renews automatically unless auto-renew is turned off at least 24 hours before the end of the current period, and your account is charged for renewal within the 24 hours before the period ends. You can manage the subscription and turn off auto-renewal in your Apple Account settings after purchase. Prices are shown in your local currency at checkout.
Terms of Use: https://www.growsense.life/terms.html
Privacy Policy: https://www.growsense.life/privacy.html
```

> **Guideline 3.1.2** requires the subscription block above in the App Store
> description — title, length, price per period, and functional links to the
> Terms of Use (EULA) and Privacy Policy. The same disclosures are already in
> the binary on `screens/paywall_screen.dart`, which reads the price from
> `ProductDetails.price` so every storefront shows its own currency.

## Keywords (100 max, comma-separated)
```
child growth,height,percentile,bone age,pediatric,WHO growth chart,kids nutrition,sleep,tracker
```

---

## Age Rating (answer the questionnaire)
- All content questions → **None**.
- "Medical/Treatment Information" → **None** (the app tracks and educates; it doesn't diagnose or give treatment).
- Result should be **4+**.
- ⚠️ **Do NOT enable "Made for Kids" / the Kids Category.** GrowSense is used by parents *about* children — the Kids Category imposes strict COPPA rules you don't want.

## App Privacy (Data types → all: purpose **App Functionality**, **Linked to user: Yes**, **Used for tracking: No**)
"Do you or partners use data for tracking?" → **No**
- **Health & Fitness → Health** — growth measurements, medical records, bone-age
- **Health & Fitness → Fitness** — activity, sleep
- **Contact Info → Email Address** — your account email
- **Contact Info → Name** — child's name/nickname
- **Identifiers → User ID** — account id
- **Purchases → Purchase History** — subscription state. Apple handles the payment,
  but the backend stores the resulting entitlement (`apple_subscriptions`, keyed to
  `user_id`) so premium follows the account onto any device. That is purchase data
  linked to identity, so it is declared. Added for 1.5.0.
- (Diagnostics → Crash Data / Performance — only if you actually collect it; otherwise omit)
No Financial Info (no payment method, card or bank detail ever reaches the app —
the App Store handles payments), no Advertising Data.

## App Review Information
- **Sign-in required:** Yes → provide the demo account (below).
- **Notes for reviewer:**
```
GrowSense is used by a parent about their child. Sign in with the demo account provided.

WHERE THE IN-APP PURCHASES ARE (1.5.0)
The demo account is deliberately on the FREE tier so both subscriptions are reachable.
1. Tap the avatar at the top right of any tab to open Account.
2. The subscription card is the first card. Tap "Upgrade to Premium" to open the paywall,
   which lists GrowSense Premium Monthly and GrowSense Premium Yearly with the price,
   renewal terms, and links to our Terms of Use and Privacy Policy.
3. "Restore purchases" sits next to that button and works without buying anything.
The paywall is also reached from any locked feature: Medical tab → a bone-age record →
"AI second opinion", or Analytics → the 90-day / 6-month range selector. Each opens a
sheet whose "See subscription options" button goes to the same paywall.

WHAT PREMIUM CHANGES
Daily food, activity and sleep logging is free and unlimited. Premium lifts the free
account's five-measurement limit, opens the full growth history (free shows 30 days),
and enables the bone-age AI second opinion, the lab interpretation, and the visit PDF.

OTHER TABS
• Today: daily readiness score (nutrition, activity, sleep) and quick logging.
• Analytics: WHO percentile growth chart, height velocity, weekly trends.
• Medical: serial bone-age history; tap a scan to annotate the carpals and growth plates.
• AI coach: sourced answers about growth, sleep and nutrition.

The bone-age AI gives an educational second opinion as a confidence range, shows its
reasoning, never states a diagnosis, and asks on screen to be confirmed by a
board-certified pediatric radiologist.

Account deletion (Guideline 5.1.1(v)): Account → Delete account performs a full, immediate data erasure.
No special hardware needed. Wearable sync is optional and not required to review.
```

---

## 1.5.0 — In-App Purchase submission

Both subscriptions are **first-time products**, so they must be attached to the 1.5.0
version submission. Apple does not review a subscription on its own.

Subscription group **GrowSense Premium** (`22269568`):

| Product | Apple ID | Duration | US price |
|---|---|---|---|
| `life.growsense.premium.monthly` | 6795398618 | 1 month | $4.99 (฿149 / ₫99,000) |
| `life.growsense.premium.yearly` | 6795400758 | 1 year | $39.99 (฿999 / ₫699,000) |

Product localizations (display name / description — 45 and 45 char limits):

```
GrowSense Premium Monthly
Unlimited measurements, your full growth history, longer analytics windows, bone-age AI and the visit PDF.
```
```
GrowSense Premium Yearly
A year of Premium — unlimited measurements, full history, longer analytics, bone-age AI and the visit PDF.
```

Still to fill on each product: the **review screenshot** (one shot of the paywall from
TestFlight shows both products and satisfies both), and optionally a **7-day
introductory free trial** — an Introductory Offer needs no review and can be added
later, but it converts materially better.

---

## [YOU] — the only steps I can't do from here
1. **Capture the paywall screenshot** on the TestFlight build (Account → avatar →
   Upgrade to Premium) and hand it over for the two IAP review-screenshot fields.
2. **Demo account password** — App Review Information → Sign-In Information. The
   account is `peempatpi@gmail.com`, now on the free tier so the paywall is reachable.
   I never type passwords.
3. Decide the **7-day introductory trial** and whether to enable **Billing Grace
   Period** on the subscription group (currently off).
4. Click **Add for Review** → **Submit**.

Screenshots are already uploaded and current (real-device captures, iPhone 6.9"
1290×2796 + iPad 13" 2048×2732; every smaller bucket inherits them). Export
compliance no longer asks — `ITSAppUsesNonExemptEncryption=false` is in `Info.plist`.
