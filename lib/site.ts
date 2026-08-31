import type { Metadata } from "next";

const siteUrl = "https://nichemusic.app";

const ogImage = {
  url: `${siteUrl}/assets/images/og-image.jpeg`,
  width: 1200,
  height: 630,
  alt: "Niche Music",
  type: "image/jpeg",
} as const;

export const siteConfig = {
  name: "Niche Music",
  title: "Niche Music",
  description:
    "The home of underground music.",
  editorialDescription:
    "The home of underground music.",
  url: siteUrl,
  author: "Niche Music, LLC",
  locale: "en_US",
  keywords: [
    "music discovery",
    "underground artists",
    "indie music",
    "social music app",
    "discover music",
    "independent artists",
    "music community",
    "new music",
    "music reviews",
    "artist spotlights",
    "underground music news",
  ],
  appleAppId: "6758951039",
  // smart app banner + app store link
  appleItunesApp: "app-id=6758951039",
  appStoreUrl: "https://apps.apple.com/app/id6758951039",
  themeColor: "#000000",
  ogImage,
  openGraph: {
    type: "website" as const,
    locale: "en_US",
    url: siteUrl,
    siteName: "Niche Music",
    title: "Niche Music",
    description:
      "The home of underground music.",
    images: [ogImage],
  },
  twitter: {
    card: "summary_large_image" as const,
    site: "@nichemusicapp",
    creator: "@nichemusicapp",
    title: "Niche Music",
    description:
      "The home of underground music.",
    images: [ogImage],
  },
} as const;

// same MobileApplication blob the old site put in the head
export const mobileAppJsonLd = {
  "@context": "https://schema.org",
  "@type": "MobileApplication",
  name: siteConfig.name,
  applicationCategory: "MusicApplication",
  operatingSystem: "iOS",
  description: siteConfig.description,
  url: siteConfig.url,
  downloadUrl: siteConfig.appStoreUrl,
  installUrl: siteConfig.appStoreUrl,
  publisher: {
    "@type": "Organization",
    name: siteConfig.author,
  },
} as const;

export const websiteJsonLd = {
  "@context": "https://schema.org",
  "@type": "WebSite",
  name: siteConfig.name,
  url: siteConfig.url,
  description: siteConfig.editorialDescription,
  potentialAction: {
    "@type": "SearchAction",
    target: `${siteConfig.url}/search?q={search_term_string}`,
    "query-input": "required name=search_term_string",
  },
  publisher: {
    "@type": "Organization",
    name: siteConfig.author,
    url: siteConfig.url,
  },
} as const;

type PageMetaInput = {
  title?: string;
  description?: string;
  path?: string;
  images?: {
    url: string;
    width?: number;
    height?: number;
    alt?: string;
    type?: string;
  }[];
  type?: "website" | "article";
  publishedTime?: string | null;
  authors?: string[];
  section?: string;
  tags?: string[];
  noIndex?: boolean;
};

function absUrl(url: string) {
  if (url.startsWith("http://") || url.startsWith("https://")) return url;
  return `${siteConfig.url}${url.startsWith("/") ? url : `/${url}`}`;
}

// build page meta that still carries the default og/twitter kit
export function buildPageMetadata({
  title,
  description,
  path = "/",
  images,
  type = "website",
  publishedTime,
  authors,
  section,
  tags,
  noIndex = false,
}: PageMetaInput = {}): Metadata {
  const pageTitle = title ?? siteConfig.title;
  const pageDescription = description ?? siteConfig.editorialDescription;
  const pageUrl = path.startsWith("http")
    ? path
    : `${siteConfig.url}${path.startsWith("/") ? path : `/${path}`}`;
  const socialTitle =
    pageTitle === siteConfig.title
      ? siteConfig.title
      : `${pageTitle} | ${siteConfig.name}`;
  const pageImages = images?.length
    ? images.map((image) => ({
        url: absUrl(image.url),
        width: image.width ?? ogImage.width,
        height: image.height ?? ogImage.height,
        alt: image.alt ?? pageTitle,
        type: image.type,
      }))
    : [
        {
          url: ogImage.url,
          width: ogImage.width,
          height: ogImage.height,
          alt: ogImage.alt,
          type: ogImage.type,
        },
      ];

  return {
    title:
      pageTitle === siteConfig.title
        ? { absolute: siteConfig.title }
        : pageTitle,
    description: pageDescription,
    authors: authors?.length ? authors.map((name) => ({ name })) : undefined,
    alternates: { canonical: path.startsWith("http") ? path : path },
    robots: noIndex ? { index: false, follow: false } : undefined,
    openGraph: {
      type,
      locale: siteConfig.openGraph.locale,
      siteName: siteConfig.openGraph.siteName,
      url: pageUrl,
      title: socialTitle,
      description: pageDescription,
      images: pageImages,
      ...(type === "article"
        ? {
            ...(publishedTime ? { publishedTime } : {}),
            ...(authors?.length ? { authors } : {}),
            ...(section ? { section } : {}),
            ...(tags?.length ? { tags } : {}),
          }
        : {}),
    },
    twitter: {
      card: "summary_large_image",
      site: siteConfig.twitter.site,
      creator: siteConfig.twitter.creator,
      title: socialTitle,
      description: pageDescription,
      images: pageImages.map((image) => ({
        url: image.url,
        width: image.width,
        height: image.height,
        alt: image.alt,
      })),
    },
  };
}
