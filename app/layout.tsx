import type { Metadata, Viewport } from "next";
import { Inter } from "next/font/google";
import { AppProviders } from "@/components/providers/AppProviders";
import { JsonLd } from "@/components/JsonLd";
import { SiteFooter } from "@/components/SiteFooter";
import { mobileAppJsonLd, siteConfig, websiteJsonLd } from "@/lib/site";
import "./globals.css";

// inter is just for ui/forms — body/display stick to the system stack
const inter = Inter({
  subsets: ["latin", "latin-ext"],
  weight: "variable",
  style: ["normal", "italic"],
  variable: "--font-inter",
  display: "swap",
});

export const viewport: Viewport = {
  themeColor: siteConfig.themeColor,
  width: "device-width",
  initialScale: 1,
};

export const metadata: Metadata = {
  metadataBase: new URL(siteConfig.url),
  title: {
    default: siteConfig.title,
    template: `%s | ${siteConfig.name}`,
  },
  description: siteConfig.editorialDescription,
  keywords: [...siteConfig.keywords],
  authors: [{ name: siteConfig.author }],
  creator: siteConfig.author,
  publisher: siteConfig.author,
  robots: {
    index: true,
    follow: true,
  },
  alternates: {
    canonical: "/",
    types: {
      "application/rss+xml": "/feed.xml",
    },
  },
  openGraph: {
    ...siteConfig.openGraph,
    images: [...siteConfig.openGraph.images],
  },
  twitter: {
    ...siteConfig.twitter,
    images: siteConfig.twitter.images.map((image) => ({
      url: image.url,
      width: image.width,
      height: image.height,
      alt: image.alt,
    })),
  },
  icons: {
    icon: [{ url: "/favicon.png", type: "image/png" }],
    apple: [{ url: "/favicon.png", type: "image/png" }],
  },
  appleWebApp: {
    capable: true,
  },
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className={`${inter.variable} h-full antialiased`}>
      <head>
        {/* early + explicit so safari doesnt miss streamed metadata */}
        <meta name="apple-itunes-app" content={siteConfig.appleItunesApp} />
      </head>
      <body className="min-h-full flex flex-col">
        <JsonLd
          data={[
            websiteJsonLd as Record<string, unknown>,
            mobileAppJsonLd as Record<string, unknown>,
          ]}
        />
        <AppProviders>
          {children}
          <SiteFooter />
        </AppProviders>
      </body>
    </html>
  );
}
