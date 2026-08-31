"use client";

import {
  createContext,
  use,
  useCallback,
  useEffect,
  useState,
  type ReactNode,
} from "react";
import { apiLogout, apiRequest } from "@/lib/api/client";
import { Endpoints } from "@/lib/api/endpoints";
import { ApiError } from "@/lib/api/types";
import type { LoginBody, LoginResult, SessionResult, SessionUser } from "@/lib/models/auth";

type AuthStatus = "loading" | "signedOut" | "signedIn";

type SessionContextValue = {
  status: AuthStatus;
  user: SessionUser | null;
  emailVerified: boolean;
  login: (body: LoginBody) => Promise<void>;
  logout: () => Promise<void>;
  refresh: () => Promise<void>;
};

const SessionContext = createContext<SessionContextValue | null>(null);

// boots session from cookie via /session
export function SessionProvider({ children }: { children: ReactNode }) {
  const [status, setStatus] = useState<AuthStatus>("loading");
  const [user, setUser] = useState<SessionUser | null>(null);
  const [emailVerified, setEmailVerified] = useState(false);

  const refresh = useCallback(async () => {
    try {
      const result = await apiRequest<SessionResult>(Endpoints.session);
      setUser(result.user);
      setEmailVerified(result.emailVerified);
      setStatus("signedIn");
    } catch (err) {
      if (err instanceof ApiError && (err.status === 401 || err.status === 404)) {
        setUser(null);
        setEmailVerified(false);
        setStatus("signedOut");
        return;
      }
      setUser(null);
      setEmailVerified(false);
      setStatus("signedOut");
    }
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  async function login(body: LoginBody) {
    await apiRequest<LoginResult>(Endpoints.loginEmailWeb, {
      method: "POST",
      body,
    });
    await refresh();
  }

  async function logout() {
    try {
      await apiLogout();
    } finally {
      setUser(null);
      setEmailVerified(false);
      setStatus("signedOut");
    }
  }

  return (
    <SessionContext.Provider
      value={{
        status,
        user,
        emailVerified,
        login,
        logout,
        refresh,
      }}
    >
      {children}
    </SessionContext.Provider>
  );
}

export function useSession() {
  const ctx = use(SessionContext);
  if (!ctx) throw new Error("useSession needs SessionProvider");
  return ctx;
}
