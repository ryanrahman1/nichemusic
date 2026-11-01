"use client";

import type { ReactNode } from "react";
import Link from "next/link";
import { useSession } from "@/components/providers/SessionProvider";
import { writerProfileHref } from "@/lib/editorial/writers";

// you hit /profile, everybody else hits the public writer page
export function WriterProfileLink({
  profileId,
  slug,
  className,
  children,
}: {
  profileId?: string | null;
  slug?: string | null;
  className?: string;
  children: ReactNode;
}) {
  const { user } = useSession();
  const href = writerProfileHref({
    profileId,
    slug,
    selfId: user?.id,
  });

  if (!href) return <span className={className}>{children}</span>;
  return (
    <Link href={href} className={className}>
      {children}
    </Link>
  );
}
