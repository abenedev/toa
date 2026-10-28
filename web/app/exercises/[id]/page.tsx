"use client";

import { ChevronLeft } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { Estimated1RMInfo } from "@/components/estimated-1rm-info";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { api, type Exercise, type ExercisePRs } from "@/lib/api";
import { pluralizeRepCounts, repUnit } from "@/lib/rep-format";

export default function ExercisePage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const router = useRouter();
  const [exercise, setExercise] = useState<Exercise | null>(null);
  const [prs, setPrs] = useState<ExercisePRs | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function loadExercise() {
      try {
        const { id } = await params;
        const exerciseId = Number.parseInt(id, 10);
        const [exerciseData, prsData] = await Promise.all([
          api.getExercise(exerciseId),
          api.getExercisePRs(exerciseId),
        ]);
        setExercise(exerciseData);
        setPrs(prsData);
      } catch (error) {
        console.error("Error loading exercise:", error);
      } finally {
        setLoading(false);
      }
    }
    loadExercise();
  }, [params]);

  if (loading) {
    return <div className="container mx-auto p-6">Loading...</div>;
  }

  if (!exercise) {
    return <div className="container mx-auto p-6">Exercise not found</div>;
  }

  const hasPrs =
    (prs?.records.length ?? 0) > 0 ||
    (prs?.reps_per_weight.length ?? 0) > 0 ||
    (prs?.duration_per_weight.length ?? 0) > 0;

  return (
    <div className="container mx-auto space-y-6 p-6">
      <div className="mx-auto flex max-w-2xl items-center justify-between gap-4">
        <div className="flex min-w-0 items-center">
          <Link href="/exercises" className="flex items-center">
            <Button
              variant="ghost"
              className="-ml-4 flex items-center"
              aria-label="Back to exercises"
            >
              <ChevronLeft className="size-8" />
            </Button>
          </Link>
          <h1 className="truncate text-2xl font-bold">{exercise.name}</h1>
        </div>
        {exercise.private ? (
          <Button onClick={() => router.push(`/exercises/${exercise.id}/edit`)}>
            Edit exercise
          </Button>
        ) : (
          <span className="rounded-full bg-muted px-2 py-0.5 text-xs font-medium text-muted-foreground">
            Default
          </span>
        )}
      </div>

      <Card className="mx-auto max-w-2xl">
        <CardContent className="space-y-3">
          {exercise.description && <p>{exercise.description}</p>}
          <p>
            <span className="font-medium">Type:</span> {exercise.type}
          </p>
          <p>
            <span className="font-medium">Equipment:</span>{" "}
            {exercise.equipment.replaceAll("_", " ").toLowerCase()}
          </p>
        </CardContent>
      </Card>

      <Card className="mx-auto max-w-2xl">
        <CardHeader>
          <CardTitle>Personal Records</CardTitle>
        </CardHeader>
        <CardContent>
          {hasPrs ? (
            <div className="space-y-4">
              {prs?.records.map((record) => (
                <div
                  key={record.type}
                  className="flex items-center justify-between border-b pb-2"
                >
                  <div>
                    <div className="font-medium">
                      {record.label}
                      {record.type === "ESTIMATED_1RM" && <Estimated1RMInfo />}
                    </div>
                    {record.date && (
                      <div className="text-xs text-muted-foreground">
                        {new Date(record.date).toLocaleDateString()}
                      </div>
                    )}
                  </div>
                  <div className="text-right font-semibold">
                    {record.type === "MAX_VOLUME" && record.detail
                      ? `${record.value} ${record.unit} (${pluralizeRepCounts(record.detail)})`
                      : `${record.value} ${record.unit}`}
                  </div>
                </div>
              ))}
              {prs?.reps_per_weight.length ? (
                <div>
                  <div className="mb-2 font-medium">Most reps per weight</div>
                  <div className="space-y-1">
                    {prs.reps_per_weight.map((item) => (
                      <div
                        key={item.weight}
                        className="flex items-center justify-between text-sm"
                      >
                        <span>{item.weight} kg</span>
                        <span className="flex items-center gap-2">
                          <span className="font-semibold">
                            {item.reps} {repUnit(item.reps)}
                          </span>
                          {item.date && (
                            <span className="text-xs text-muted-foreground">
                              {new Date(item.date).toLocaleDateString()}
                            </span>
                          )}
                        </span>
                      </div>
                    ))}
                  </div>
                </div>
              ) : null}
              {prs?.duration_per_weight.length ? (
                <div>
                  <div className="mb-2 font-medium">
                    Longest duration per weight
                  </div>
                  <div className="space-y-1">
                    {prs.duration_per_weight.map((item) => (
                      <div
                        key={item.weight}
                        className="flex items-center justify-between text-sm"
                      >
                        <span>{item.weight} kg</span>
                        <span className="flex items-center gap-2">
                          <span className="font-semibold">
                            {item.duration} s
                          </span>
                          {item.date && (
                            <span className="text-xs text-muted-foreground">
                              {new Date(item.date).toLocaleDateString()}
                            </span>
                          )}
                        </span>
                      </div>
                    ))}
                  </div>
                </div>
              ) : null}
            </div>
          ) : (
            <p className="text-sm text-muted-foreground">
              No personal records yet — log some workouts to see them here.
            </p>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
