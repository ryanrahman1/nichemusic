"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useRef, useState } from "react";
import { BodyEditor } from "@/components/editor/BodyEditor";
import {
  checkArticleSlug,
  deleteDeskArticle,
  getMyWriter,
  publishDeskArticle,
  publishMyArticle,
  submitMyArticle,
  updateDeskArticle,
  updateMyArticle,
  uploadEditorialFile,
} from "@/lib/editorial/api";
import {
  articleHref,
  packContent,
  TEMPLATE_META,
} from "@/lib/editorial/cms";
import type {
  ArticleCard,
  ArticleTemplate,
  CmsPayload,
  SpotlightWidget,
  TemplateData,
  TemplateTextKey,
  WriterPermissions,
} from "@/lib/editorial/types";
import { ARTICLE_TEMPLATES } from "@/lib/editorial/types";
import { slugify } from "@/lib/editorial/cms";
import { WidgetPanel } from "@/components/editor/WidgetPanel";
import { parseWidgets } from "@/lib/editorial/cms";
import { FieldHint, HelpButton } from "@/components/editor/FieldHint";
import { PublishedEditNotice, type PublishedEditNoticeMode } from "@/components/editor/PublishedEditNotice";
import { StandardsGate } from "@/components/editor/StandardsGate";
import type { HelpId } from "@/components/editor/fieldHelp";
import { useEditorLayout } from "@/components/editor/useEditorLayout";
import styles from "./cms.module.css";

type Props = {
  article: ArticleCard;
  initial: CmsPayload;
  desk?: boolean;
  permissions?: WriterPermissions;
  viewerWriterId?: string | null;
};

const WRITER_SAVE = ["draft", "changes_requested", "rejected", "published"];
const DESK_SAVE = ["submitted", "in_review", "approved", "published"];
const PUBLISHABLE_STATUSES = ["submitted", "in_review", "approved"];
type SlugCheckState = "idle" | "checking" | "available" | "taken" | "error";

export function ArticleCms({
  article,
  initial,
  desk = false,
  permissions,
  viewerWriterId,
}: Props) {
  const router = useRouter();
  const [meta, setMeta] = useState({
    title: article.title,
    slug: article.slug,
    subtitle: article.subtitle ?? "",
    excerpt: article.excerpt ?? "",
    type: article.type,
    coverImageUrl: article.coverImageUrl ?? "",
    coverImageAlt: article.coverImageAlt ?? "",
    coverImageCredit: article.coverImageCredit ?? "",
    tagSlugs: article.tags.map((t) => t.slug).join(", "),
  });
  const [payload, setPayload] = useState<CmsPayload>(initial);
  const [saveState, setSaveState] = useState("Saved");
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState(article.status ?? "draft");
  const [slugCheck, setSlugCheck] = useState<SlugCheckState>("idle");
  const [publishedEditNotice, setPublishedEditNotice] =
    useState<PublishedEditNoticeMode | null>(
      article.status === "published" ? "warning" : null,
    );
  const [canSelfPublish, setCanSelfPublish] = useState(false);
  const owner = Boolean(
    viewerWriterId &&
      (article.credits ?? []).some(
        (credit) => credit.creditType === "writer" && credit.writer?.id === viewerWriterId,
      ),
  );
  const useDeskApi = desk && !owner;
  const canDelete = Boolean(permissions?.canDelete);
  const canDeskPublish = Boolean(permissions?.canPublish);
  const [busy, setBusy] = useState(false);
  const [gate, setGate] = useState<null | "submit" | "publish">(null);
  const [agreed, setAgreed] = useState(false);
  const dirty = useRef(false);
  const shellRef = useRef<HTMLDivElement>(null);
  const { vars: layoutVars, dragging, dragSide, dragWidget } = useEditorLayout(
    payload.template === "artist_spotlight",
    shellRef,
  );
  const coverRef = useRef<HTMLInputElement>(null);
  const extraRef = useRef<HTMLInputElement>(null);
  const extraField = useRef<TemplateTextKey>("artworkUrl");
  const slugCheckRequest = useRef(0);
  const shownSlugCheck = slugify(meta.slug.trim()) ? slugCheck : "idle";

  const markDirty = () => {
    dirty.current = true;
    setSaveState("Unsaved");
  };

  const persist = useCallback(async (): Promise<ArticleCard | null> => {
    const allowed = useDeskApi
      ? Boolean(permissions?.canEditAny) || DESK_SAVE.includes(status)
      : WRITER_SAVE.includes(status);
    if (!allowed) return null;

    setSaveState("Saving…");
    setError(null);
    const body = {
      title: meta.title.trim() || "Untitled",
      slug: slugify(meta.slug.trim()) || article.slug,
      subtitle: meta.subtitle.trim() || null,
      excerpt: meta.excerpt.trim() || null,
      coverImageUrl: meta.coverImageUrl.trim() || null,
      coverImageAlt: meta.coverImageAlt.trim() || null,
      coverImageCredit: meta.coverImageCredit.trim() || null,
      tagSlugs: meta.tagSlugs.split(",").map((t) => slugify(t)).filter(Boolean),
      template: payload.template,
      templateData: payload.templateData,
      content: packContent(payload),
    };
    try {
      // desk saves credit the editor, writer routes stay owner-only
      const result = useDeskApi
        ? await updateDeskArticle(article.id, body)
        : await updateMyArticle(article.id, body);
      const next = result.article;
      const nextStatus =
        next.status ??
        (status === "published"
          ? useDeskApi
            ? "in_review"
            : "changes_requested"
          : status);
      dirty.current = false;
      setStatus(nextStatus);
      if (status === "published" && nextStatus !== "published") {
        setSaveState("Unpublished — needs review");
        setPublishedEditNotice("unpublished");
      } else {
        setSaveState("Saved");
      }
      return next;
    } catch (err) {
      setSaveState("Couldnt save");
      setError(err instanceof Error ? err.message : "Couldnt save");
      return null;
    }
  }, [
    article.id,
    article.slug,
    meta,
    payload,
    permissions?.canEditAny,
    status,
    useDeskApi,
  ]);

  // check the slug against this article type after they pause typing
  useEffect(() => {
    const normalized = slugify(meta.slug.trim());
    const requestId = ++slugCheckRequest.current;

    if (!normalized) {
      return;
    }

    const timer = window.setTimeout(() => {
      setSlugCheck("checking");
      void checkArticleSlug(normalized, article.type, article.id)
        .then((result) => {
          if (requestId === slugCheckRequest.current) {
            setSlugCheck(result.available ? "available" : "taken");
          }
        })
        .catch(() => {
          if (requestId === slugCheckRequest.current) setSlugCheck("error");
        });
    }, 450);

    return () => window.clearTimeout(timer);
  }, [article.id, article.type, meta.slug]);

  useEffect(() => {
    void (async () => {
      try {
        const me = await getMyWriter();
        const role = me.writer?.role ?? "";
        setCanSelfPublish(
          Boolean(me.permissions.canPublish && (role === "editor" || role === "admin")),
        );
      } catch {
        setCanSelfPublish(false);
      }
    })();
  }, []);

  useEffect(() => {
    const t = window.setTimeout(() => {
      if (dirty.current) void persist();
    }, 1200);
    return () => window.clearTimeout(t);
  }, [meta, payload, persist]);

  function setTemplate(template: ArticleTemplate) {
    markDirty();
    setPayload((p) => ({ ...p, template }));
    setMeta((m) => ({ ...m, type: TEMPLATE_META[template].type }));
  }

  function setWidgets(widgets: SpotlightWidget[]) {
    markDirty();
    setPayload((p) => ({
      ...p,
      templateData: { ...p.templateData, widgets },
    }));
  }

  function setField<K extends keyof TemplateData>(key: K, value: TemplateData[K]) {
    markDirty();
    setPayload((p) => ({
      ...p,
      templateData: { ...p.templateData, [key]: value },
    }));
  }

  async function uploadTo(field: "cover" | TemplateTextKey, file: File) {
    const url = await uploadEditorialFile(article.id, file);
    markDirty();
    if (field === "cover") setMeta((m) => ({ ...m, coverImageUrl: url }));
    else setField(field, url as TemplateData[typeof field]);
  }

  function openGate(kind: "submit" | "publish") {
    setAgreed(false);
    setGate(kind);
  }

  async function confirmGate() {
    if (!gate || !agreed) return;
    const kind = gate;
    setBusy(true);
    setError(null);
    try {
      // only save first when this action has edits to push
      const shouldPersist = dirty.current || status === "published";
      const saved = shouldPersist ? await persist() : null;
      if (shouldPersist && !saved) return;
      if (kind === "submit") {
        const { article: next } = await submitMyArticle(article.id);
        setStatus(next.status ?? "submitted");
        setSaveState("Submitted");
      } else {
        if (status === "published" && saved?.status !== "published") {
          setError("This edit needs review before it can be published again.");
          setGate(null);
          return;
        }
        const { article: next } = useDeskApi
          ? await publishDeskArticle(article.id)
          : await publishMyArticle(article.id);
        setStatus(next.status ?? "published");
        setSaveState("Published");
      }
      setGate(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : kind === "submit" ? "Couldnt submit" : "Couldnt publish");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className={styles.shell}>
      <header className={styles.top}>
        <Link href="/write" className={styles.back}>
          Write
        </Link>
        <HelpButton id="title" />
        <input
          className={styles.title}
          value={meta.title}
          placeholder="Article title"
          onChange={(e) => {
            markDirty();
            setMeta((m) => ({ ...m, title: e.target.value }));
          }}
        />
        <span className={styles.status}>
          {status} · {saveState}
        </span>
        <button type="button" className={styles.secondary} onClick={() => void persist()} disabled={busy}>
          Save
        </button>
        {!useDeskApi && WRITER_SAVE.includes(status) && (
          <button
            type="button"
            className={styles.primary}
            disabled={busy}
            onClick={() => openGate("submit")}
          >
            {busy && gate === "submit" ? "Working…" : status === "published" ? "Submit for review" : "Submit"}
          </button>
        )}
        {(useDeskApi
          ? canDeskPublish && PUBLISHABLE_STATUSES.includes(status)
          : canSelfPublish && PUBLISHABLE_STATUSES.includes(status)) && (
          <button
            type="button"
            className={styles.primary}
            disabled={busy}
            onClick={() => openGate("publish")}
          >
            {busy && gate === "publish" ? "Working…" : "Publish"}
          </button>
        )}
        {canDelete && (
          <button
            type="button"
            className={styles.danger}
            disabled={busy}
            onClick={async () => {
              if (!window.confirm(`Delete “${meta.title || article.title}”? this aint reversible`)) {
                return;
              }
              setBusy(true);
              setError(null);
              try {
                await deleteDeskArticle(article.id);
                router.push("/write");
              } catch (err) {
                setError(err instanceof Error ? err.message : "Couldnt delete");
                setBusy(false);
              }
            }}
          >
            Delete
          </button>
        )}
        {status === "published" && (
          <Link
            href={articleHref({
              type: article.type,
              slug: slugify(meta.slug.trim()) || article.slug,
            })}
            className={styles.secondary}
          >
            View
          </Link>
        )}
      </header>

      <div className={styles.body} ref={shellRef} style={layoutVars}>
        <aside className={styles.side}>
          <button
            type="button"
            className={dragging === "side" ? `${styles.resizeHandle} ${styles.resizeHandleOn}` : styles.resizeHandle}
            aria-label="Resize metadata column"
            onPointerDown={dragSide}
          />
          {error && <p className={styles.err}>{error}</p>}

          <label>
            <FieldHint id="slug" />
            <input
              value={meta.slug}
              onChange={(e) => {
                markDirty();
                setMeta((m) => ({ ...m, slug: e.target.value }));
              }}
            />
            {shownSlugCheck !== "idle" ? (
              <span
                className={`${styles.slugCheck} ${styles[`slugCheck_${shownSlugCheck}`]}`}
                aria-live="polite"
              >
                {slugCheckLabel(shownSlugCheck)}
              </span>
            ) : null}
          </label>

          <label>
            <FieldHint id="template" />
            <select
              value={payload.template}
              onChange={(e) => setTemplate(e.target.value as ArticleTemplate)}
            >
              {ARTICLE_TEMPLATES.map((t) => (
                <option key={t} value={t}>
                  {TEMPLATE_META[t].label}
                </option>
              ))}
            </select>
          </label>

          <p className={styles.typeNote}>
            <FieldHint id="type">Type: {meta.type}</FieldHint>
          </p>

          <label>
            <FieldHint id="subtitle" />
            <input
              value={meta.subtitle}
              onChange={(e) => {
                markDirty();
                setMeta((m) => ({ ...m, subtitle: e.target.value }));
              }}
            />
          </label>
          <label>
            <FieldHint id="excerpt" />
            <textarea
              rows={3}
              value={meta.excerpt}
              onChange={(e) => {
                markDirty();
                setMeta((m) => ({ ...m, excerpt: e.target.value }));
              }}
            />
          </label>
          <label>
            <FieldHint id="tags" />
            <input
              value={meta.tagSlugs}
              placeholder="hyperpop, seoul"
              onChange={(e) => {
                markDirty();
                setMeta((m) => ({ ...m, tagSlugs: e.target.value }));
              }}
            />
          </label>

          <div className={styles.mediaField}>
            <FieldHint id="cover" />
            {meta.coverImageUrl && (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={meta.coverImageUrl} alt="" />
            )}
            <button type="button" onClick={() => coverRef.current?.click()}>
              Upload cover
            </button>
            <label>
              <FieldHint id="imageUrl" />
              <input
                placeholder="https://…"
                value={meta.coverImageUrl}
                onChange={(e) => {
                  markDirty();
                  setMeta((m) => ({ ...m, coverImageUrl: e.target.value }));
                }}
              />
            </label>
            <label>
              <FieldHint id="coverAlt" />
              <input
                placeholder="Cover alt"
                value={meta.coverImageAlt}
                onChange={(e) => {
                  markDirty();
                  setMeta((m) => ({ ...m, coverImageAlt: e.target.value }));
                }}
              />
            </label>
            <label>
              <FieldHint id="coverCredit" />
              <input
                placeholder="Cover credit"
                value={meta.coverImageCredit}
                onChange={(e) => {
                  markDirty();
                  setMeta((m) => ({ ...m, coverImageCredit: e.target.value }));
                }}
              />
            </label>
          </div>

          {payload.template === "album_review" && (
            <TemplateFields
              fields={[
                ["artist", "Artist", "artist"],
                ["album", "Album", "album"],
                ["releaseDate", "Release date", "releaseDate"],
                ["rating", "Rating", "rating"],
                ["verdict", "Verdict", "verdict"],
                ["label", "Label", "label"],
                ["scene", "Scene", "scene"],
                ["badge", "Badge", "badge"],
              ]}
              data={payload.templateData}
              onChange={setField}
              imageKey="artworkUrl"
              imageLabel="Album artwork"
              imageHelp="artworkUrl"
              onImage={() => {
                extraField.current = "artworkUrl";
                extraRef.current?.click();
              }}
            />
          )}

          {payload.template === "interview" && (
            <TemplateFields
              fields={[
                ["interviewee", "Interviewee", "interviewee"],
                ["role", "Role / description", "role"],
                ["location", "Location", "location"],
                ["interviewDate", "Interview date", "interviewDate"],
              ]}
              data={payload.templateData}
              onChange={setField}
              imageKey="portraitUrl"
              imageLabel="Portrait"
              imageHelp="portraitUrl"
              onImage={() => {
                extraField.current = "portraitUrl";
                extraRef.current?.click();
              }}
            />
          )}

          {payload.template === "artist_spotlight" && (
            <TemplateFields
              fields={[
                ["artist", "Artist", "spotlightArtist"],
                ["location", "Location", "location"],
                ["scene", "Scene", "spotlightScene"],
              ]}
              data={payload.templateData}
              onChange={setField}
              imageKey="portraitUrl"
              imageLabel="Portrait"
              imageHelp="portraitUrl"
              onImage={() => {
                extraField.current = "portraitUrl";
                extraRef.current?.click();
              }}
            />
          )}
        </aside>

        {payload.template === "artist_spotlight" && (
          <WidgetPanel
            widgets={parseWidgets(payload.templateData)}
            onChange={setWidgets}
            excludeArticleId={article.id}
            defaultArtist={payload.templateData.artist}
            onResize={dragWidget}
            resizing={dragging === "widget"}
          />
        )}

        <main className={styles.main}>
          <BodyEditor
            value={payload.doc}
            onChange={(doc) => {
              markDirty();
              setPayload((p) => ({ ...p, doc }));
            }}
            onUpload={(file) => uploadEditorialFile(article.id, file)}
          />
        </main>
      </div>

      <input
        ref={coverRef}
        type="file"
        accept="image/*"
        hidden
        onChange={(e) => {
          const file = e.target.files?.[0];
          if (file) void uploadTo("cover", file);
          e.target.value = "";
        }}
      />
      <input
        ref={extraRef}
        type="file"
        accept="image/*"
        hidden
        onChange={(e) => {
          const file = e.target.files?.[0];
          if (file) void uploadTo(extraField.current, file);
          e.target.value = "";
        }}
      />
      {gate ? (
        <StandardsGate
          action={gate}
          busy={busy}
          agreed={agreed}
          onAgreed={setAgreed}
          onCancel={() => {
            if (!busy) setGate(null);
          }}
          onConfirm={() => void confirmGate()}
        />
      ) : null}
      {publishedEditNotice ? (
        <PublishedEditNotice
          mode={publishedEditNotice}
          onDismiss={() => setPublishedEditNotice(null)}
        />
      ) : null}
    </div>
  );
}

function TemplateFields({
  fields,
  data,
  onChange,
  imageKey,
  imageLabel,
  imageHelp,
  onImage,
}: {
  fields: [TemplateTextKey, string, HelpId][];
  data: TemplateData;
  onChange: (key: TemplateTextKey, value: string) => void;
  imageKey: TemplateTextKey;
  imageLabel: string;
  imageHelp: HelpId;
  onImage: () => void;
}) {
  const src = data[imageKey];
  return (
    <div className={styles.tpl}>
      <p>{TEMPLATE_HEAD[imageLabel] ?? "Template"}</p>
      <div className={styles.mediaField}>
        <FieldHint id={imageHelp}>{imageLabel}</FieldHint>
        {src && (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={src} alt="" />
        )}
        <button type="button" onClick={onImage}>
          Upload
        </button>
        <label>
          <FieldHint id="imageUrl" />
          <input
            placeholder="https://…"
            value={src}
            onChange={(e) => onChange(imageKey, e.target.value)}
          />
        </label>
      </div>
      {fields.map(([key, label, help]) => (
        <label key={key}>
          <FieldHint id={help}>{label}</FieldHint>
          {key === "verdict" ? (
            <textarea rows={3} value={data[key]} onChange={(e) => onChange(key, e.target.value)} />
          ) : (
            <input value={data[key]} onChange={(e) => onChange(key, e.target.value)} />
          )}
        </label>
      ))}
    </div>
  );
}

const TEMPLATE_HEAD: Record<string, string> = {
  "Album artwork": "Album review fields",
  Portrait: "Template fields",
};

// give writers a tiny bit of slug feedback while they work
function slugCheckLabel(state: SlugCheckState) {
  if (state === "checking") return "Checking slug…";
  if (state === "available") return "Slug is available";
  if (state === "taken") return "Slug is already used for this article type";
  if (state === "error") return "Couldn’t check slug right now";
  return "";
}
