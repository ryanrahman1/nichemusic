import { LegalRoutePage, legalMetadata } from "@/lib/legal/page";

export async function generateMetadata() {
  return legalMetadata("standards", "Editorial Standards");
}

export default function StandardsPage() {
  return <LegalRoutePage slug="standards" />;
}
