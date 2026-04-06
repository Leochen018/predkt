/** @type {import('next').NextConfig} */
const nextConfig = {
  // 1. Enable Static Export (This creates the 'out' folder)
  output: 'export',

  // 2. Add trailing slashes (Fixes 404s on many static hosts)
  trailingSlash: true,

  // 3. Disable Image Optimization (Required for static export)
  images: {
    unoptimized: true,
  },

  // 4. Optional: Ignore linting/typescript errors during build 
  // (Only use this if your build is failing due to minor code style issues)
  eslint: {
    ignoreDuringBuilds: true,
  },
  typescript: {
    ignoreBuildErrors: true,
  },
};

module.exports = nextConfig;