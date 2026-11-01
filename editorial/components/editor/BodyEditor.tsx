"use client";

import Link from "@tiptap/extension-link";
import Placeholder from "@tiptap/extension-placeholder";
import Underline from "@tiptap/extension-underline";
import { EditorContent, useEditor, type Editor } from "@tiptap/react";
import type { JSONContent } from "@tiptap/react";
import StarterKit from "@tiptap/starter-kit";
import { useRef } from "react";
import { EditorialImage } from "@/components/editor/editorialImage";
import type { RichTextDoc } from "@/lib/editorial/types";
import { FieldHint } from "@/components/editor/FieldHint";
import styles from "./cms.module.css";

type BodyEditorProps = {
  value: RichTextDoc;
  onChange: (doc: RichTextDoc) => void;
  onUpload: (file: File) => Promise<string>;
};

export function BodyEditor({ value, onChange, onUpload }: BodyEditorProps) {
  const fileRef = useRef<HTMLInputElement>(null);
  const uploading = useRef(false);

  const editor = useEditor({
    immediatelyRender: false,
    extensions: [
      StarterKit.configure({
        heading: { levels: [2, 3] },
      }),
      Underline,
      Link.configure({ openOnClick: false, autolink: true }),
      EditorialImage,
      Placeholder.configure({
        placeholder: "Start writing the article…",
      }),
    ],
    content: value as JSONContent,
    onUpdate: ({ editor: next }) => {
      onChange(next.getJSON() as RichTextDoc);
    },
  });

  async function insertImage(file: File) {
    if (!editor || uploading.current) return;
    uploading.current = true;
    try {
      const src = await onUpload(file);
      editor
        .chain()
        .focus()
        .insertContent({
          type: "image",
          attrs: { src, alt: "", caption: "", credit: "", size: "normal" },
        })
        .run();
    } finally {
      uploading.current = false;
    }
  }

  return (
    <>
      <div className={styles.editorTop}>
        <p className={styles.bodyHint}>
          <FieldHint id="body" />
        </p>
        {editor && <Toolbar editor={editor} onPickImage={() => fileRef.current?.click()} />}
      </div>
      <div className={styles.articlePane}>
        <div className={styles.editor}>
          <EditorContent editor={editor} className={styles.prose} />
        </div>
        <input
          ref={fileRef}
          type="file"
          accept="image/*"
          hidden
          onChange={(e) => {
            const file = e.target.files?.[0];
            if (file) void insertImage(file);
            e.target.value = "";
          }}
        />
      </div>
    </>
  );
}

function Toolbar({
  editor,
  onPickImage,
}: {
  editor: Editor;
  onPickImage: () => void;
}) {
  const btn = (active: boolean) => (active ? styles.tbOn : styles.tb);

  return (
    <div className={styles.toolbar}>
      <button type="button" className={btn(editor.isActive("bold"))} onClick={() => editor.chain().focus().toggleBold().run()}>
        Bold
      </button>
      <button type="button" className={btn(editor.isActive("italic"))} onClick={() => editor.chain().focus().toggleItalic().run()}>
        Italic
      </button>
      <button type="button" className={btn(editor.isActive("underline"))} onClick={() => editor.chain().focus().toggleUnderline().run()}>
        Underline
      </button>
      <span className={styles.tbRule} />
      <button type="button" className={btn(editor.isActive("heading", { level: 2 }))} onClick={() => editor.chain().focus().toggleHeading({ level: 2 }).run()}>
        Heading
      </button>
      <button type="button" className={btn(editor.isActive("heading", { level: 3 }))} onClick={() => editor.chain().focus().toggleHeading({ level: 3 }).run()}>
        Subhead
      </button>
      <button type="button" className={btn(editor.isActive("blockquote"))} onClick={() => editor.chain().focus().toggleBlockquote().run()}>
        Quote
      </button>
      <button type="button" className={btn(editor.isActive("bulletList"))} onClick={() => editor.chain().focus().toggleBulletList().run()}>
        List
      </button>
      <span className={styles.tbRule} />
      <button
        type="button"
        className={styles.tb}
        onClick={() => {
          const href = window.prompt("Link URL");
          if (!href) editor.chain().focus().unsetLink().run();
          else editor.chain().focus().setLink({ href }).run();
        }}
      >
        Link
      </button>
      <button type="button" className={styles.tb} onClick={onPickImage}>
        Upload image
      </button>
      <button
        type="button"
        className={styles.tb}
        onClick={() => {
          const src = window.prompt("Image URL");
          if (!src?.trim()) return;
          editor
            .chain()
            .focus()
            .insertContent({
              type: "image",
              attrs: { src: src.trim(), alt: "", caption: "", credit: "", size: "normal" },
            })
            .run();
        }}
      >
        Image URL
      </button>
    </div>
  );
}
