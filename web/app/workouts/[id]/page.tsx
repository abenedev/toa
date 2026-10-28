"use client";

import { ChevronLeft } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { PlannedWorkoutActions } from "@/components/planned-workout-actions";
import { StartWorkoutButton } from "@/components/start-workout-button";
import { Button } from "@/components/ui/button";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import {
  api,
  type DurationSet,
  type Exercise,
  type RepSet,
  type Workout,
  type WorkoutExercise,
} from "@/lib/api";
import { cn } from "@/lib/utils";
import {
  getDescendedPerformedWorkouts,
  getHeaviestTotalVolume,
} from "@/lib/workout-volume";

const SET_TYPE_COLORS: Record<string, string> = {
  WARMUP:
    "bg-amber-100 border-amber-300 text-amber-900 dark:bg-amber-950/70 dark:border-amber-800 dark:text-amber-300",
  FAILURE:
    "bg-rose-100 border-rose-300 text-rose-900 dark:bg-rose-950/70 dark:border-rose-800 dark:text-rose-300",
  DROPSET:
    "bg-blue-100 border-blue-300 text-blue-900 dark:bg-blue-950/70 dark:border-blue-800 dark:text-blue-300",
  SUPERSET:
    "bg-purple-100 border-purple-300 text-purple-900 dark:bg-purple-950/70 dark:border-purple-800 dark:text-purple-300",
  WORKSET:
    "bg-slate-100 border-slate-300 text-slate-800 dark:bg-slate-800 dark:border-slate-700 dark:text-slate-200",
};

export default function WorkoutDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const router = useRouter();
  const [workout, setWorkout] = useState<Workout | null>(null);
  const [exercises, setExercises] = useState<Exercise[]>([]);
  const [workoutExercises, setWorkoutExercises] = useState<WorkoutExercise[]>(
    [],
  );
  const [repSets, setRepSets] = useState<RepSet[]>([]);
  const [durationSets, setDurationSets] = useState<DurationSet[]>([]);
  const [workoutVolume, setWorkoutVolume] = useState<number | null>(null);
  const [heaviestTotalVolume, setHeaviestTotalVolume] = useState<number | null>(
    null,
  );
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function loadData() {
      try {
        const { id } = await params;
        const workoutId = Number.parseInt(id, 10);

        const [
          workoutData,
          exercisesData,
          workoutExercisesData,
          repSetsData,
          durationSetsData,
        ] = await Promise.all([
          api.getWorkout(workoutId),
          api.getExercises(),
          api.getWorkoutExercises(workoutId),
          api.getRepSets(workoutId),
          api.getDurationSets(workoutId),
        ]);

        if (!workoutData) {
          router.push("/workouts");
          return;
        }

        setWorkout(workoutData);
        setExercises(exercisesData);
        setWorkoutExercises(workoutExercisesData);
        setRepSets(repSetsData);
        setDurationSets(durationSetsData);

        if (workoutData.planned) {
          const [plannedVolume, allWorkouts]: [
            { workout_id: number; total_volume: number },
            Workout[],
          ] = await Promise.all([
            api.getWorkoutVolume(workoutData.id),
            api.getWorkouts(),
          ]);
          const descendedWorkouts = getDescendedPerformedWorkouts(
            workoutData.id,
            allWorkouts,
          );
          const descendedVolumes = await Promise.all(
            descendedWorkouts.map((descendedWorkout) =>
              api.getWorkoutVolume(descendedWorkout.id),
            ),
          );
          setWorkoutVolume(plannedVolume.total_volume);
          setHeaviestTotalVolume(
            getHeaviestTotalVolume(
              descendedVolumes.map((volume) => volume.total_volume),
            ),
          );
        } else {
          const volume = await api.getWorkoutVolume(workoutData.id);
          setWorkoutVolume(volume.total_volume);
        }
      } catch (error) {
        console.error("Failed to load data:", error);
        router.push("/workouts");
      } finally {
        setLoading(false);
      }
    }
    loadData();
  }, [params, router]);

  if (loading || !workout) {
    return (
      <div className="container mx-auto p-6">
        <p>Loading...</p>
      </div>
    );
  }

  const workoutRepSets = repSets.filter((set) => set.workout_id === workout.id);
  const workoutDurationSets = durationSets.filter(
    (set) => set.workout_id === workout.id,
  );

  const exerciseSets = new Map<number, (RepSet | DurationSet)[]>();
  for (const workoutExercise of [...workoutExercises].sort(
    (a, b) => a.position - b.position,
  )) {
    const hasLoggedSets =
      workoutRepSets.some(
        (set) => set.exercise_id === workoutExercise.exercise_id,
      ) ||
      workoutDurationSets.some(
        (set) => set.exercise_id === workoutExercise.exercise_id,
      );
    if (!workout.planned && !hasLoggedSets) continue;
    if (!exerciseSets.has(workoutExercise.exercise_id)) {
      exerciseSets.set(workoutExercise.exercise_id, []);
    }
  }
  const orderedSets = [...workoutRepSets, ...workoutDurationSets].sort(
    (a, b) => a.position - b.position,
  );

  for (const set of orderedSets) {
    if (!exerciseSets.has(set.exercise_id)) {
      exerciseSets.set(set.exercise_id, []);
    }
    exerciseSets.get(set.exercise_id)?.push(set);
  }

  return (
    <div className="container mx-auto p-6">
      <div>
        <div className="flex justify-between items-center mb-4">
          <div className="flex items-center">
            <Link href="/workouts" className="flex items-center">
              <Button variant="ghost" className="-ml-4 flex items-center">
                <ChevronLeft className="size-8" />
              </Button>
            </Link>
            <h2 className="text-2xl font-bold">{workout.name}</h2>
          </div>
          <div className="flex items-center gap-2">
            {workout.planned && <PlannedWorkoutActions workout={workout} />}
            <StartWorkoutButton workoutId={workout.id} />
          </div>
        </div>

        <div>
          <div className="space-y-2 text-sm text-muted-foreground mb-4">
            <p>
              <strong>{workout.planned ? "Created on" : "Completed on"}</strong>{" "}
              {new Intl.DateTimeFormat(undefined, {
                dateStyle: "medium",
                timeStyle: "short",
              }).format(new Date(workout.creation_date))}
            </p>
            {workoutVolume !== null && (
              <>
                <p>
                  <strong>
                    {workout.planned
                      ? "Planned total volume:"
                      : "Total volume:"}
                  </strong>{" "}
                  {new Intl.NumberFormat(undefined, {
                    maximumFractionDigits: 2,
                  }).format(workoutVolume)}{" "}
                  kg
                </p>
                {workout.planned && (
                  <p>
                    <strong>Heaviest total volume:</strong>{" "}
                    {heaviestTotalVolume === null
                      ? "—"
                      : `${new Intl.NumberFormat(undefined, {
                          maximumFractionDigits: 2,
                        }).format(heaviestTotalVolume)} kg`}
                  </p>
                )}
              </>
            )}
            {workout.rpe && (
              <p>
                <strong>RPE:</strong> {workout.rpe}
              </p>
            )}
            {workout.description && <p>{workout.description}</p>}
            {workout.note && (
              <div className="p-3 bg-muted/40 border rounded-lg text-sm text-foreground">
                <span className="font-semibold text-muted-foreground mr-1.5">
                  Post Workout Note:
                </span>
                {workout.note}
              </div>
            )}
          </div>

          <div className="space-y-6">
            {exerciseSets.size === 0 ? (
              <p className="text-muted-foreground">
                No exercises recorded for this workout yet.
              </p>
            ) : (
              Array.from(exerciseSets.entries()).map(([exerciseId, sets]) => {
                const exercise = exercises.find((e) => e.id === exerciseId);
                if (!exercise) return null;

                const isRepExercise = exercise.type === "REPS";
                const weightLabel =
                  exercise.equipment === "ASSISTED_BODYWEIGHT"
                    ? "-kg"
                    : exercise.equipment === "BODYWEIGHT"
                      ? "+kg"
                      : "kg";

                return (
                  <div key={exerciseId}>
                    <h3 className="text-lg font-semibold mb-2">
                      {exercise.name}
                    </h3>
                    {(() => {
                      const we = workoutExercises.find(
                        (w) => w.exercise_id === exerciseId,
                      );
                      return we?.note ? (
                        <p className="text-sm text-muted-foreground mb-2 italic">
                          {we.note}
                        </p>
                      ) : null;
                    })()}

                    {sets.length === 0 ? (
                      <p className="text-sm text-muted-foreground">
                        No sets completed for this exercise.
                      </p>
                    ) : (
                      <Table>
                        <TableHeader>
                          <TableRow>
                            <TableHead>Set</TableHead>
                            <TableHead>Type</TableHead>
                            <TableHead>Weight ({weightLabel})</TableHead>
                            {isRepExercise && <TableHead>Reps</TableHead>}
                            {!isRepExercise && (
                              <TableHead>Duration (s)</TableHead>
                            )}
                            <TableHead>RPE</TableHead>
                            <TableHead>Rest (s)</TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {sets.map((set, index) => {
                            const repSet =
                              isRepExercise && "reps" in set ? set : null;

                            return (
                              <TableRow key={set.id}>
                                <TableCell>{index + 1}</TableCell>
                                <TableCell>
                                  <span
                                    className={cn(
                                      "inline-block px-2 py-0.5 rounded text-xs font-semibold border",
                                      SET_TYPE_COLORS[set.type_] ||
                                        "bg-muted text-muted-foreground",
                                    )}
                                  >
                                    {set.type_}
                                  </span>
                                </TableCell>
                                <TableCell>{set.weight ?? 0}</TableCell>
                                {isRepExercise && (
                                  <TableCell>
                                    {repSet ? (repSet.reps ?? 0) : 0}
                                  </TableCell>
                                )}
                                {!isRepExercise && (
                                  <TableCell>
                                    {"duration" in set
                                      ? (set.duration ?? 0)
                                      : 0}
                                  </TableCell>
                                )}
                                <TableCell>{set.rpe ?? 0}</TableCell>
                                <TableCell>{set.rest ?? 0}</TableCell>
                              </TableRow>
                            );
                          })}
                        </TableBody>
                      </Table>
                    )}
                  </div>
                );
              })
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
