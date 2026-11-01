import { buildPageMetadata } from "@/lib/site";

export const metadata = buildPageMetadata({
  title: "Write",
  description: "The Niche Music editorial desk.",
  path: "/write",
  noIndex: true,
});

export default function WriteLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return children;
}
