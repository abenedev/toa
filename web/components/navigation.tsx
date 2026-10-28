"use client";

import { Dumbbell, Library, Settings } from "lucide-react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";

export function Navigation() {
  const pathname = usePathname();

  const normalizedPath =
    pathname.endsWith("/") && pathname !== "/"
      ? pathname.slice(0, -1)
      : pathname;

  if (
    normalizedPath === "/login" ||
    normalizedPath === "/signup" ||
    normalizedPath === "/" ||
    normalizedPath.includes("active") ||
    normalizedPath.includes("edit") ||
    normalizedPath.includes("new")
  ) {
    return null;
  }

  const isWorkouts = normalizedPath.startsWith("/workouts");
  const isExercises = normalizedPath.startsWith("/exercises");
  const isSettings =
    normalizedPath.startsWith("/settings") ||
    normalizedPath.startsWith("/account");

  return (
    <nav className="fixed bottom-0 inset-x-0 z-50 border-t border-border bg-background/95 backdrop-blur-md pb-[env(safe-area-inset-bottom)] shadow-lg transition-all">
      <div className="max-w-md mx-auto flex items-center justify-around h-16 px-4">
        <Link
          href="/workouts"
          className={cn(
            "flex flex-col items-center justify-center gap-1 flex-1 py-1 transition-colors group",
            isWorkouts
              ? "text-primary font-semibold"
              : "text-muted-foreground hover:text-foreground",
          )}
        >
          <Dumbbell
            className={cn(
              "size-5 transition-transform group-active:scale-95",
              isWorkouts && "stroke-[2.5px]",
            )}
          />
          <span className="text-[11px] leading-tight">Workouts</span>
        </Link>

        <Link
          href="/exercises"
          className={cn(
            "flex flex-col items-center justify-center gap-1 flex-1 py-1 transition-colors group",
            isExercises
              ? "text-primary font-semibold"
              : "text-muted-foreground hover:text-foreground",
          )}
        >
          <Library
            className={cn(
              "size-5 transition-transform group-active:scale-95",
              isExercises && "stroke-[2.5px]",
            )}
          />
          <span className="text-[11px] leading-tight">Exercises</span>
        </Link>

        <Link
          href="/settings"
          className={cn(
            "flex flex-col items-center justify-center gap-1 flex-1 py-1 transition-colors group",
            isSettings
              ? "text-primary font-semibold"
              : "text-muted-foreground hover:text-foreground",
          )}
        >
          <Settings
            className={cn(
              "size-5 transition-transform group-active:scale-95",
              isSettings && "stroke-[2.5px]",
            )}
          />
          <span className="text-[11px] leading-tight">Settings</span>
        </Link>
      </div>
    </nav>
  );
}
