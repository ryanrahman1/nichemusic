"use client";

import { useEffect, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { ArticleCms } from "@/components/editor/ArticleCms";
import { WriteLock } from "../WriteLock";
import { useSession } from "@/components/providers/SessionProvider";
import { ApiError } from "@/lib/api/types";
import { getDeskArticle, getMyArticle, getMyWriter } from "@/lib/editorial/api";
import { unpackArticle } from "@/lib/editorial/cms";
import type { ArticleCard, WriterPermissions } from "@/lib/editorial/types";
import { StatusView } from "@/components/status/StatusView";
import styles from "@/components/editor/cms.module.css";

const emptyPerms = (): WriterPermissions => ({
  canWrite: false,
  canSubmit: false,
  canReview: false,
  canPublish: false,
  canManageWriters: false,
  canEditAny: false,
  canDelete: false,
});

export default function WriteArticlePage() {
  const params = useParams<{ id: string }>();
  const { status } = useSession();
  const router = useRouter();
  const [article, setArticle] = useState<ArticleCard | null>(null);
  const [desk, setDesk] = useState(false);
  const [perms, setPerms] = useState<WriterPermissions>(emptyPerms);
  const [writerId, setWriterId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (status === "signedOut") router.replace("/login");
  }, [status, router]);

  useEffect(() => {
    if (status !== "signedIn" || !params.id) return;
    void (async () => {
      try {
        const me = await getMyWriter();
        setPerms(me.permissions);
        setWriterId(me.writer?.id ?? null);

        try {
          const { article: next } = await getMyArticle(params.id);
          setArticle(next);
          setDesk(false);
          return;
        } catch (err) {
          const forbidden = err instanceof ApiError && (err.status === 403 || err.code === "FORBIDDEN");
          if (!forbidden || !(me.permissions.canReview || me.permissions.canEditAny)) {
            throw err;
          }
        }

        // not theirs — try the desk door
        const { article: next } = await getDeskArticle(params.id);
        setArticle(next);
        setDesk(true);
      } catch (err) {
        setError(err instanceof Error ? err.message : "Couldnt load article");
      }
    })();
  }, [params.id, status]);

  if (error) {
    return (
      <>
        <WriteLock />
        <div className={styles.shell}>
          <StatusView
            tone="ink"
            kicker="Editor"
            title="Couldn’t open this piece."
            body={error}
            actions={[
              { href: "/write", label: "Back to write" },
              { href: "/", label: "Home" },
            ]}
          />
        </div>
      </>
    );
  }

  if (!article) {
    return (
      <>
        <WriteLock />
        <div className={styles.shell}>
          <p className={styles.muted}>Loading editor…</p>
        </div>
      </>
    );
  }

  return (
    <>
      <WriteLock />
      <ArticleCms
        article={article}
        initial={unpackArticle(article)}
        desk={desk}
        permissions={perms}
        viewerWriterId={writerId}
      />
    </>
  );
}
