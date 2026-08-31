"use client";

import type { ReactNode } from "react";
import { SessionProvider } from "@/components/providers/SessionProvider";

export function AppProviders({ children }: { children: ReactNode }) {
  return <SessionProvider>{children}</SessionProvider>;
}
