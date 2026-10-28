"use client";

import { Pencil, Trash2 } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { api, type Workout } from "@/lib/api";

export function PlannedWorkoutActions({ workout }: { workout: Workout }) {
  const router = useRouter();

  const handleDelete = async () => {
    if (!window.confirm(`Delete planned workout "${workout.name}"?`)) return;
    await api.deleteWorkout(workout.id);
    router.push("/workouts");
  };

  return (
    <div className="flex items-center gap-2">
      <Link href={`/workouts/${workout.id}/edit`}>
        <Button variant="outline" title="Edit workout">
          <Pencil aria-hidden="true" />
        </Button>
      </Link>
      <Button
        variant="destructive"
        className="border-destructive/40"
        onClick={handleDelete}
        title="Delete workout"
      >
        <Trash2 className="size-4" />
      </Button>
    </div>
  );
}
