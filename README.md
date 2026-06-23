# GrowSense

Pediatric growth tracking app — single-file web app + Supabase backend.

**Live app:** https://cheetahokok-sudo.github.io/growsense/

## What's in this repo

| File | Purpose |
|---|---|
| `index.html` | The entire app — HTML/CSS/JS in one file. This is what GitHub Pages serves. |
| `growsense_schema.sql` | The Supabase database schema (tables, RLS policies, the growth-velocity view). Reference only — already applied to the live Supabase project. Re-running it would error on "table already exists." |

## How updates get deployed

There's no build step. GitHub Pages serves `index.html` directly.

1. Get an updated `index.html` (e.g. from a Claude conversation)
2. On this repo's GitHub page, click on `index.html`
3. Click the pencil icon (**Edit this file**) — or delete and re-upload via **Add file → Upload files**
4. If editing: select all, paste the new content, **Commit changes**
5. Wait ~30–60 seconds, then hard-refresh the live URL (Cmd/Ctrl+Shift+R, or add `?v=2` to the URL to bust cache)

## Recovering a previous version if something breaks

Every commit is saved automatically — nothing is ever lost by overwriting `index.html`.

1. Go to the repo → click **`index.html`**
2. Click **History** (clock icon, top right of the file view) — this lists every past version
3. Click any older commit → **View file** (or the `<>` button) to see that version's full content
4. To roll back: copy that old content, then repeat the edit/commit steps above to restore it as the current version

You can also click **Browse files at this point in history** in any commit view to see the whole repo as it existed then.

## Database

Schema lives in Supabase (project: `growsense`), not in this repo's data — `growsense_schema.sql` here is just a reference copy of what was run in the SQL Editor. The actual live data (children, daily logs, measurements) lives in Supabase's Postgres, not in git.

## Known incomplete areas (as of this snapshot)

- **Medical screen** (illness/medications/lab values) — not yet connected to any database table; entries are lost on reload
- **Lab markers chart** on Analytics — shows "not yet connected" placeholder, no backing table yet
- **Doctor/researcher sharing** (`shareChildWithDoctor`) — the email lookup likely needs a dedicated Postgres function (RPC) to work under current Row Level Security policies; not yet built
