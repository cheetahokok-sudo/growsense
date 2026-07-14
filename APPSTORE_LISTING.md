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

## Version 1.0.0 — What's New
```
First release of GrowSense.
• Daily readiness score from nutrition, activity and sleep
• WHO percentile growth charts with an honest projected range
• Serial bone-age history with an AI second opinion
• Fast food, activity and sleep logging + wearable sync
• AI growth coach for sleep, nutrition and clinic prep
```

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
• Bone-age history — keep every bone-age X-ray from every clinic in one timeline, with an AI second opinion, and bring the full story to your next consult.
• Fast logging — protein-first food and impact-aware activity libraries make daily consistency easy; sync sleep and activity from a connected wearable.
• AI growth coach — practical, sourced answers about sleep, nutrition, growth trends, puberty and clinic prep.
• Analytics — weekly trends, height velocity, and a logging-quality view that's honest about gaps.

BUILT ON HONESTY
GrowSense is not a calorie counter and never promises to "boost" height. Good habits help a child reach their own potential — the arc bends over years, not weeks. We label measured vs estimated data, cite our sources, and keep your family's health data private: it is never sold and never used for advertising.

FOR PARENTS, ABOUT CHILDREN
Accounts are created and managed by a parent or guardian. Your data is encrypted in transit, isolated to your account, and you can export or delete everything at any time.

GrowSense is educational and does not replace medical advice. For any growth concern, talk to your pediatrician.
```

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
- (Diagnostics → Crash Data / Performance — only if you actually collect it; otherwise omit)
No Financial Info (the App Store handles payments), no Advertising Data.

## App Review Information
- **Sign-in required:** Yes → provide the demo account (below).
- **Notes for reviewer:**
```
GrowSense is used by a parent about their child. Sign in with the demo account provided.
• Today tab: daily readiness score (nutrition, activity, sleep) and quick logging.
• Analytics tab: WHO percentile growth chart, height velocity, weekly trends.
• Medical tab: serial bone-age history with an AI second opinion.
• AI coach tab: sourced answers about growth, sleep and nutrition.
Account deletion (Guideline 5.1.1(v)): Account → Delete account performs a full, immediate data erasure.
No special hardware needed. Wearable sync is optional and not required to review.
```

---

## [YOU] — the only steps I can't do from here
1. **Upload the 6 screenshots** (`GS-S1`–`GS-S6.png`) to the 6.7" set (and duplicate/resize for 6.5" + iPad if you support iPad — the app is universal, so iPad shots are required). Drag them into the Media Manager.
2. **Create the reviewer demo account** in the app (a real login with ~7 days of sample data so it looks active), then paste its email + password into App Review Information → Sign-In Information.
3. **TestFlight → Export Compliance:** answer **No** to non-exempt encryption (standard HTTPS only).
4. **Attach the build** (run one fresh Codemagic build so the submitted build carries the new children icon + PrivacyInfo), then **Submit for Review**.
```
