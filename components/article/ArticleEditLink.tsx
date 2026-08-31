"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { useSession } from "@/components/providers/SessionProvider";
import { getMyWriter } from "@/lib/editorial/api";
import styles from "./article.module.css";

export function ArticleEditLink({
  articleId,
  writerIds,
}: {
  articleId: string;
  writerIds: string[];
}) {
  const { status } = useSession();
  const [href, setHref] = useState<string | null>(null);
  const writerKey = writerIds.join(",");

  if (status !== "signedIn" && href !== null) {
    setHref(null);
  }

  useEffect(() => {
    if (status !== "signedIn") return;

    let cancelled = false;
    void (async () => {
      try {
        const me = await getMyWriter();
        const id = me.writer?.id;
        const ids = writerKey ? writerKey.split(",") : [];
        if (cancelled) return;
        if (me.permissions.canEditAny || (id && ids.includes(id) && me.permissions.canWrite)) {
          setHref(`/write/${articleId}`);
        } else {
          setHref(null);
        }
      } catch {
        if (!cancelled) setHref(null);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [articleId, status, writerKey]);

  if (!href) return null;

  return (
    <div className={styles.editBar}>
      <Link href={href} className={styles.editBtn}>
        Edit
      </Link>
    </div>
  );
}
