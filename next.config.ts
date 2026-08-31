import type { NextConfig } from "next";

const apiTarget = process.env.API_PROXY_TARGET || "http://localhost:3932";

const nextConfig: NextConfig = {
  images: {
    remotePatterns: [
      { protocol: "https", hostname: "nichemusic.app" },
      { protocol: "https", hostname: "www.nichemusic.app" },
      { protocol: "https", hostname: "stream.nichemusic.app" },
      { protocol: "https", hostname: "**.nichemusic.app" },
      { protocol: "https", hostname: "**.mzstatic.com" },
      { protocol: "https", hostname: "i.scdn.co" },
    ],
  },
  async rewrites() {
    return [
      {
        source: "/api/:path*",
        destination: `${apiTarget}/:path*`,
      },
    ];
  },
};

export default nextConfig;
