import { ArticleEditLink } from "@/components/article/ArticleEditLink";
import { ArticleShare } from "@/components/article/ArticleShare";
import { ArticleViewTracker } from "@/components/article/ArticleViewTracker";
import { CmsBody } from "@/components/article/CmsBody";
import { SpotlightRail } from "@/components/article/SpotlightRail";
import { ArticleTeaserCard } from "@/components/editorial/ArticleTeaserCard";
import { WriterProfileLink } from "@/components/editorial/WriterProfileLink";
import { articleHref, parseWidgets, tagHref, unpackArticle, wordCount, youtubeId } from "@/lib/editorial/cms";
import { resolveFeaturedArticle } from "@/lib/editorial/public";
import type { ArticleCard, ArticleCredit, CmsPayload, SpotlightWidget } from "@/lib/editorial/types";
import type { ReactNode } from "react";
import Link from "next/link";
import styles from "./article.module.css";

function formatDate(value: string | null | undefined) {
  if (!value) return "";
  return new Date(value).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

export function writerName(credit: ArticleCredit | undefined) {
  if (!credit?.writer) return "";
  return (
    credit.writer.profile?.displayName ||
    credit.writer.profile?.username ||
    credit.writer.slug
  );
}

function WriterLink({
  credit,
  className,
  children,
}: {
  credit?: ArticleCredit;
  className?: string;
  children: ReactNode;
}) {
  return (
    <WriterProfileLink
      profileId={credit?.writer?.profile?.id}
      slug={credit?.writer?.slug}
      className={className}
    >
      {children}
    </WriterProfileLink>
  );
}

export function byline(article: ArticleCard) {
  const writer = (article.credits ?? []).find((c) => c.creditType === "writer");
  return writerName(writer);
}

function avatar(credit: ArticleCredit | undefined) {
  return credit?.writer?.profile?.avatarUrl ?? "";
}

export async function ArticleView({
  article,
  related = [],
}: {
  article: ArticleCard;
  related?: ArticleCard[];
}) {
  const cms = unpackArticle(article);
  const writer = (article.credits ?? []).find((c) => c.creditType === "writer");
  const editor = (article.credits ?? []).find((c) => c.creditType === "editor");
  const words = wordCount(cms.doc);
  const writerIds = (article.credits ?? [])
    .filter((c) => c.creditType === "writer")
    .map((c) => c.writer?.id)
    .filter((id): id is string => Boolean(id));
  const authorProfileIds = (article.credits ?? [])
    .filter((c) => c.creditType === "writer")
    .map((c) => c.writer?.profile?.id)
    .filter((id): id is string => Boolean(id));
  const widgets = cms.template === "artist_spotlight" ? parseWidgets(cms.templateData) : [];
  const featured: Record<string, ArticleCard> = {};
  await Promise.all(
    widgets
      .filter((w): w is Extract<SpotlightWidget, { type: "featured_on_niche" }> => w.type === "featured_on_niche")
      .map(async (widget) => {
        const piece = await resolveFeaturedArticle(widget);
        if (piece) featured[widget.id] = piece;
      }),
  );
  const liveWidgets = widgets.some((widget) => widgetIsLive(widget, featured));
  const relatedCards = related.slice(0, 2);

  return (
    <article className={styles.article}>
      <ArticleViewTracker articleId={article.id} authorProfileIds={authorProfileIds} />
      <ArticleEditLink articleId={article.id} writerIds={writerIds} />
      {cms.template === "album_review" ? (
        <AlbumReviewHeader article={article} cms={cms} writer={writer} editor={editor} words={words} />
      ) : cms.template === "interview" ? (
        <InterviewHeader article={article} cms={cms} writer={writer} editor={editor} />
      ) : cms.template === "artist_spotlight" ? (
        <SpotlightHeader article={article} cms={cms} writer={writer} editor={editor} />
      ) : (
        <StandardHeader article={article} writer={writer} editor={editor} />
      )}

      <div className={
        liveWidgets || relatedCards.length > 0
          ? styles.spotlightBody
          : cms.template === "standard"
            ? `${styles.contentWrap} ${styles.newsCopy}`
            : styles.contentWrap
      }>
        <CmsBody value={cms.doc} />
        {liveWidgets || relatedCards.length > 0 ? (
          <aside className={liveWidgets ? styles.rail : `${styles.rail} ${styles.railOpen}`}>
            {liveWidgets ? (
              <SpotlightRail
                widgets={widgets}
                featured={featured}
                artistName={cms.templateData.artist}
              />
            ) : (
              <div className={styles.railAdSlot} aria-hidden />
            )}
            {relatedCards.length > 0 ? (
              <section className={liveWidgets ? `${styles.relatedRail} ${styles.relatedAfterWidgets}` : styles.relatedRail}>
                <p className={styles.kicker}>Related</p>
                <div className={styles.relatedPair}>
                  {relatedCards.map((item) => (
                    <ArticleTeaserCard key={item.id} article={item} />
                  ))}
                </div>
              </section>
            ) : null}
          </aside>
        ) : null}
      </div>

      <footer className={styles.credits}>
        <ArticleShare title={article.title} path={articleHref(article)} />
        {article.tags.length > 0 ? (
          <p className={`${styles.kicker} ${styles.tagLine}`}>
            Tags:{" "}
            {article.tags.map((tag, i) => (
              <span key={tag.id}>
                {i > 0 ? " · " : null}
                <Link href={tagHref(tag)} className={styles.tagLink}>
                  {tag.name || tag.slug}
                </Link>
              </span>
            ))}
          </p>
        ) : null}
      </footer>

      {writer?.writer && (
        <aside className={styles.authorCard}>
          <p className={styles.kicker}>Written by</p>
          <WriterLink credit={writer} className={styles.authorLink}>
            {avatar(writer) ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img className={styles.avatar} src={avatar(writer)} alt="" />
            ) : null}
            <p className={styles.authorName}>{writerName(writer)}</p>
          </WriterLink>
          {writer.writer.bio ? (
            <p className={styles.authorBio}>{writer.writer.bio}</p>
          ) : null}
        </aside>
      )}
    </article>
  );
}

function widgetIsLive(widget: SpotlightWidget, featured: Record<string, ArticleCard>) {
  // skip empty widgets so the rail doesnt sit there doing nothing
  if (widget.type === "essential_tracks" || widget.type === "if_you_like") return widget.items.length > 0;
  if (widget.type === "watch") return Boolean(youtubeId(widget.youtubeUrl));
  if (widget.type === "featured_on_niche") return Boolean(featured[widget.id]);
  return false;
}

function StandardHeader({
  article,
  writer,
  editor,
}: {
  article: ArticleCard;
  writer?: ArticleCredit;
  editor?: ArticleCredit;
}) {
  return (
    <header className={styles.standardHead}>
      {article.coverImageUrl && (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          className={styles.cover}
          src={article.coverImageUrl}
          alt={article.coverImageAlt || article.title}
        />
      )}
      <div className={`${styles.headCopy} ${styles.newsCopy}`}>
        <p className={styles.kicker}>
          {article.type}
          {article.publishedAt ? ` — ${formatDate(article.publishedAt)}` : ""}
        </p>
        <h1>{article.title}</h1>
        {article.subtitle && <p className={styles.deck}>{article.subtitle}</p>}
        <Byline writer={writer} editor={editor} date={article.publishedAt} />
      </div>
    </header>
  );
}

function AlbumReviewHeader({
  article,
  cms,
  writer,
  editor,
  words,
}: {
  article: ArticleCard;
  cms: CmsPayload;
  writer?: ArticleCredit;
  editor?: ArticleCredit;
  words: number;
}) {
  const d = cms.templateData;
  const artist = d.artist || article.title;
  const album = d.album;
  const hero = article.coverImageUrl || d.artworkUrl;

  return (
    <>
      {hero ? (
        <div className={styles.reviewHero}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={hero} alt={artist} />
          <div className={styles.reviewHeroCopy}>
            <p className={styles.kicker}>Album review</p>
            <h1>{artist}</h1>
            {album && (
              <p className={styles.albumName}>
                <em>{album}</em>
              </p>
            )}
          </div>
        </div>
      ) : (
        <div className={styles.reviewHeroCopy}>
          <p className={styles.kicker}>Album review</p>
          <h1>{artist}</h1>
          {album && (
            <p className={styles.albumName}>
              <em>{album}</em>
            </p>
          )}
        </div>
      )}

      <section className={styles.reviewMeta}>
        {d.artworkUrl ? (
          <div className={styles.artPlate}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={d.artworkUrl} alt={album || artist} />
          </div>
        ) : (
          <div />
        )}
        <div className={styles.scoreCol}>
          <div className={styles.scoreTop}>
            <div className={styles.scoreRow}>
              {d.rating && <span className={styles.score}>{d.rating}</span>}
              {d.rating && <span className={styles.over}>/ 10</span>}
              {d.badge && <span className={styles.badge}>{d.badge}</span>}
            </div>
            {(d.verdict || article.excerpt) && (
              <p className={styles.verdict}>{article.excerpt || d.verdict}</p>
            )}
          </div>
          <div className={styles.facts}>
            {d.label && (
              <div>
                <p className={styles.factLabel}>Label</p>
                <p>{d.label}</p>
              </div>
            )}
            {d.releaseDate && (
              <div>
                <p className={styles.factLabel}>Released</p>
                <p>{d.releaseDate}</p>
              </div>
            )}
            {d.scene && (
              <div>
                <p className={styles.factLabel}>Scene</p>
                <p>{d.scene}</p>
              </div>
            )}
          </div>
        </div>
        <CreditBox writer={writer} editor={editor} date={article.publishedAt} words={words} />
      </section>

      {d.verdict && (
        <section className={styles.intro}>
          <p className={styles.kicker}>The verdict</p>
          <p className={styles.introCopy}>{d.verdict}</p>
        </section>
      )}
    </>
  );
}

function InterviewHeader({
  article,
  cms,
  writer,
  editor,
}: {
  article: ArticleCard;
  cms: CmsPayload;
  writer?: ArticleCredit;
  editor?: ArticleCredit;
}) {
  const d = cms.templateData;
  return (
    <header className={styles.interviewHead}>
      {d.portraitUrl && (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={d.portraitUrl} alt={d.interviewee || article.title} />
      )}
      <div>
        <p className={styles.kicker}>Interview</p>
        <h1>{d.interviewee || article.title}</h1>
        {d.role && <p className={styles.deck}>{d.role}</p>}
        <p className={styles.by}>
          {[d.location, d.interviewDate].filter(Boolean).join(" · ")}
        </p>
        <Byline writer={writer} editor={editor} date={article.publishedAt} />
      </div>
    </header>
  );
}

function SpotlightHeader({
  article,
  cms,
  writer,
  editor,
}: {
  article: ArticleCard;
  cms: CmsPayload;
  writer?: ArticleCredit;
  editor?: ArticleCredit;
}) {
  const d = cms.templateData;
  const cover = article.coverImageUrl;
  const portrait = d.portraitUrl;

  return (
    <header className={styles.standardHead}>
      {cover && (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          className={styles.cover}
          src={cover}
          alt={d.artist || article.title}
        />
      )}
      <div className={portrait ? styles.spotlightMeta : styles.headCopy}>
        {portrait && (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            className={styles.spotlightPortrait}
            src={portrait}
            alt={d.artist || article.title}
          />
        )}
        <div className={portrait ? styles.headCopy : undefined}>
          <p className={styles.kicker}>
            Artist spotlight
            {d.scene ? ` — ${d.scene}` : ""}
          </p>
          <h1>{d.artist || article.title}</h1>
          {article.subtitle && <p className={styles.deck}>{article.subtitle}</p>}
          {d.location && <p className={styles.by}>{d.location}</p>}
          <Byline writer={writer} editor={editor} date={article.publishedAt} />
        </div>
      </div>
    </header>
  );
}

function Byline({
  writer,
  editor,
  date,
}: {
  writer?: ArticleCredit;
  editor?: ArticleCredit;
  date?: string | null;
}) {
  return (
    <p className={styles.by}>
      {writerName(writer) ? (
        <>
          <span>Written by</span>
          <WriterLink credit={writer} className={styles.byPerson}>
            {avatar(writer) ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img className={styles.avatar} src={avatar(writer)} alt="" />
            ) : null}
            {writerName(writer)}
          </WriterLink>
        </>
      ) : null}
      {writerName(editor) ? (
        <>
          <span>Edited by</span>
          <WriterLink credit={editor} className={styles.byPerson}>
            {avatar(editor) ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img className={styles.avatar} src={avatar(editor)} alt="" />
            ) : null}
            {writerName(editor)}
          </WriterLink>
        </>
      ) : null}
      {date ? <span>{formatDate(date)}</span> : null}
    </p>
  );
}

function CreditBox({
  writer,
  editor,
  date,
  words,
}: {
  writer?: ArticleCredit;
  editor?: ArticleCredit;
  date?: string | null;
  words: number;
}) {
  return (
    <div className={styles.creditBox}>
      <p className={styles.kicker}>Credits</p>
      {writer?.writer && (
        <div className={styles.creditRow}>
          <span>
            <span>Written by</span>
            <WriterLink credit={writer} className={styles.creditPerson}>
              {avatar(writer) ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img className={styles.avatar} src={avatar(writer)} alt="" />
              ) : null}
              <b>{writerName(writer)}</b>
            </WriterLink>
          </span>
        </div>
      )}
      {editor?.writer && (
        <div className={styles.creditRow}>
          <span>
            <span>Reviewed & edited by</span>
            <WriterLink credit={editor} className={styles.creditPerson}>
              {avatar(editor) ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img className={styles.avatar} src={avatar(editor)} alt="" />
              ) : null}
              <b>{writerName(editor)}</b>
            </WriterLink>
          </span>
        </div>
      )}
      <p className={styles.creditFoot}>
        {[
          date ? `Published ${formatDate(date)}` : "",
          words ? `${words} words` : "",
        ]
          .filter(Boolean)
          .join(" · ")}
      </p>
    </div>
  );
}
