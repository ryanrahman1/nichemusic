import Image from "next/image";

// keep this in sync with next.config images.remotePatterns
const OPTIMIZED_HOSTS = new Set([
  "nichemusic.app",
  "www.nichemusic.app",
  "stream.nichemusic.app",
  "i.scdn.co",
]);

function canOptimize(src: string) {
  try {
    const host = new URL(src).hostname.toLowerCase();
    if (OPTIMIZED_HOSTS.has(host)) return true;
    return host.endsWith(".mzstatic.com") || host.endsWith(".nichemusic.app");
  } catch {
    return false;
  }
}

export function CoverImage({
  src,
  alt,
  sizes,
  priority = false,
  className,
}: {
  src: string;
  alt: string;
  sizes: string;
  priority?: boolean;
  className?: string;
}) {
  // skip next/image if the host aint on the allowlist so the page doesnt eat it
  if (canOptimize(src)) {
    return (
      <Image
        src={src}
        alt={alt}
        fill
        sizes={sizes}
        // priority already forces eager load for lcp
        priority={priority}
        className={className}
      />
    );
  }

  return (
    // eslint-disable-next-line @next/next/no-img-element
    <img
      src={src}
      alt={alt}
      className={className}
      loading={priority ? "eager" : "lazy"}
      fetchPriority={priority ? "high" : undefined}
    />
  );
}
