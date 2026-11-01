import Markdown from "react-markdown";
import { Navbar } from "@/components/Navbar";
import { legalMarkdown } from "@/lib/legal/markdown";
import type { LegalDocument } from "@/lib/legal/types";
import styles from "./legal.module.css";

export function LegalDocumentView({ document }: { document: LegalDocument }) {
  return (
    <>
      <Navbar />
      <main className={styles.page}>
        <article className={styles.doc}>
          <Markdown>{legalMarkdown(document)}</Markdown>
        </article>
      </main>
    </>
  );
}
