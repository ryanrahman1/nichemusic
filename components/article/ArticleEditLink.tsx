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

  useEffect(() => {
    if (status !== "signedIn") {
      setHref(null);
      return;
    }

    void (async () => {
      try {
        const me = await getMyWriter();
        const id = me.writer?.id;
        if (me.permissions.canEditAny || (id && writerIds.includes(id) && me.permissions.canWrite)) {
          setHref(`/write/${articleId}`);
        } else {
          setHref(null);
        }
      } catch {
        setHref(null);
      }
    })();
  }, [articleId, status, writerIds.join(",")]);

  if (!href) return null;

  return (
    <div className={styles.editBar}>
      <Link href={href} className={styles.editBtn}>
        Edit
      </Link>
    </div>
  );
}
