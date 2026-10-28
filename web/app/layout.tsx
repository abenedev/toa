import type { Metadata } from "next";
import { Geist, Geist_Mono, Inter } from "next/font/google";
import Script from "next/script";
import "./globals.css";
import { AuthGuard } from "@/components/auth-guard";
import { Navigation } from "@/components/navigation";
import { AuthProvider } from "@/contexts/AuthContext";
import { cn } from "@/lib/utils";

const inter = Inter({ subsets: ["latin"], variable: "--font-sans" });

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "Workout Tracker",
  description: "Track your workouts and progress",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html
      lang="en"
      suppressHydrationWarning
      className={cn(
        "h-full",
        "antialiased",
        geistSans.variable,
        geistMono.variable,
        "font-sans",
        inter.variable,
      )}
    >
      <body className="min-h-full flex flex-col">
        <Script id="theme-bootstrap" strategy="beforeInteractive">
          {`(() => {
						const savedTheme = window.localStorage.getItem("theme");
						const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
						document.documentElement.classList.toggle("dark", savedTheme === "dark" || (!savedTheme && prefersDark));
					})();`}
        </Script>
        <AuthProvider>
          <Navigation />
          <AuthGuard>
            <main className="flex-1 pb-20">{children}</main>
          </AuthGuard>
        </AuthProvider>
      </body>
    </html>
  );
}
