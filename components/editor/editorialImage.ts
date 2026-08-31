import Image from "@tiptap/extension-image";
import { ReactNodeViewRenderer } from "@tiptap/react";
import { ImageBlock } from "@/components/editor/ImageBlock";

export const EditorialImage = Image.extend({
  atom: false,
  inline: false,
  group: "block",
  draggable: true,
  addAttributes() {
    return {
      src: { default: null },
      alt: { default: "" },
      title: { default: null },
      caption: { default: "" },
      credit: { default: "" },
      size: { default: "normal" },
    };
  },
  addNodeView() {
    return ReactNodeViewRenderer(ImageBlock);
  },
});
