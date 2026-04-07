/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'export', // <--- This MUST be exactly this
  trailingSlash: true,
  images: {
    unoptimized: true,
  },
}
module.exports = nextConfig