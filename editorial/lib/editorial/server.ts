import { cookies } from "next/headers";
import { Endpoints } from "@/lib/api/endpoints";
import type { SessionResult } from "@/lib/models/auth";
import type {
  OnboardingProfile,
  WriterPermissions,
  WriterWorkspace,
} from "@/lib/editorial/types";

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

const emptyWorkspace = (): WriterWorkspace => ({
  writer: null,
  permissions: emptyPerms(),
  articles: [],
  queue: [],
  catalog: [],
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
  if (
    data?.error?.code === "NOT_A_WRITER" ||
    data?.error?.code === "WRITER_NOT_FOUND"
  ) {
    return emptyWorkspace();
  }

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

// pull profile fields so writer onboarding starts mostly filled out
export async function loadOnboardingProfile(): Promise<OnboardingProfile | null> {
  const jar = await cookies();
  if (!jar.get("session")) return null;

  const res = await fetch(new URL(Endpoints.me, `${apiOrigin()}/`), {
    cache: "no-store",
    headers: {
      cookie: cookieHeader(jar),
      "x-requested-via": "nichewebapp",
    },
  });

  if (res.status === 401) return null;

  const data = (await res.json()) as Envelope<{
    user?: {
      username?: string | null;
      display_name?: string | null;
      bio?: string | null;
      location_name?: string | null;
    };
  }>;

  if (!res.ok || !data?.success || !data.result?.user) {
    throw new Error(data?.error?.message || `Profile failed (${res.status})`);
  }

  return {
    username: data.result.user.username ?? null,
    displayName: data.result.user.display_name ?? null,
    bio: data.result.user.bio ?? null,
    location: data.result.user.location_name ?? null,
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
