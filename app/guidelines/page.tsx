import { LegalRoutePage, legalMetadata } from "@/lib/legal/page";

export async function generateMetadata() {
  return legalMetadata("guidelines", "Community Guidelines");
}

export default function GuidelinesPage() {
  return <LegalRoutePage slug="guidelines" />;
}
