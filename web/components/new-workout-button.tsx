"use client";

import { useRouter } from "next/navigation";
import { useAdGate } from "@/components/ad-interstitial";
import { Button } from "@/components/ui/button";

export function NewWorkoutButton() {
  const router = useRouter();
  const { trigger, dialog } = useAdGate(() => router.push("/workouts/new"));

  return (
    <>
      <Button onClick={trigger}>New workout</Button>
      {dialog}
    </>
  );
}
