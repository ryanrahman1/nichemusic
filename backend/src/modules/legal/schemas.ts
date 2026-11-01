import { z } from "zod"

export const legalDbSlugs = [
    "terms",
    "privacy",
    "eula",
    "artist-agreement",
    "guidelines",
    "standards",
] as const

export const legalSlugSchema = z
    .string()
    .trim()
    .min(1)
    .transform((value) => {
        const slug = value.toLowerCase()
        if (slug === "community-guidelines") return "guidelines"
        if (slug === "editorial-standards") return "standards"
        return slug
    })
    .refine((value) => legalDbSlugs.includes(value as (typeof legalDbSlugs)[number]), {
        message: "Unknown legal document",
    })
