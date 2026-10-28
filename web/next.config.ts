import type { NextConfig } from "next";

const nextConfig: NextConfig = {
	// Allow API calls to the backend
	async rewrites() {
		return [
			{
				source: "/api/:path*",
				destination: "https://toa-5gzn.onrender.com/:path*",
			},
		];
	},
};

export default nextConfig;
