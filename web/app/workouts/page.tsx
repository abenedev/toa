"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { NewWorkoutButton } from "@/components/new-workout-button";
import { Card, CardContent } from "@/components/ui/card";
import {
  api,
  type DurationSet,
  type Exercise,
  type RepSet,
  type Workout,
} from "@/lib/api";

function getExerciseSetCount(
  workoutId: number,
  exerciseId: number,
  repSets: RepSet[],
  durationSets: DurationSet[],
): number {
  const exerciseRepSets = repSets.filter(
    (s) => s.workout_id === workoutId && s.exercise_id === exerciseId,
  );
  const exerciseDurationSets = durationSets.filter(
    (s) => s.workout_id === workoutId && s.exercise_id === exerciseId,
  );
  return exerciseRepSets.length + exerciseDurationSets.length;
}

export default function WorkoutsPage() {
  const [workouts, setWorkouts] = useState<Workout[]>([]);
  const [exercises, setExercises] = useState<Exercise[]>([]);
  const [repSets, setRepSets] = useState<RepSet[]>([]);
  const [durationSets, setDurationSets] = useState<DurationSet[]>([]);
  const [workoutExercises, setWorkoutExercises] = useState<
    { workout_id: number; exercise_id: number; position: number }[]
  >([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function loadData() {
      try {
        const [
          workoutsData,
          exercisesData,
          repSetsData,
          durationSetsData,
          workoutExercisesData,
        ] = await Promise.all([
          api.getWorkouts(),
          api.getExercises(),
          api.getRepSets(),
          api.getDurationSets(),
          api.getWorkoutExercises(),
        ]);
        setWorkouts(workoutsData);
        setExercises(exercisesData);
        setRepSets(repSetsData);
        setDurationSets(durationSetsData);
        setWorkoutExercises(workoutExercisesData);
      } catch (error) {
        console.error("Failed to load data:", error);
      } finally {
        setLoading(false);
      }
    }
    loadData();
  }, []);

  const plannedWorkouts = workouts
    .filter((w) => w.planned)
    .sort(
      (a, b) =>
        new Date(b.creation_date).getTime() -
        new Date(a.creation_date).getTime(),
    );
  const completedWorkouts = workouts
    .filter((w) => !w.planned)
    .sort(
      (a, b) =>
        new Date(b.creation_date).getTime() -
        new Date(a.creation_date).getTime(),
    );

  if (loading) {
    return (
      <div className="container mx-auto p-6">
        <p>Loading...</p>
      </div>
    );
  }

  return (
    <div className="container mx-auto p-6 space-y-4">
      <div className="flex items-center justify-between">
        <h2 className="text-2xl font-bold">Workouts</h2>
        <NewWorkoutButton />
      </div>
      {/* Planned Workouts Section */}
      <div>
        {plannedWorkouts.length === 0 ? (
          <p className="text-muted-foreground">No planned workouts.</p>
        ) : (
          <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
            {plannedWorkouts.map((workout) => {
              // Get all exercises for this workout
              const workoutRepSets = repSets.filter(
                (s) => s.workout_id === workout.id,
              );
              const workoutDurationSets = durationSets.filter(
                (s) => s.workout_id === workout.id,
              );

              // Get unique exercise IDs
              const exerciseIds = new Set([
                ...workoutExercises
                  .filter((item) => item.workout_id === workout.id)
                  .map((item) => item.exercise_id),
                ...workoutRepSets.map((s) => s.exercise_id),
                ...workoutDurationSets.map((s) => s.exercise_id),
              ]);

              // Get exercise set counts
              const exerciseData = Array.from(exerciseIds)
                .map((exerciseId) => {
                  const exercise = exercises.find((e) => e.id === exerciseId);
                  if (!exercise) return null;
                  const setCount = getExerciseSetCount(
                    workout.id,
                    exerciseId,
                    repSets,
                    durationSets,
                  );
                  return { exercise, setCount };
                })
                .filter(
                  (data): data is { exercise: Exercise; setCount: number } =>
                    data !== null,
                );

              return (
                <Link key={workout.id} href={`/workouts/${workout.id}`}>
                  <Card className="hover:shadow-lg transition-shadow cursor-pointer h-full">
                    <CardContent>
                      <h3 className="text-lg font-semibold">{workout.name}</h3>
                      {workout.description && <p>{workout.description}</p>}
                      {exerciseData.length > 0 ? (
                        <ul className="text-sm text-muted-foreground">
                          {exerciseData.map(({ exercise, setCount }) => (
                            <li key={`${workout.id}-${exercise.id}`}>
                              {setCount} x {exercise.name}
                            </li>
                          ))}
                        </ul>
                      ) : (
                        <p className="text-sm text-muted-foreground">
                          No exercises added yet.
                        </p>
                      )}
                    </CardContent>
                  </Card>
                </Link>
              );
            })}
          </div>
        )}
      </div>

      {/* History Section */}
      <div>
        <h2 className="text-2xl font-bold mb-4">History</h2>
        {completedWorkouts.length === 0 ? (
          <p className="text-muted-foreground">No completed workouts yet.</p>
        ) : (
          <div>
            {completedWorkouts.map((workout) => {
              // Get all exercises for this workout
              const workoutRepSets = repSets.filter(
                (s) => s.workout_id === workout.id,
              );
              const workoutDurationSets = durationSets.filter(
                (s) => s.workout_id === workout.id,
              );

              // Get unique exercise IDs
              const exerciseIds = new Set([
                ...workoutExercises
                  .filter(
                    (item) =>
                      item.workout_id === workout.id &&
                      getExerciseSetCount(
                        workout.id,
                        item.exercise_id,
                        repSets,
                        durationSets,
                      ) > 0,
                  )
                  .map((item) => item.exercise_id),
                ...workoutRepSets.map((s) => s.exercise_id),
                ...workoutDurationSets.map((s) => s.exercise_id),
              ]);

              // Get exercise set counts
              const exerciseData = Array.from(exerciseIds)
                .map((exerciseId) => {
                  const exercise = exercises.find((e) => e.id === exerciseId);
                  if (!exercise) return null;
                  const setCount = getExerciseSetCount(
                    workout.id,
                    exerciseId,
                    repSets,
                    durationSets,
                  );
                  return { exercise, setCount };
                })
                .filter(
                  (data): data is { exercise: Exercise; setCount: number } =>
                    data !== null,
                );

              return (
                <Link key={workout.id} href={`/workouts/${workout.id}`}>
                  <Card className="hover:shadow-lg transition-shadow cursor-pointer mb-4">
                    <CardContent>
                      <div className="flex justify-between items-start">
                        <h3 className="text-lg font-semibold">
                          {workout.name}
                        </h3>
                        <div className="text-sm text-muted-foreground ml-4 text-right">
                          <div>
                            {new Intl.DateTimeFormat(undefined, {
                              dateStyle: "medium",
                              timeStyle: "short",
                            }).format(new Date(workout.creation_date))}
                          </div>
                          {workout.rpe && (
                            <div className="font-semibold text-foreground">
                              RPE: {workout.rpe}
                            </div>
                          )}
                        </div>
                      </div>
                      <p>{workout.description}</p>
                      {exerciseData.length > 0 ? (
                        <ul className="text-sm text-muted-foreground">
                          {exerciseData.map(({ exercise, setCount }) => (
                            <li key={`${workout.id}-${exercise.id}`}>
                              {setCount} x {exercise.name}
                            </li>
                          ))}
                        </ul>
                      ) : (
                        <p className="text-sm text-muted-foreground">
                          No exercises added yet.
                        </p>
                      )}
                    </CardContent>
                  </Card>
                </Link>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
