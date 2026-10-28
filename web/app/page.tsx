import Link from "next/link";
import { Button } from "@/components/ui/button";

export default function Home() {
  return (
    <div className="flex min-h-[calc(100vh-4rem)] flex-col items-center justify-center p-6 text-center">
      <div className="max-w-md space-y-6">
        <h1 className="text-4xl font-bold tracking-tight sm:text-5xl">
          Workout Tracker
        </h1>
        <p className="text-muted-foreground text-lg">
          Track your workouts, log exercises, and reach your fitness goals.
        </p>
        <div className="flex items-center justify-center gap-4 pt-2">
          <Link href="/login">
            <Button size="lg" className="w-32">
              Log in
            </Button>
          </Link>
          <Link href="/signup">
            <Button size="lg" variant="outline" className="w-32">
              Sign Up
            </Button>
          </Link>
        </div>
      </div>
    </div>
  );
}
