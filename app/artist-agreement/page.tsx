import { LegalRoutePage, legalMetadata } from "@/lib/legal/page";

export async function generateMetadata() {
  return legalMetadata("artist-agreement", "Artist Agreement");
}

export default function ArtistAgreementPage() {
  return <LegalRoutePage slug="artist-agreement" />;
}
