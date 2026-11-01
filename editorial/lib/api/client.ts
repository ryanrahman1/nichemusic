import { clearCsrfCookie, getCsrfToken } from "@/lib/api/csrf";
import { Endpoints } from "@/lib/api/endpoints";
import { ApiError, type ApiEnvelope } from "@/lib/api/types";

const API_BASE =
  (process.env.NEXT_PUBLIC_API_URL as string | undefined) ||
  "https://api.nichemusic.app";

type RequestOptions = {
  method?: "GET" | "POST" | "PUT" | "PATCH" | "DELETE";
  body?: unknown;
  query?: Record<string, string | number | boolean | null | undefined>;
  raw?: boolean;
};

function buildUrl(
  path: string,
  query?: Record<string, string | number | boolean | null | undefined>,
) {
  let url: string;
  if (path.startsWith("http")) {
    url = path;
  } else {
    const base = API_BASE.endsWith("/") ? API_BASE.slice(0, -1) : API_BASE;
    const suffix = path.startsWith("/") ? path : `/${path}`;
    url = `${base}${suffix}`;
  }

  if (!query) return url;

  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(query)) {
    if (value === undefined || value === null) continue;
    params.set(key, String(value));
  }
  const qs = params.toString();
  return qs ? `${url}?${qs}` : url;
}

async function parseJson(res: Response): Promise<unknown> {
  const text = await res.text();
  if (!text) return null;
  try {
    return JSON.parse(text) as unknown;
  } catch {
    return null;
  }
}

// one fetch wrapper for cookies + csrf + envelope
export async function apiRequest<T>(
  path: string,
  options: RequestOptions = {},
): Promise<T> {
  const method = options.method ?? "GET";
  const isMutating = method !== "GET";
  const headers: Record<string, string> = {
    "x-requested-via": "nichewebapp",
  };

  if (options.body !== undefined) {
    headers["Content-Type"] = "application/json";
  }

  if (isMutating) {
    const csrf = getCsrfToken();
    if (csrf) headers["x-csrf-token"] = csrf;
  }

  const res = await fetch(buildUrl(path, options.query), {
    method,
    credentials: "include",
    headers,
    body:
      options.body !== undefined ? JSON.stringify(options.body) : undefined,
  });

  const data = await parseJson(res);

  if (!res.ok) {
    const envelope = data as ApiEnvelope<unknown> | null;
    const message =
      envelope?.error?.message ||
      (typeof data === "object" && data && "error" in data
        ? String((data as { error: unknown }).error)
        : `Request failed (${res.status})`);
    const code = envelope?.error?.code;
    throw new ApiError(message, res.status, code, envelope?.error?.details);
  }

  if (options.raw) return data as T;

  const envelope = data as ApiEnvelope<T> | null;
  if (envelope && typeof envelope === "object" && "success" in envelope) {
    if (!envelope.success) {
      throw new ApiError(
        envelope.error?.message || "Request failed",
        res.status,
        envelope.error?.code,
        envelope.error?.details,
      );
    }
    return envelope.result as T;
  }

  return data as T;
}

export async function apiLogout() {
  try {
    await apiRequest<{ success?: boolean }>(Endpoints.logout, {
      method: "POST",
      raw: true,
    });
  } finally {
    clearCsrfCookie();
  }
}
