import { buildPageMetadata } from "@/lib/site";

export const metadata = buildPageMetadata({
  title: "Log in",
  description: "Log in to Niche Music to write, review, and manage your profile.",
  path: "/login",
  noIndex: true,
});

export default function LoginLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return children;
}
