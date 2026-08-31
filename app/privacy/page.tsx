import { LegalRoutePage, legalMetadata } from "@/lib/legal/page";

export async function generateMetadata() {
  return legalMetadata("privacy", "Privacy Policy");
}

export default function PrivacyPage() {
  return <LegalRoutePage slug="privacy" />;
}
