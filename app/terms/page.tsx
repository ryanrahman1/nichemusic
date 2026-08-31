import { LegalRoutePage, legalMetadata } from "@/lib/legal/page";

export async function generateMetadata() {
  return legalMetadata("terms", "Terms of Service");
}

export default function TermsPage() {
  return <LegalRoutePage slug="terms" />;
}
