import { defineCollection, z } from 'astro:content';

// One article = one Markdown file with structured frontmatter (the single
// source of truth). The layout renders hero, byline, share tags, and refs.
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
    disclaimer: z.string(),
  }),
});

export const collections = { articles };
