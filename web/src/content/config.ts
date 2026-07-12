import { defineCollection, z } from 'astro:content';

// One article = one Markdown file with structured frontmatter (the single
// source of truth). The layout renders hero, byline, share tags, and the
// References block. Inline citations in the body are literal
// <sup><a href="#rN">[N]</a></sup> anchors that point at the ids the
// References renderer assigns (r1..rN, numbered continuously across groups).
const articles = defineCollection({
  type: 'content',
  schema: z.object({
    title: z.string(), // <title> + og:title (SEO)
    h1: z.string(), // on-page headline
    description: z.string(), // meta description + og:description
    eyebrow: z.string(), // small kicker above the h1
    hero: z.string(), // hero image filename (lives in /blog/)
    heroAlt: z.string(),
    lang: z.string().default('en'),
    // Other-language versions of this article (for hreflang + the toggle).
    // Each page lists the OTHER languages; supports any number (EN/TH/ZH…).
    langAlts: z
      .array(z.object({ code: z.string(), href: z.string(), label: z.string() }))
      .optional(),
    disclaimer: z.string(),
    // Hub card (Growth Science index). Omit on translations so they don't
    // appear as separate cards. Order = position in the card grid.
    card: z
      .object({
        cat: z.string(),
        title: z.string(),
        blurb: z.string(),
        order: z.number(),
      })
      .optional(),
    // References: groups rendered in order; items numbered continuously so
    // #rN anchors stay stable. A group with no label just renders its items.
    references: z.array(
      z.object({
        group: z.string().optional(),
        items: z.array(z.string()), // full citation, may contain <em> etc.
      }),
    ),
  }),
});

export const collections = { articles };
