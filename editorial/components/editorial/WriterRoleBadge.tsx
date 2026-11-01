import { writerRoleLabel } from "@/lib/editorial/writers";
import styles from "./writer-role-badge.module.css";

export function WriterRoleBadge({ role }: { role?: string | null }) {
  const label = writerRoleLabel(role);
  if (!label) return null;

  // contributors stay quieter so editors/verified pop a bit more
  const muted = label === "Contributor";

  return (
    <span className={muted ? `${styles.badge} ${styles.muted}` : styles.badge}>
      {label}
    </span>
  );
}
