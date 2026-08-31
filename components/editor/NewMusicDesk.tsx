"use client";

import { useEffect, useRef, useState } from "react";
import {
  addNewMusicPick,
  deleteNewMusicPick,
  listNewMusicPicks,
  reorderNewMusicPicks,
  searchAppleSongs,
  searchEditorials,
  updateNewMusicPick,
  type MusicSearchHit,
} from "@/lib/editorial/api";
import type { AdminNewMusicPick, ArticleCard } from "@/lib/editorial/types";
import { StatusView } from "@/components/status/StatusView";
import { DeskFold } from "@/components/editor/DeskFold";
import styles from "@/components/editor/write-home.module.css";

function toLocal(iso: string | null) {
  if (!iso) return "";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function fromLocal(value: string) {
  if (!value) return null;
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return null;
  return d.toISOString();
}

export function NewMusicDesk() {
  const [picks, setPicks] = useState<AdminNewMusicPick[]>([]);
  const [q, setQ] = useState("");
  const [hits, setHits] = useState<MusicSearchHit[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const timer = useRef<number | null>(null);

  useEffect(() => {
    void listNewMusicPicks()
      .then((data) => setPicks(data.picks))
      .catch((err: unknown) => {
        setError(err instanceof Error ? err.message : "Couldnt load the friday board");
      });
  }, []);

  function queueSearch(value: string) {
    if (timer.current) window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => {
      if (value.trim().length < 2) {
        setHits([]);
        return;
      }
      void searchAppleSongs(value.trim()).then(setHits);
    }, 350);
  }

  async function run(fn: () => Promise<{ picks: AdminNewMusicPick[] }>) {
    setBusy(true);
    setError(null);
    try {
      const data = await fn();
      setPicks(data.picks);
    } catch (err) {
      setError(err instanceof Error ? err.message : "That friday edit failed");
    } finally {
      setBusy(false);
    }
  }

  return (
    <DeskFold id="nmf" title="New Music Friday" meta={`${picks.length} on the board`}>
      <p className={styles.nmfLede}>
        Search Apple Music, drop a track, reorder, hang a review on it, and set when it shows.
      </p>

      {error ? (
        <StatusView compact kicker="Friday" title="Couldn’t update the board." body={error} />
      ) : null}

      <div className={styles.nmfSearch}>
        <label>
          Add a track
          <input
            value={q}
            onChange={(e) => {
              setQ(e.target.value);
              queueSearch(e.target.value);
            }}
            placeholder="Search Apple Music…"
          />
        </label>
        {hits.length > 0 ? (
          <ul className={styles.nmfHits}>
            {hits.map((hit) => (
              <li key={hit.id}>
                <button
                  type="button"
                  disabled={busy}
                  onClick={() =>
                    void run(async () => {
                      const next = await addNewMusicPick({ appleSongId: hit.id });
                      setQ("");
                      setHits([]);
                      return next;
                    })
                  }
                >
                  {hit.cover ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={hit.cover} alt="" />
                  ) : (
                    <span className={styles.nmfFallback} />
                  )}
                  <span>
                    <strong>{hit.title}</strong>
                    {hit.subtitle ? <em>{hit.subtitle}</em> : null}
                  </span>
                </button>
              </li>
            ))}
          </ul>
        ) : null}
      </div>

      {picks.length === 0 ? (
        <StatusView
          compact
          kicker="Friday"
          title="Nothing on the board yet."
          body="Search a song and add it. Homepage only shows picks inside their window."
        />
      ) : (
        <ol className={styles.nmfList}>
          {picks.map((pick, index) => (
            <PickRow
              key={pick.id}
              pick={pick}
              index={index}
              total={picks.length}
              busy={busy}
              onMove={(dir) => {
                const next = [...picks];
                const swap = index + dir;
                const a = next[index];
                const b = next[swap];
                if (!a || !b) return;
                next[index] = b;
                next[swap] = a;
                void run(() => reorderNewMusicPicks(next.map((row) => row.id)));
              }}
              onSave={(patch) => void run(() => updateNewMusicPick(pick.id, patch))}
              onDelete={() => void run(() => deleteNewMusicPick(pick.id))}
            />
          ))}
        </ol>
      )}
    </DeskFold>
  );
}

function PickRow({
  pick,
  index,
  total,
  busy,
  onMove,
  onSave,
  onDelete,
}: {
  pick: AdminNewMusicPick;
  index: number;
  total: number;
  busy: boolean;
  onMove: (dir: -1 | 1) => void;
  onSave: (patch: {
    editorialId?: string | null;
    showFrom?: string | null;
    showUntil?: string | null;
  }) => void;
  onDelete: () => void;
}) {
  const [from, setFrom] = useState(toLocal(pick.showFrom));
  const [until, setUntil] = useState(toLocal(pick.showUntil));
  const [reviewQ, setReviewQ] = useState("");
  const [reviews, setReviews] = useState<ArticleCard[]>([]);

  useEffect(() => {
    setFrom(toLocal(pick.showFrom));
    setUntil(toLocal(pick.showUntil));
  }, [pick.showFrom, pick.showUntil]);

  function queueReviews(value: string) {
    if (value.trim().length < 2) {
      setReviews([]);
      return;
    }
    void searchEditorials(value.trim()).then((data) => {
      setReviews(data.articles.filter((article) => article.type === "review").slice(0, 5));
    });
  }

  const name = pick.track?.name || "Untitled";
  const artist = pick.track?.artist?.name || "";

  return (
    <li className={styles.nmfRow}>
      {pick.track?.artworkUrl ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={pick.track.artworkUrl} alt="" />
      ) : (
        <span className={styles.nmfFallback} />
      )}
      <div className={styles.nmfMeta}>
        <p>
          <strong>{name}</strong>
          {artist ? <span> · {artist}</span> : null}
        </p>
        <p className={styles.nmfStatus}>{pick.live ? "Live now" : "Scheduled / hidden"}</p>
        {pick.review ? (
          <p className={styles.nmfReview}>
            Review: {pick.review.title}{" "}
            <button type="button" disabled={busy} onClick={() => onSave({ editorialId: null })}>
              Remove
            </button>
          </p>
        ) : null}
      </div>

      <div className={styles.nmfFields}>
        <label>
          Show from
          <input type="datetime-local" value={from} onChange={(e) => setFrom(e.target.value)} />
        </label>
        <label>
          Show until
          <input type="datetime-local" value={until} onChange={(e) => setUntil(e.target.value)} />
        </label>
        <label>
          Related review
          <input
            value={reviewQ}
            onChange={(e) => {
              setReviewQ(e.target.value);
              queueReviews(e.target.value);
            }}
            placeholder="Search a review…"
          />
        </label>
        {reviews.length > 0 ? (
          <ul className={styles.nmfHits}>
            {reviews.map((article) => (
              <li key={article.id}>
                <button
                  type="button"
                  disabled={busy}
                  onClick={() => {
                    onSave({ editorialId: article.id });
                    setReviewQ("");
                    setReviews([]);
                  }}
                >
                  <span>
                    <strong>{article.title}</strong>
                  </span>
                </button>
              </li>
            ))}
          </ul>
        ) : null}
      </div>

      <div className={styles.nmfBtns}>
        <button type="button" disabled={busy || index === 0} onClick={() => onMove(-1)}>
          Up
        </button>
        <button type="button" disabled={busy || index === total - 1} onClick={() => onMove(1)}>
          Down
        </button>
        <button
          type="button"
          disabled={busy}
          onClick={() => onSave({ showFrom: fromLocal(from), showUntil: fromLocal(until) })}
        >
          Save window
        </button>
        <button type="button" className={styles.danger} disabled={busy} onClick={onDelete}>
          Remove
        </button>
      </div>
    </li>
  );
}
