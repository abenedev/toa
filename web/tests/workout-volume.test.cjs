const assert = require("node:assert/strict");
const test = require("node:test");
const {
  getDescendedPerformedWorkouts,
  getHeaviestTotalVolume,
} = require("../lib/workout-volume.ts");

function workout(id, planned, sourceWorkoutId = null) {
  return {
    id,
    user_id: 1,
    name: `Workout ${id}`,
    planned,
    description: null,
    creation_date: "2026-01-01T00:00:00Z",
    mesocycle_id: null,
    source_workout_id: sourceWorkoutId,
  };
}

test("finds performed descendants through planned intermediate workouts", () => {
  const descendants = getDescendedPerformedWorkouts(1, [
    workout(1, true),
    workout(2, true, 1),
    workout(3, false, 1),
    workout(4, false, 2),
    workout(5, false, 99),
  ]);

  assert.deepEqual(
    descendants.map((item) => item.id),
    [3, 4],
  );
});

test("returns the maximum descendant volume rather than their sum", () => {
  assert.equal(getHeaviestTotalVolume([800, 1250, 950]), 1250);
});

test("returns null when no descended performed workout has volume", () => {
  assert.equal(getHeaviestTotalVolume([]), null);
});