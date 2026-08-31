import { cookies } from "next/headers";
import { Endpoints } from "@/lib/api/endpoints";
import type { SessionResult } from "@/lib/models/auth";
import type { WriterPermissions, WriterWorkspace } from "@/lib/editorial/types";

type Envelope<T> = {
  success: boolean;
  result: T | null;
  error: { code?: string; message?: string } | null;
};

const emptyPerms = (): WriterPermissions => ({
  canWrite: false,
  canSubmit: false,
  canReview: false,
  canPublish: false,
  canManageWriters: false,
  canEditAny: false,
  canDelete: false,
});

function cookieHeader(jar: Awaited<ReturnType<typeof cookies>>) {
  return jar
    .getAll()
    .map((item) => `${item.name}=${item.value}`)
    .join("; ");
}

function apiOrigin() {
  return (
    process.env.API_PROXY_TARGET ||
    process.env.API_INTERNAL_URL ||
    "https://api.nichemusic.app"
  );
}

// pull the write board in one hop with the session cookie
export async function loadWriterWorkspace(): Promise<WriterWorkspace | null> {
  const jar = await cookies();
  if (!jar.get("session")) return null;

  const cookie = cookieHeader(jar);

  const res = await fetch(new URL(Endpoints.editorialMeWorkspace, `${apiOrigin()}/`), {
    cache: "no-store",
    headers: {
      cookie,
      "x-requested-via": "nichewebapp",
    },
  });

  if (res.status === 401) return null;

  const data = (await res.json()) as Envelope<Partial<WriterWorkspace>>;
  if (!res.ok || !data?.success || !data.result) {
    throw new Error(data?.error?.message || `Workspace failed (${res.status})`);
  }

  return {
    writer: data.result.writer ?? null,
    permissions: { ...emptyPerms(), ...data.result.permissions },
    articles: data.result.articles ?? [],
    queue: data.result.queue ?? [],
    catalog: data.result.catalog ?? [],
  };
}

// who is this cookie even
export async function loadSession(): Promise<SessionResult | null> {
  const jar = await cookies();
  if (!jar.get("session")) return null;

  const res = await fetch(new URL(Endpoints.session, `${apiOrigin()}/`), {
    cache: "no-store",
    headers: {
      cookie: cookieHeader(jar),
      "x-requested-via": "nichewebapp",
    },
  });

  if (res.status === 401 || res.status === 404) return null;

  const data = (await res.json()) as Envelope<SessionResult>;
  if (!res.ok || !data?.success || !data.result) return null;
  return data.result;
}
