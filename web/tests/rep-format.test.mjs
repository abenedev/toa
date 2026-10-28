import assert from "node:assert/strict";
import test from "node:test";
import { pluralizeRepCounts, repUnit } from "../lib/rep-format.ts";

test("uses singular rep for one and plural reps for counts greater than one", () => {
  assert.equal(repUnit(1), "rep");
  assert.equal(repUnit(2), "reps");
});

test("pluralizes rep counts embedded in PR details without changing other counts", () => {
  assert.equal(
    pluralizeRepCounts("1 reps x 80 kg; 8 rep x 40 kg"),
    "1 rep x 80 kg; 8 reps x 40 kg",
  );
  assert.equal(pluralizeRepCounts("80 kg"), "80 kg");
});