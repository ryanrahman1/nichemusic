"use client";

import { useEffect, useState, type PointerEvent as ReactPointerEvent } from "react";
import {
  getEditorialById,
  getPublishedEditorial,
  searchEditorials,
  searchMusic,
  type MusicSearchHit,
} from "@/lib/editorial/api";
import type {
  ArticleCard,
  SpotlightEntity,
  SpotlightWidget,
} from "@/lib/editorial/types";
import { FieldHint } from "@/components/editor/FieldHint";
import { editorialHero } from "@/lib/editorial/cms";
import styles from "./cms.module.css";

type Props = {
  widgets: SpotlightWidget[];
  onChange: (widgets: SpotlightWidget[]) => void;
  excludeArticleId?: string;
  defaultArtist?: string;
  onResize?: (e: ReactPointerEvent<HTMLButtonElement>) => void;
  resizing?: boolean;
};

export function WidgetPanel({
  widgets,
  onChange,
  excludeArticleId,
  defaultArtist,
  onResize,
  resizing,
}: Props) {
  function add(type: SpotlightWidget["type"]) {
    const id = `w_${Date.now().toString(36)}`;
    if (type === "essential_tracks") onChange([...widgets, { id, type, items: [] }]);
    if (type === "if_you_like") onChange([...widgets, { id, type, artistName: defaultArtist ?? "", items: [] }]);
    if (type === "watch") onChange([...widgets, { id, type, youtubeUrl: "", caption: "" }]);
    if (type === "featured_on_niche") onChange([...widgets, { id, type, editorialId: "", slug: "" }]);
  }

  function patch(id: string, next: SpotlightWidget) {
    onChange(widgets.map((w) => (w.id === id ? next : w)));
  }

  return (
    <aside className={styles.widgetCol}>
      {onResize ? (
        <button
          type="button"
          className={resizing ? `${styles.resizeHandle} ${styles.resizeHandleOn}` : styles.resizeHandle}
          aria-label="Resize widgets column"
          onPointerDown={onResize}
        />
      ) : null}
      <p className={styles.bodyHint}>
        <FieldHint id="widgets" />
      </p>
      {widgets.map((widget, index) => (
        <div key={widget.id} className={styles.widgetCard}>
          <div className={styles.widgetTop}>
            <strong>{labelFor(widget.type)}</strong>
            <div className={styles.widgetBtns}>
              {index > 0 && (
                <button type="button" className={styles.tb} onClick={() => {
                  const next = [...widgets];
                  const current = next[index];
                  const prev = next[index - 1];
                  if (!current || !prev) return;
                  next[index - 1] = current;
                  next[index] = prev;
                  onChange(next);
                }}>
                  Up
                </button>
              )}
              <button
                type="button"
                className={styles.tb}
                onClick={() => onChange(widgets.filter((w) => w.id !== widget.id))}
              >
                Remove
              </button>
            </div>
          </div>
          {widget.type === "essential_tracks" && (
            <EntityList
              kind="track"
              items={widget.items}
              onChange={(items) => patch(widget.id, { ...widget, items })}
              withBlurb
            />
          )}
          {widget.type === "if_you_like" && (
            <>
              <label>
                If you like
                <input
                  placeholder={defaultArtist || "Artist name"}
                  value={widget.artistName}
                  onChange={(e) => patch(widget.id, { ...widget, artistName: e.target.value })}
                />
              </label>
              <EntityList
                kind="artist"
                items={widget.items}
                onChange={(items) => patch(widget.id, { ...widget, items })}
              />
            </>
          )}
          {widget.type === "watch" && (
            <>
              <label>
                YouTube URL
                <input
                  placeholder="https://www.youtube.com/watch?v=…"
                  value={widget.youtubeUrl}
                  onChange={(e) => patch(widget.id, { ...widget, youtubeUrl: e.target.value })}
                />
              </label>
              <label>
                Caption
                <input
                  value={widget.caption}
                  onChange={(e) => patch(widget.id, { ...widget, caption: e.target.value })}
                />
              </label>
            </>
          )}
          {widget.type === "featured_on_niche" && (
            <FeaturedPicker
              editorialId={widget.editorialId}
              slug={widget.slug}
              excludeArticleId={excludeArticleId}
              onPick={(editorialId, slug) => patch(widget.id, { ...widget, editorialId, slug })}
            />
          )}
        </div>
      ))}
      <div className={styles.widgetAdd}>
        <button type="button" onClick={() => add("essential_tracks")}>+ Tracks</button>
        <button type="button" onClick={() => add("if_you_like")}>+ If you like</button>
        <button type="button" onClick={() => add("watch")}>+ Watch</button>
        <button type="button" onClick={() => add("featured_on_niche")}>+ Featured</button>
      </div>
    </aside>
  );
}

function labelFor(type: SpotlightWidget["type"]) {
  if (type === "essential_tracks") return "Essential tracks";
  if (type === "if_you_like") return "If you like…";
  if (type === "watch") return "Watch";
  return "Featured on Niche";
}

function EntityList({
  kind,
  items,
  onChange,
  withBlurb,
}: {
  kind: "track" | "artist";
  items: SpotlightEntity[];
  onChange: (items: SpotlightEntity[]) => void;
  withBlurb?: boolean;
}) {
  const [q, setQ] = useState("");
  const [hits, setHits] = useState<MusicSearchHit[]>([]);
  if (q.trim().length < 2 && hits.length > 0) {
    setHits([]);
  }

  useEffect(() => {
    if (q.trim().length < 2) return;
    const t = window.setTimeout(() => {
      void searchMusic(q.trim(), kind)
        .then((rows) => setHits(rows.filter((row) => row.kind === kind).slice(0, 6)))
        .catch(() => setHits([]));
    }, 250);
    return () => window.clearTimeout(t);
  }, [kind, q]);

  return (
    <div className={styles.entityList}>
      <p className={styles.entityHint}>{items.length}/5 · aim for 3–5</p>
      {items.length < 5 && (
        <input
          value={q}
          placeholder={kind === "track" ? "Search tracks" : "Search artists"}
          onChange={(e) => setQ(e.target.value)}
        />
      )}
      {hits.length > 0 && (
        <div className={styles.hitList}>
          {hits.map((hit) => (
            <button
              key={hit.id}
              type="button"
              className={styles.hit}
              onClick={() => {
                if (items.some((item) => item.id === hit.id)) return;
                onChange([
                  ...items,
                  {
                    id: hit.id,
                    title: hit.title,
                    subtitle: hit.subtitle,
                    cover: hit.cover,
                    href: hit.href,
                    blurb: "",
                  },
                ]);
                setQ("");
                setHits([]);
              }}
            >
              {hit.cover && (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={hit.cover} alt="" />
              )}
              <span>
                {hit.title}
                {hit.subtitle ? ` — ${hit.subtitle}` : ""}
              </span>
            </button>
          ))}
        </div>
      )}
      {items.map((item) => (
        <div key={item.id} className={styles.picked}>
          {item.cover && (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={item.cover} alt="" />
          )}
          <div>
            <p>{item.title}</p>
            {withBlurb && (
              <input
                placeholder="Short blurb"
                value={item.blurb ?? ""}
                onChange={(e) =>
                  onChange(
                    items.map((row) =>
                      row.id === item.id ? { ...row, blurb: e.target.value } : row,
                    ),
                  )
                }
              />
            )}
          </div>
          <button
            type="button"
            className={styles.tb}
            onClick={() => onChange(items.filter((row) => row.id !== item.id))}
          >
            x
          </button>
        </div>
      ))}
    </div>
  );
}

function FeaturedPicker({
  editorialId = "",
  slug = "",
  excludeArticleId,
  onPick,
}: {
  editorialId?: string;
  slug?: string;
  excludeArticleId?: string;
  onPick: (id: string, slug: string) => void;
}) {
  const [q, setQ] = useState("");
  const [hits, setHits] = useState<ArticleCard[]>([]);
  const [picked, setPicked] = useState<ArticleCard | null>(null);
  const id = editorialId || "";
  const pieceSlug = slug || "";
  const pieceKey = `${id}\t${pieceSlug}`;
  if (!id && !pieceSlug && picked !== null) {
    setPicked(null);
  }
  if (q.trim().length < 2 && hits.length > 0) {
    setHits([]);
  }

  useEffect(() => {
    if (q.trim().length < 2) return;
    const t = window.setTimeout(() => {
      void searchEditorials(q.trim()).then((data) => {
        setHits((data.articles ?? []).filter((row) => row.id !== excludeArticleId).slice(0, 6));
      });
    }, 250);
    return () => window.clearTimeout(t);
  }, [excludeArticleId, q]);

  useEffect(() => {
    const tab = pieceKey.indexOf("\t");
    const nextId = tab === -1 ? pieceKey : pieceKey.slice(0, tab);
    const nextSlug = tab === -1 ? "" : pieceKey.slice(tab + 1);
    if (!nextId && !nextSlug) return;
    let alive = true;
    void (async () => {
      if (nextSlug) {
        try {
          const data = await getPublishedEditorial(nextSlug);
          if (alive) setPicked(data.article);
          return;
        } catch {
          // try the id route next
        }
      }
      if (nextId) {
        try {
          const data = await getEditorialById(nextId);
          if (alive) setPicked(data.article);
          return;
        } catch {
          if (alive) setPicked(null);
        }
      }
    })();
    return () => {
      alive = false;
    };
  }, [pieceKey]);

  return (
    <div className={styles.entityList}>
      {picked && (
        <div className={styles.picked}>
          {editorialHero(picked) && (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={editorialHero(picked) ?? ""} alt="" />
          )}
          <div>
            <p>{picked.title}</p>
          </div>
          <button type="button" className={styles.tb} onClick={() => onPick("", "")}>
            x
          </button>
        </div>
      )}
      <input
        value={q}
        placeholder="Search published articles"
        onChange={(e) => setQ(e.target.value)}
      />
      {hits.length > 0 && (
        <div className={styles.hitList}>
          {hits.map((hit) => (
            <button
              key={hit.id}
              type="button"
              className={styles.hit}
              onClick={() => {
                onPick(hit.id, hit.slug);
                setPicked(hit);
                setQ("");
                setHits([]);
              }}
            >
              {editorialHero(hit) && (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={editorialHero(hit) ?? ""} alt="" />
              )}
              <span>{hit.title}</span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
