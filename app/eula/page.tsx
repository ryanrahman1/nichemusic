import { LegalRoutePage, legalMetadata } from "@/lib/legal/page";

export async function generateMetadata() {
  return legalMetadata("eula", "EULA");
}

export default function EulaPage() {
  return <LegalRoutePage slug="eula" />;
}
