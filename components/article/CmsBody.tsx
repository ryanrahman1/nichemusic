import type { ReactNode } from "react";
import type { RichTextDoc } from "@/lib/editorial/types";
import styles from "./article.module.css";

type Mark = { type: string; attrs?: Record<string, string> };
type Node = {
  type: string;
  text?: string;
  marks?: Mark[];
  attrs?: {
    src?: string;
    alt?: string;
    caption?: string;
    credit?: string;
    size?: "normal" | "wide" | "full";
    href?: string;
    level?: number;
  };
  content?: Node[];
};

function applyMarks(text: string, marks: Mark[] | undefined, key: string): ReactNode {
  let node: ReactNode = text;
  for (const mark of marks ?? []) {
    if (mark.type === "bold") node = <strong key={`${key}-b`}>{node}</strong>;
    if (mark.type === "italic") node = <em key={`${key}-i`}>{node}</em>;
    if (mark.type === "underline") node = <u key={`${key}-u`}>{node}</u>;
    if (mark.type === "link") {
      node = (
        <a key={`${key}-a`} href={mark.attrs?.href} className="underline-link">
          {node}
        </a>
      );
    }
  }
  return node;
}

function renderNodes(nodes: Node[] | undefined, keyPrefix: string): ReactNode {
  return (nodes ?? []).map((node, index) => {
    const key = `${keyPrefix}-${index}`;
    if (node.type === "text") {
      return <span key={key}>{applyMarks(node.text ?? "", node.marks, key)}</span>;
    }
    if (node.type === "hardBreak") return <br key={key} />;
    if (node.type === "paragraph") {
      return <p key={key}>{renderNodes(node.content, key)}</p>;
    }
    if (node.type === "heading") {
      const Tag = Number(node.attrs?.level) === 3 ? "h3" : "h2";
      return <Tag key={key}>{renderNodes(node.content, key)}</Tag>;
    }
    if (node.type === "bulletList") return <ul key={key}>{renderNodes(node.content, key)}</ul>;
    if (node.type === "orderedList") return <ol key={key}>{renderNodes(node.content, key)}</ol>;
    if (node.type === "listItem") return <li key={key}>{renderNodes(node.content, key)}</li>;
    if (node.type === "blockquote") {
      return <blockquote key={key}>{renderNodes(node.content, key)}</blockquote>;
    }
    if (node.type === "image" && node.attrs?.src) {
      const size = node.attrs.size ?? "normal";
      return (
        <figure key={key} className={`${styles.inlineFig} ${styles[`size_${size}`]}`}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={node.attrs.src} alt={node.attrs.alt || ""} />
          {(node.attrs.caption || node.attrs.credit) && (
            <figcaption>
              {node.attrs.caption}
              {node.attrs.credit ? ` — ${node.attrs.credit}` : ""}
            </figcaption>
          )}
        </figure>
      );
    }
    return <div key={key}>{renderNodes(node.content, key)}</div>;
  });
}

export function CmsBody({ value }: { value: RichTextDoc }) {
  // public article body, layout is ours not the writer's
  return <div className={styles.body}>{renderNodes(value.content as Node[], "cms")}</div>;
}
