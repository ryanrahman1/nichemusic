const CSRF_COOKIE = "csrfToken";

// grab the non-httponly csrf cookie for double-submit
export function getCsrfToken(): string | null {
  if (typeof document === "undefined") return null;

  const match = document.cookie
    .split(";")
    .map((part) => part.trim())
    .find((part) => part.startsWith(`${CSRF_COOKIE}=`));

  if (!match) return null;
  return decodeURIComponent(match.slice(CSRF_COOKIE.length + 1)) || null;
}

// logout doesnt clear csrf server-side on old sessions so we wipe it ourselves
export function clearCsrfCookie() {
  const secure =
    typeof window !== "undefined" && window.location.protocol === "https:";
  const domain =
    typeof window !== "undefined" &&
    (window.location.hostname === "nichemusic.app" ||
      window.location.hostname.endsWith(".nichemusic.app"))
      ? "; Domain=.nichemusic.app"
      : "";
  document.cookie = `${CSRF_COOKIE}=; Path=/; Max-Age=0; SameSite=Lax${secure ? "; Secure" : ""}${domain}`;
}
