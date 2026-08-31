"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState, type FormEvent } from "react";
import { Navbar } from "@/components/Navbar";
import { useSession } from "@/components/providers/SessionProvider";
import { ApiError } from "@/lib/api/types";
import styles from "./login.module.css";

export default function LoginPage() {
  const { status, login } = useSession();
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (status === "signedIn") {
      router.replace("/");
    }
  }, [status, router]);

  if (status === "loading" || status === "signedIn") {
    return null;
  }

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setBusy(true);
    try {
      await login({ email: email.trim(), password });
      router.replace("/");
    } catch (err) {
      const message =
        err instanceof ApiError
          ? err.message
          : "Couldnt log you in — try again";
      setError(message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className={styles.page}>
      <Navbar />

      <main className={styles.main}>
        <div className={styles.content}>
          <p className="section-kicker">Sign in</p>
          <h1 className={styles.title}>Log in.</h1>
          <p className={styles.lede}>
            Use the email and password tied to your Niche account.{" "}
            <Link
              href="https://open.nichemusic.app/signup"
              target="_blank"
              className="underline-link underline-link--inline"
            >
              Don&apos;t have one?
            </Link>
          </p>

          <form className={styles.form} onSubmit={onSubmit}>
            <label className="form-field">
              <span className="form-field__label">Email</span>
              <input
                className="form-field__input"
                type="email"
                autoComplete="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="you@email.com"
              />
            </label>

            <label className="form-field" htmlFor="login-password">
              <span className="form-field__label">Password</span>
              <input
                id="login-password"
                className="form-field__input"
                type="password"
                autoComplete="current-password"
                required
                minLength={8}
                value={password}
                onChange={(e) => setPassword(e.target.value)}
              />
            </label>

            {error && <p className={styles.error}>{error}</p>}

            <div className={styles.actions}>
              <button
                type="submit"
                className="cta-primary"
                disabled={busy}
              >
                {busy ? "Logging in…" : "Log in"}
              </button>
              <Link href="/" className="underline-link underline-link--action">
                Back to home
              </Link>
            </div>
          </form>
        </div>
      </main>
    </div>
  );
}
