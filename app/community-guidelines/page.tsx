import { redirect } from "next/navigation";
import { buildPageMetadata } from "@/lib/site";

export const metadata = buildPageMetadata({
  title: "Community Guidelines",
  description: "Community guidelines for Niche Music.",
  path: "/guidelines",
});

export default function CommunityGuidelinesRedirect() {
  redirect("/guidelines");
}
