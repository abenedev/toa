import type { Workout } from "./api.ts";

export function getDescendedPerformedWorkouts(
  sourceWorkoutId: number,
  workouts: Workout[],
): Workout[] {
  const childrenBySource = new Map<number, Workout[]>();
  for (const workout of workouts) {
    if (workout.source_workout_id == null) continue;
    const children = childrenBySource.get(workout.source_workout_id) ?? [];
    children.push(workout);
    childrenBySource.set(workout.source_workout_id, children);
  }

  const visited = new Set<number>([sourceWorkoutId]);
  const queue = [sourceWorkoutId];
  const descendants: Workout[] = [];
  while (queue.length > 0) {
    const parentId = queue.shift();
    if (parentId === undefined) continue;
    for (const child of childrenBySource.get(parentId) ?? []) {
      if (visited.has(child.id)) continue;
      visited.add(child.id);
      descendants.push(child);
      queue.push(child.id);
    }
  }

  return descendants.filter((workout) => !workout.planned);
}

export function getHeaviestTotalVolume(volumes: number[]): number | null {
  if (volumes.length === 0) return null;
  return volumes.reduce((heaviest, current) => Math.max(heaviest, current));
}
