"use client";

import Link from "next/link";
import { CoverImage } from "@/components/home/CoverImage";
import { deleteDeskArticle } from "@/lib/editorial/api";
import { articleTypeLabel, editorialHero } from "@/lib/editorial/cms";
import type { ArticleCard, WriterPermissions } from "@/lib/editorial/types";
import { writerDisplayName } from "@/lib/editorial/writers";
import { StatusView } from "@/components/status/StatusView";
import styles from "./write-home.module.css";
import { DeskFold } from "@/components/editor/DeskFold";

function byline(article: ArticleCard) {
  const writer = (article.credits ?? []).find((c) => c.creditType === "writer");
  return writerDisplayName(writer);
}

function statusLabel(status: string | null | undefined) {
  if (!status) return "Draft";
  if (status === "in_review") return "In review";
  if (status === "changes_requested") return "Changes requested";
  return status.replace(/_/g, " ");
}

export function PieceCard({
  article,
  onDelete,
}: {
  article: ArticleCard;
  onDelete?: () => void;
}) {
  const cover = editorialHero(article);
  const author = byline(article);

  return (
    <article className={styles.card}>
      <Link href={`/write/${article.id}`} className={styles.cardLink}>
        <div className={styles.media}>
          {cover ? (
            <CoverImage src={cover} alt="" sizes="(max-width: 640px) 100vw, 33vw" />
          ) : (
            <span className={styles.blank} aria-hidden>
              {article.title.slice(0, 1) || "N"}
            </span>
          )}
        </div>
        <div className={styles.copy}>
          <p className={styles.meta}>
            <span className={styles.type}>{articleTypeLabel(article.type)}</span>
            <span className={styles.status}>{statusLabel(article.status)}</span>
          </p>
          <h3 className={styles.title}>{article.title || "Untitled"}</h3>
          <div className={styles.cardFoot}>
            {author ? <p className={styles.by}>{author}</p> : <span />}
            {onDelete ? (
              <button
                type="button"
                className={styles.danger}
                onClick={(e) => {
                  e.preventDefault();
                  e.stopPropagation();
                  if (!window.confirm(`Delete “${article.title}”? this aint reversible`)) {
                    return;
                  }
                  onDelete();
                }}
              >
                Delete
              </button>
            ) : null}
          </div>
        </div>
      </Link>
    </article>
  );
}

export function ReviewQueue({ queue }: { queue: ArticleCard[] }) {
  return (
    <DeskFold id="review" title="In review" meta="Edit and publish. The original writer stays on the byline.">
      {queue.length === 0 ? (
        <StatusView
          compact
          kicker="In review"
          title="Nothing waiting."
          body="When a writer submits, it shows up here for edit and publish. Their byline stays on the piece."
        />
      ) : (
        <div className={styles.grid}>
          {queue.map((article) => (
            <PieceCard key={article.id} article={article} />
          ))}
        </div>
      )}
    </DeskFold>
  );
}

export function ArticleCatalog({
  catalog,
  canDelete,
  onDeleted,
}: {
  catalog: ArticleCard[];
  canDelete: boolean;
  onDeleted: (id: string) => void;
}) {
  return (
    <DeskFold id="catalog" title="All articles" meta="Open or delete any piece on the site.">
      {catalog.length === 0 ? (
        <StatusView
          compact
          kicker="Catalog"
          title="No articles yet."
          body="The stack is empty. First draft through the write desk and it’ll land here."
        />
      ) : (
        <div className={styles.grid}>
          {catalog.map((article) => (
            <PieceCard
              key={article.id}
              article={article}
              onDelete={
                canDelete
                  ? () => {
                      void (async () => {
                        try {
                          await deleteDeskArticle(article.id);
                          onDeleted(article.id);
                        } catch (err) {
                          window.alert(err instanceof Error ? err.message : "Couldnt delete");
                        }
                      })();
                    }
                  : undefined
              }
            />
          ))}
        </div>
      )}
    </DeskFold>
  );
}

export function DeskBoard({
  queue,
  catalog,
  permissions,
  onDeleted,
}: {
  queue: ArticleCard[];
  catalog: ArticleCard[];
  permissions: WriterPermissions;
  onDeleted: (id: string) => void;
}) {
  return (
    <>
      {permissions.canReview ? <ReviewQueue queue={queue} /> : null}
      {permissions.canEditAny ? (
        <ArticleCatalog
          catalog={catalog}
          canDelete={permissions.canDelete}
          onDeleted={onDeleted}
        />
      ) : null}
    </>
  );
}
