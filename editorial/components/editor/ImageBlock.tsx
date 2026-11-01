"use client";

import { NodeViewWrapper, type NodeViewProps } from "@tiptap/react";
import { FieldHint } from "@/components/editor/FieldHint";
import styles from "./cms.module.css";

export function ImageBlock({ node, updateAttributes, selected }: NodeViewProps) {
  const { src, alt, caption, credit, size } = node.attrs as {
    src: string;
    alt: string;
    caption: string;
    credit: string;
    size: "normal" | "wide" | "full";
  };

  return (
    <NodeViewWrapper
      className={`${styles.imgBlock} ${styles[`img_${size}`]} ${selected ? styles.imgOn : ""}`}
    >
      {src ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={src} alt={alt || ""} />
      ) : (
        <div className={styles.imgEmpty}>Image missing</div>
      )}
      <div className={styles.imgMeta} contentEditable={false}>
        <p className={styles.imgMetaHead}>
          <FieldHint id="imageSize" />
        </p>
        <div className={styles.imgSizes}>
          {(["normal", "wide", "full"] as const).map((value) => (
            <button
              key={value}
              type="button"
              className={size === value ? styles.chipOn : styles.chip}
              onClick={() => updateAttributes({ size: value })}
            >
              {value}
            </button>
          ))}
        </div>
        <label>
          <FieldHint id="imageUrl" />
          <input
            value={src ?? ""}
            placeholder="https://…"
            onChange={(e) => updateAttributes({ src: e.target.value })}
          />
        </label>
        <label>
          <FieldHint id="imageCaption" />
          <input
            value={caption ?? ""}
            placeholder="Caption"
            onChange={(e) => updateAttributes({ caption: e.target.value })}
          />
        </label>
        <label>
          <FieldHint id="imageCredit" />
          <input
            value={credit ?? ""}
            placeholder="Credit"
            onChange={(e) => updateAttributes({ credit: e.target.value })}
          />
        </label>
        <label>
          <FieldHint id="imageAlt" />
          <input
            value={alt ?? ""}
            placeholder="Alt text"
            onChange={(e) => updateAttributes({ alt: e.target.value })}
          />
        </label>
      </div>
    </NodeViewWrapper>
  );
}
