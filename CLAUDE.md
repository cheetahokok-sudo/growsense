\# GrowSense — Project Brief for Claude Code



\## What this is

Pediatric growth intelligence PWA + future Flutter app.

Live at: https://www.growsense.life

Repo: https://github.com/cheetahokok-sudo/growsense



\## Tech stack

\- Frontend: Vanilla JS PWA, GitHub Pages

\- Backend: Supabase (ogpkmcqaulohexanucng.supabase.co, Singapore)

\- Fonts: Inter, Fraunces, Sarabun (Thai)

\- CSS variables design system — never use hardcoded hex colours



\## File structure

\- index.html              — all HTML, modal definitions, tab structure

\- app.js                  — all JS logic (\~7300 lines), global APP state object

\- food-reference-data.js  — 90 food presets with region + category fields

\- style.css               — main stylesheet with CSS variables

\- who-reference-data.js   — WHO growth percentile data



\## Brand colours (CSS variables)

\--accent: #2F6B4F (green, CTAs)

\--deep-green: #0E2A20 (hero backgrounds)

\--measured: #2A5C8A (blue, confirmed data only)

\--estimated: #9C7A3D (gold, forecasts only)

\--flag: #A23B3B (red, alerts only)



\## Architecture rules

\- 5-tab nav: Today | Food | Activity | Analytics | Medical

\- APP object is global state — check existing pattern before adding state

\- All modals use modal-overlay + modal-sheet pattern

\- Activity tiers: high\_impact 1.0, weight\_bearing 0.65, cardio 0.35, flexibility 0.15

\- Food items have: id, name, emoji, region, category, per100g, servingGrams, source

\- Food regions: global, cn, kr, ae, th, vn, us, eu

\- Food categories: chicken, beef, pork, fish, seafood, egg, dairy, plant, composite



\## Target markets

Thailand (primary), Vietnam, South Korea, UAE, Taiwan, Hong Kong



\## Supabase tables (key ones)

\- children, daily\_nutrition, nutrition\_log\_items

\- daily\_activity\_items, custom\_activities, favorite\_activities

\- daily\_sleep, measurements (growth), custom\_foods, favorite\_foods



\## Current state

\- Food library: 90 presets, browse modal with search + category tabs + log button

\- Activity browser: 30 activities, tier filter tabs

\- Journal tab: not yet built

\- Flutter app: not yet started



\## Rules — never break these

\- Never use hardcoded hex colours — always CSS variables

\- Never break the modal-overlay + modal-sheet pattern

\- Never add inline style blocks to index.html

\- Always use local-time date constructors for Bangkok UTC+7

\- Always test changes against the existing APP global state structure

\- Commit after every completed feature

