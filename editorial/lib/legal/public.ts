import { Endpoints } from "@/lib/api/endpoints";
import type { LegalDbSlug, LegalDocument } from "@/lib/legal/types";

type Envelope<T> = {
  success: boolean;
  result: T | null;
  error: { code?: string; message?: string } | null;
};

function apiOrigin() {
  return (
    process.env.API_PROXY_TARGET ||
    process.env.API_INTERNAL_URL ||
    "https://api.nichemusic.app"
  );
}

async function publicGet<T>(path: string): Promise<T> {
  const url = new URL(path, `${apiOrigin()}/`);
  const res = await fetch(url.toString(), {
    next: { revalidate: 60 },
    headers: { "x-requested-via": "nichewebapp" },
  });

  const data = (await res.json()) as Envelope<T>;
  if (!res.ok || !data?.success || !data.result) {
    throw new Error(data?.error?.message || `Request failed (${res.status})`);
  }
  return data.result;
}

export async function listLegalDocuments(): Promise<{
  documents: LegalDocument[];
  error?: string;
}> {
  try {
    return await publicGet<{ documents: LegalDocument[] }>(Endpoints.legalDocuments);
  } catch (error) {
    console.error("[legal] document list unavailable", error);
    return {
      documents: [] as LegalDocument[],
      error: "Legal documents are temporarily unavailable.",
    };
  }
}

export async function getLegalDocument(slug: LegalDbSlug) {
  return publicGet<{ document: LegalDocument }>(Endpoints.legalDocument(slug));
}
