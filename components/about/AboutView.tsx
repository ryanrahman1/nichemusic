"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { CoverImage } from "@/components/home/CoverImage";
import {
  MARQUEE_WORDS,
  OPENING_PHRASES,
  TEAM,
} from "@/lib/about/team";
import styles from "./about.module.css";

export type CollagePiece = {
  id: string;
  kind: "story" | "review" | "track";
  title: string;
  meta?: string;
  image?: string | null;
  href?: string;
};

const SPRINKLE = [
  { className: "sprinkleA", size: "72px" },
  { className: "sprinkleB", size: "64px" },
  { className: "sprinkleC", size: "68px" },
  { className: "sprinkleD", size: "72px" },
] as const;

export function AboutView({ collage }: { collage: CollagePiece[] }) {
  const images = collage.filter((item) => item.image).slice(0, 4);

  return (
    <main className={styles.page}>
      <section className={styles.hero}>
        <p className={styles.heroKicker}>About Niche</p>
        <h1 className={styles.heroLead}>
          <span className={styles.heroLine}>Niche is for finding music</span>
          <span className={styles.heroCycle}>
            <ScramblePhrase phrases={OPENING_PHRASES} />
          </span>
        </h1>
      </section>

      <section className={styles.statement}>
        <h2>
          Streaming made everything available.
          <br />
          It didn&apos;t make everything discoverable.
        </h2>
        <p>
          Niche exists because the underground still moves through people —
          writers, artists, and listeners pointing each other at the next
          record. The desk documents it. The app is where the scene actually
          lives.
        </p>
      </section>

      <section className={styles.wordart}>
        <div className={styles.poster}>
          <p className={`${styles.word} ${styles.wordEditorial}`}>EDITORIAL</p>
          <p className={`${styles.word} ${styles.wordArtists}`}>ARTISTS</p>
          <p className={`${styles.word} ${styles.wordDiscovery}`}>DISCOVERY</p>
          <p className={`${styles.word} ${styles.wordPeople}`}>PEOPLE</p>
          <p className={`${styles.word} ${styles.wordNiche}`}>NICHE</p>

          {images.map((item, i) => {
            const slot = SPRINKLE[i];
            if (!slot) return null;
            return (
              <Sprinkle
                key={item.id}
                piece={item}
                className={styles[slot.className]}
              />
            );
          })}
        </div>
      </section>

      <ScrollMarquee />

      <section className={styles.team}>
        <h2>The people behind Niche</h2>
        <div className={styles.credits}>
          {TEAM.map((person) => (
            <TeamCredit key={person.name} person={person} />
          ))}
        </div>
      </section>

      <section className={styles.close}>
        <h2>Niche is still early.</h2>
        <p>
          We&apos;re building it with the artists, writers, and listeners who
          are here early too.
        </p>
        <div className={styles.ctas}>
          <Link href="/download" className={styles.ctaFill}>
            Get Niche
          </Link>
          <Link href="/write" className={styles.ctaGhost}>
            Become a writer
          </Link>
        </div>
      </section>
    </main>
  );
}

const PHRASE_HOLD_MS = 3400;

function ScramblePhrase({ phrases }: { phrases: readonly string[] }) {
  const [index, setIndex] = useState(0);
  const [phase, setPhase] = useState<"hold" | "down" | "up">("hold");
  const [progress, setProgress] = useState(0);
  const reduce = usePrefersReducedMotion();
  const text = phrases[index] ?? phrases[0];

  useEffect(() => {
    if (reduce || phase !== "hold") return;
    let frame = 0;
    const started = performance.now();

    // fill the bar then kick the slide
    const hold = (now: number) => {
      const elapsed = now - started;
      setProgress(Math.min(1, elapsed / PHRASE_HOLD_MS));
      if (elapsed >= PHRASE_HOLD_MS) {
        setProgress(0);
        setPhase("down");
        return;
      }
      frame = window.requestAnimationFrame(hold);
    };

    setProgress(0);
    frame = window.requestAnimationFrame(hold);
    return () => window.cancelAnimationFrame(frame);
  }, [index, phase, reduce]);

  function onPhraseAnimEnd() {
    if (phase === "down") {
      setIndex((i) => (i + 1) % phrases.length);
      setPhase("up");
      return;
    }
    if (phase === "up") {
      setPhase("hold");
    }
  }

  const motion =
    phase === "down" ? styles.heroPhraseDown : phase === "up" ? styles.heroPhraseUp : "";

  return (
    <span className={styles.heroCycleInner}>
      <span className={styles.heroPhraseClip}>
        <span
          key={`${index}-${phase}`}
          className={`${styles.heroPhrase} ${motion}`}
          aria-live="polite"
          onAnimationEnd={onPhraseAnimEnd}
        >
          {text}
        </span>
      </span>
      {reduce ? null : (
        <span
          className={phase === "hold" ? styles.heroBar : `${styles.heroBar} ${styles.heroBarIdle}`}
          aria-hidden
        >
          <span
            className={styles.heroBarFill}
            style={{ transform: `scaleX(${phase === "hold" ? progress : 0})` }}
          />
        </span>
      )}
    </span>
  );
}

function Sprinkle({
  piece,
  className,
}: {
  piece?: CollagePiece;
  className: string;
}) {
  if (!piece?.image) return null;
  const body = <CoverImage src={piece.image} alt="" sizes="120px" />;
  const cls = `${styles.sprinkle} ${className}`;
  if (piece.href) {
    return (
      <Link href={piece.href} className={cls} aria-label={piece.title}>
        {body}
      </Link>
    );
  }
  return <div className={cls}>{body}</div>;
}

function ScrollMarquee() {
  const line = MARQUEE_WORDS.flatMap((word) => [word, "—"]);

  return (
    <div className={styles.marqueeWrap} aria-hidden>
      <div className={styles.marqueeTrack}>
        {[0, 1].map((copy) => (
          <span key={copy} className={styles.marqueeCopy}>
            {line.map((word, i) => (
              <span
                key={`${copy}-${i}`}
                className={`${styles.marqueeItem} ${word === "—" ? styles.marqueeDot : ""}`}
              >
                {word}
              </span>
            ))}
          </span>
        ))}
      </div>
    </div>
  );
}

function TeamCredit({ person }: { person: (typeof TEAM)[number] }) {
  const ref = useRef<HTMLElement>(null);
  const [on, setOn] = useState(false);

  useEffect(() => {
    const node = ref.current;
    if (!node) return;
    const io = new IntersectionObserver(
      ([entry]) => {
        if (entry?.isIntersecting && window.matchMedia("(max-width: 720px)").matches) {
          setOn(true);
        }
      },
      { threshold: 0.55 },
    );
    io.observe(node);
    return () => io.disconnect();
  }, []);

  const [album, artist] = splitListen(person.listening);

  return (
    <article
      ref={ref}
      className={on ? `${styles.person} ${styles.personOn}` : styles.person}
    >
      <div className={styles.portrait} aria-hidden>
        <span className={styles.portraitMark}>{person.initials}</span>
      </div>
      <div className={styles.personCopy}>
        <h3>{person.name}</h3>
        <p className={styles.role}>{person.role}</p>
        <div className={styles.listen}>
          <p className={styles.listenLabel}>{person.listeningLabel}</p>
          <p>
            <em>{album}</em>
            {artist ? ` — ${artist}` : ""}
          </p>
        </div>
      </div>
    </article>
  );
}

function splitListen(value: string) {
  const [album, artist] = value.split(" — ");
  return [album ?? value, artist ?? ""] as const;
}

function usePrefersReducedMotion() {
  const [reduce, setReduce] = useState(false);
  useEffect(() => {
    const mq = window.matchMedia("(prefers-reduced-motion: reduce)");
    setReduce(mq.matches);
    const onChange = () => setReduce(mq.matches);
    mq.addEventListener("change", onChange);
    return () => mq.removeEventListener("change", onChange);
  }, []);
  return reduce;
}
