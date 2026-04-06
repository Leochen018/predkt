/** @type {import('next').NextConfig} */
const nextConfig = {
  // Removed static export to support dynamic routes like /verify?token=xxx
  // This allows server-side rendering which is needed for email verification
}
module.exports = nextConfig
