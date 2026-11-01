"use client";

import Link from "next/link";
import { StatusView } from "@/components/status/StatusView";
import styles from "@/components/editor/cms.module.css";

export default function WriteError({
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <div className={styles.shell}>
      <StatusView
        tone="ink"
        kicker="Write"
        title="The editor tripped."
        body="Couldn’t load the write desk. Try again, or bounce back to your pieces."
        actions={[{ href: "/write", label: "Write home" }]}
      />
      <button
        type="button"
        className={styles.secondary}
        onClick={() => reset()}
        style={{ margin: "0 24px 32px", width: "fit-content" }}
      >
        Try again
      </button>
      <Link href="/" className={styles.back} style={{ margin: "0 24px 40px" }}>
        Home
      </Link>
    </div>
  );
}
