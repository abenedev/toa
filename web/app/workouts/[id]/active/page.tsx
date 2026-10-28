"use client";
import { Check, Timer, Trash2, Trophy } from "lucide-react";
import { notFound, usePathname, useRouter } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { Confetti } from "@/components/confetti";
import { ExerciseSearchDialog } from "@/components/exercise-search-dialog";
import { RestTimerDialog } from "@/components/rest-timer-dialog";
import { SwipeableSetRow } from "@/components/swipeable-set-row";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Textarea } from "@/components/ui/textarea";
import {
  api,
  type DurationSet,
  type Exercise,
  type ExercisePRs,
  type RepSet,
  type Workout,
  type WorkoutExercise,
} from "@/lib/api";
import { playSetCheckSound, playTimerDoneSound } from "@/lib/sound";
import { cn } from "@/lib/utils";

interface SetCompletion {
  completed: boolean;
  restStartTime: number | null;
  actualValues: Record<string, string>;
}

interface ExerciseGroup {
  id: string;
  exerciseId: number;
  sets: Array<RepSet | DurationSet>;
}

function getSetKey(set: RepSet | DurationSet): number {
  // RepSet and DurationSet have separate IDs, while their base set IDs are unique.
  return set.set_id ?? set.id;
}

function createExerciseGroupId() {
  return `exercise-group-${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

const SET_TYPES = ["WORKSET", "WARMUP", "DROPSET", "SUPERSET", "FAILURE"];
const SET_TYPE_LABELS: Record<string, string> = {
  WORKSET: "Workset",
  WARMUP: "Warmup",
  DROPSET: "Dropset",
  SUPERSET: "Superset",
  FAILURE: "Failure",
};

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

const SET_TYPE_SHORT_LABELS: Record<string, string> = {
  WARMUP: "W",
  DROPSET: "D",
  SUPERSET: "S",
  FAILURE: "F",
};

function getSetTypeDisplay(
  currentSet: RepSet | DurationSet,
  allExerciseSets: (RepSet | DurationSet)[],
  selectedSetTypes: Map<number, string>,
): string {
  const currentType =
    selectedSetTypes.get(getSetKey(currentSet)) || currentSet.type_;
  if (currentType === "WORKSET") {
    let worksetCount = 0;
    for (const s of allExerciseSets) {
      const type = selectedSetTypes.get(getSetKey(s)) || s.type_;
      if (type === "WORKSET") {
        worksetCount++;
      }
      if (getSetKey(s) === getSetKey(currentSet)) {
        break;
      }
    }
    return String(worksetCount);
  }

  return SET_TYPE_SHORT_LABELS[currentType] || currentType.charAt(0);
}

export default function ActiveWorkoutPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const [workout, setWorkout] = useState<Workout | null>(null);
  const [exercises, setExercises] = useState<Exercise[]>([]);
  const [workoutExercises, setWorkoutExercises] = useState<WorkoutExercise[]>(
    [],
  );
  const [repSets, setRepSets] = useState<RepSet[]>([]);
  const [durationSets, setDurationSets] = useState<DurationSet[]>([]);
  const [elapsedTime, setElapsedTime] = useState(0);
  const [setCompletions, setSetCompletions] = useState<
    Map<number, SetCompletion>
  >(new Map());
  const [activeRestTime, setActiveRestTime] = useState<{
    setId: number;
    remaining: number;
  } | null>(null);
  const [prSetKeys, setPrSetKeys] = useState<Set<number>>(new Set());
  const [confettiTrigger, setConfettiTrigger] = useState(0);
  const bestE1rmRef = useRef<Map<number, number>>(new Map());
  const [loading, setLoading] = useState(true);
  const [selectedSetTypes, setSelectedSetTypes] = useState<Map<number, string>>(
    new Map(),
  );
  const [inputs, setInputs] = useState<Record<string, string>>({});
  const [dialogOpen, setDialogOpen] = useState(false);
  const [dialogMode, setDialogMode] = useState<"cancel" | "finish" | null>(
    null,
  );
  const [exerciseSearchDialogOpen, setExerciseSearchDialogOpen] =
    useState(false);
  const [restTimerDialogOpen, setRestTimerDialogOpen] = useState(false);
  const [postWorkoutNote, setPostWorkoutNote] = useState("");
  const [workoutRpe, setWorkoutRpe] = useState<number | null>(null);
  const [postWorkoutDialogOpen, setPostWorkoutDialogOpen] = useState(false);
  const [pendingFinishAction, setPendingFinishAction] = useState<
    (() => Promise<void>) | null
  >(null);
  const [exerciseGroups, setExerciseGroups] = useState<ExerciseGroup[]>([]);
  const [exerciseRestTimes, setExerciseRestTimes] = useState<
    Record<string, number>
  >({});
  const [exerciseNotes, setExerciseNotes] = useState<Record<string, string>>(
    {},
  );
  const [draggedGroupId, setDraggedGroupId] = useState<string | null>(null);
  const [dropIndicator, setDropIndicator] = useState<{
    groupId: string;
    position: "before" | "after";
  } | null>(null);
  const timerStartedAtRef = useRef<number | null>(null);
  const timerWorkoutIdRef = useRef<number | null>(null);
  const initialRepSetIdsRef = useRef<Set<number>>(new Set());
  const initialDurationSetIdsRef = useRef<Set<number>>(new Set());
  const initialRepSetsRef = useRef<Map<number, RepSet>>(new Map());
  const initialDurationSetsRef = useRef<Map<number, DurationSet>>(new Map());
  const postWorkoutNoteRef = useRef(postWorkoutNote);
  const workoutRpeRef = useRef(workoutRpe);
  useEffect(() => {
    postWorkoutNoteRef.current = postWorkoutNote;
    workoutRpeRef.current = workoutRpe;
  }, [postWorkoutNote, workoutRpe]);
  const pathname = usePathname();
  const isEditMode = pathname.endsWith("/edit");
  const isNewMode = pathname.endsWith("/workouts/new");
  const router = useRouter();

  useEffect(() => {
    async function loadData() {
      try {
        const { id } = await params;
        if (id === "new") {
          const exercisesData = await api.getExercises();
          setWorkout({
            id: 0,
            user_id: 1,
            name: "",
            planned: true,
            description: null,
            note: null,
            creation_date: new Date().toISOString(),
            mesocycle_id: null,
          });
          setPostWorkoutNote("");
          setExercises(exercisesData);
          setRepSets([]);
          setDurationSets([]);
          setExerciseGroups([]);
          setExerciseNotes({});
          setWorkoutExercises([]);
          return;
        }
        const idNum = Number.parseInt(id, 10);

        const [
          workoutData,
          exercisesData,
          workoutExercisesData,
          repSetData,
          durationSetData,
        ]: [Workout, Exercise[], WorkoutExercise[], RepSet[], DurationSet[]] =
          await Promise.all([
            api.getWorkout(idNum),
            api.getExercises(),
            api.getWorkoutExercises(idNum),
            api.getRepSets(idNum),
            api.getDurationSets(idNum),
          ]);

        const nextRepSets = repSetData.filter(
          (set: RepSet) => set.workout_id === idNum,
        );
        const nextDurationSets = durationSetData.filter(
          (set: DurationSet) => set.workout_id === idNum,
        );

        setWorkout(workoutData);
        // Clear post-workout note and RPE when starting from history (non-planned workout)
        setPostWorkoutNote(workoutData.planned ? workoutData.note || "" : "");
        setWorkoutRpe(workoutData.planned ? (workoutData.rpe ?? null) : null);
        setExercises(exercisesData);
        setWorkoutExercises(workoutExercisesData);
        setRepSets(nextRepSets);
        setDurationSets(nextDurationSets);

        // Initialize exercise notes from workout exercises
        const initialNotes: Record<string, string> = {};
        workoutExercisesData.forEach((we) => {
          initialNotes[we.exercise_id.toString()] = we.note || "";
        });
        setExerciseNotes(initialNotes);
        initialRepSetIdsRef.current = new Set(nextRepSets.map((set) => set.id));
        initialDurationSetIdsRef.current = new Set(
          nextDurationSets.map((set) => set.id),
        );
        initialRepSetsRef.current = new Map(
          nextRepSets.map((set) => [set.id, set]),
        );
        initialDurationSetsRef.current = new Map(
          nextDurationSets.map((set) => [set.id, set]),
        );

        // Initialize inputs with saved values
        const initialInputs: Record<string, string> = {};
        nextRepSets.forEach((set) => {
          const setKey = getSetKey(set);
          if (set.weight !== null)
            initialInputs[`${setKey}-weight`] = String(set.weight);
          if (set.reps !== null)
            initialInputs[`${setKey}-reps`] = String(set.reps);
          if (set.rpe !== null)
            initialInputs[`${setKey}-rpe`] = String(set.rpe);
        });
        nextDurationSets.forEach((set) => {
          const setKey = getSetKey(set);
          if (set.weight !== null)
            initialInputs[`${setKey}-weight`] = String(set.weight);
          if (set.duration !== null)
            initialInputs[`${setKey}-duration`] = String(set.duration);
          if (set.rpe !== null)
            initialInputs[`${setKey}-rpe`] = String(set.rpe);
        });
        setInputs(initialInputs);

        setExerciseGroups(() => {
          const orderedSets = [...nextRepSets, ...nextDurationSets].sort(
            (a, b) => a.position - b.position,
          );
          const setsByExercise = new Map<number, (RepSet | DurationSet)[]>();
          for (const set of orderedSets) {
            const exerciseSets = setsByExercise.get(set.exercise_id) ?? [];
            exerciseSets.push(set);
            setsByExercise.set(set.exercise_id, exerciseSets);
          }

          const groups = workoutExercisesData
            .slice()
            .sort((a, b) => a.position - b.position)
            .map((workoutExercise) => ({
              id: createExerciseGroupId(),
              exerciseId: workoutExercise.exercise_id,
              sets: setsByExercise.get(workoutExercise.exercise_id) ?? [],
            }));

          const associatedExerciseIds = new Set(
            workoutExercisesData.map((item) => item.exercise_id),
          );
          for (const [exerciseId, sets] of setsByExercise) {
            if (associatedExerciseIds.has(exerciseId)) continue;
            groups.push({ id: createExerciseGroupId(), exerciseId, sets });
          }

          return groups;
        });
      } catch (error) {
        console.error("Error loading workout:", error);
      } finally {
        setLoading(false);
      }
    }

    loadData();
  }, [params]);

  useEffect(() => {
    if (loading || !workout || isEditMode || isNewMode) {
      return;
    }

    if (timerWorkoutIdRef.current !== workout.id) {
      timerWorkoutIdRef.current = workout.id;
      timerStartedAtRef.current = Date.now();
      setElapsedTime(0);
    }

    const interval = window.setInterval(() => {
      const startedAt = timerStartedAtRef.current;
      if (startedAt !== null) {
        setElapsedTime(Math.floor((Date.now() - startedAt) / 1000));
      }
    }, 1000);

    return () => window.clearInterval(interval);
  }, [loading, workout, isEditMode, isNewMode]);

  useEffect(() => {
    if (!activeRestTime || activeRestTime.remaining <= 0) {
      return;
    }

    const interval = setInterval(() => {
      setActiveRestTime((prev) => {
        if (!prev) return null;
        const newRemaining = prev.remaining - 1;
        if (newRemaining <= 0) {
          playTimerDoneSound();
          return null;
        }
        return { ...prev, remaining: newRemaining };
      });
    }, 1000);

    return () => clearInterval(interval);
  }, [activeRestTime]);

  const handleStartRestTimer = (seconds: number) => {
    setActiveRestTime({ setId: 0, remaining: seconds });
  };

  const handleStopRestTimer = () => {
    setActiveRestTime(null);
  };

  const handleAdjustRestTimer = (deltaSeconds: number) => {
    setActiveRestTime((prev) => {
      if (!prev) {
        return deltaSeconds > 0 ? { setId: 0, remaining: deltaSeconds } : null;
      }
      const nextRemaining = Math.max(0, prev.remaining + deltaSeconds);
      if (nextRemaining === 0) return null;
      return { ...prev, remaining: nextRemaining };
    });
  };

  const formatRemainingRestTime = (seconds: number) => {
    const mins = Math.floor(seconds / 60);
    const secs = seconds % 60;
    if (mins === 0) return `${secs}s`;
    return `${mins}m ${secs.toString().padStart(2, "0")}s`;
  };

  const formatTime = (seconds: number) => {
    const hrs = Math.floor(seconds / 3600);
    const mins = Math.floor((seconds % 3600) / 60);
    const secs = seconds % 60;
    return `${hrs.toString().padStart(2, "0")}:${mins
      .toString()
      .padStart(2, "0")}:${secs.toString().padStart(2, "0")}`;
  };

  const createRepSetTemplate = (
    exerciseId: number,
    workoutId: number,
  ): RepSet => ({
    id: Date.now() + Math.random(),
    workout_id: workoutId,
    exercise_id: exerciseId,
    position: 0,
    type_: "WORKSET",
    weight: null,
    rpe: null,
    rest: 0,
    reps: 0,
  });

  const createDurationSetTemplate = (
    exerciseId: number,
    workoutId: number,
  ): DurationSet => ({
    id: Date.now() + Math.random(),
    workout_id: workoutId,
    exercise_id: exerciseId,
    position: 0,
    type_: "WORKSET",
    weight: null,
    rpe: null,
    rest: 0,
    duration: 0,
  });

  const handleSelectExerciseFromModal = (exercise: Exercise) => {
    if (!workout) return;

    const newSet =
      exercise.type === "REPS"
        ? createRepSetTemplate(exercise.id, workout.id)
        : createDurationSetTemplate(exercise.id, workout.id);
    const newGroup: ExerciseGroup = {
      id: createExerciseGroupId(),
      exerciseId: exercise.id,
      sets: [newSet],
    };

    setExerciseGroups((prev) => [...prev, newGroup]);
    if (exercise.type === "REPS") {
      setRepSets((prev) => [...prev, newSet as RepSet]);
    } else {
      setDurationSets((prev) => [...prev, newSet as DurationSet]);
    }
    setExerciseNotes((prev) => ({
      ...prev,
      [exercise.id.toString()]: "",
    }));
  };

  const handleDeleteSet = (setToDelete: RepSet | DurationSet) => {
    const setKey = getSetKey(setToDelete);
    if ("reps" in setToDelete) {
      setRepSets((prev) => prev.filter((set) => set.id !== setToDelete.id));
    } else {
      setDurationSets((prev) =>
        prev.filter((set) => set.id !== setToDelete.id),
      );
    }
    setExerciseGroups((prev) =>
      prev
        .map((group) => ({
          ...group,
          sets: group.sets.filter((set) => getSetKey(set) !== setKey),
        }))
        .filter((group) => group.sets.length > 0),
    );
    setSetCompletions((prev) => {
      const next = new Map(prev);
      next.delete(setKey);
      return next;
    });
  };

  const handleDeleteExercise = (groupId: string) => {
    const group = exerciseGroups.find((item) => item.id === groupId);
    if (!group) return;

    const repSetIds = new Set(
      group.sets
        .filter((set): set is RepSet => "reps" in set)
        .map((set) => set.id),
    );
    const durationSetIds = new Set(
      group.sets
        .filter((set): set is DurationSet => "duration" in set)
        .map((set) => set.id),
    );
    const groupSetKeys = new Set(group.sets.map(getSetKey));
    setRepSets((prev) => prev.filter((set) => !repSetIds.has(set.id)));
    setDurationSets((prev) =>
      prev.filter((set) => !durationSetIds.has(set.id)),
    );
    setSetCompletions((prev) => {
      const next = new Map(prev);
      for (const key of groupSetKeys) next.delete(key);
      return next;
    });
    setExerciseGroups((prev) => prev.filter((item) => item.id !== groupId));
    setExerciseNotes((prev) => {
      const next = { ...prev };
      delete next[group.exerciseId.toString()];
      return next;
    });
  };

  const handleDragOverExercise = (
    event: React.DragEvent<HTMLElement>,
    targetGroupId: string,
  ) => {
    event.preventDefault();
    if (draggedGroupId === null || draggedGroupId === targetGroupId) return;
    const bounds = event.currentTarget.getBoundingClientRect();
    const position =
      event.clientY < bounds.top + bounds.height / 2 ? "before" : "after";
    setDropIndicator({ groupId: targetGroupId, position });
  };

  const handleDropExercise = (targetGroupId: string) => {
    if (draggedGroupId === null || draggedGroupId === targetGroupId) return;

    setExerciseGroups((prev) => {
      const next = [...prev];
      const sourceIndex = next.findIndex(
        (group) => group.id === draggedGroupId,
      );
      const targetIndex = next.findIndex((group) => group.id === targetGroupId);
      if (sourceIndex < 0 || targetIndex < 0) return prev;
      const [moved] = next.splice(sourceIndex, 1);
      let insertionIndex =
        targetIndex + (dropIndicator?.position === "after" ? 1 : 0);
      if (sourceIndex < insertionIndex) insertionIndex -= 1;
      next.splice(insertionIndex, 0, moved);
      return next;
    });
    setDraggedGroupId(null);
    setDropIndicator(null);
  };

  const handleRestTimeChange = (groupId: string, value: string) => {
    const rest = Math.max(0, Number.parseInt(value, 10) || 0);
    const group = exerciseGroups.find((item) => item.id === groupId);
    if (!group) return;
    const groupSetIds = new Set(group.sets.map(getSetKey));

    setExerciseRestTimes((prev) => ({ ...prev, [groupId]: rest }));
    setRepSets((prev) =>
      prev.map((set) =>
        groupSetIds.has(getSetKey(set)) ? { ...set, rest } : set,
      ),
    );
    setDurationSets((prev) =>
      prev.map((set) =>
        groupSetIds.has(getSetKey(set)) ? { ...set, rest } : set,
      ),
    );
    setExerciseGroups((prev) =>
      prev.map((item) =>
        item.id === groupId
          ? { ...item, sets: item.sets.map((set) => ({ ...set, rest })) }
          : item,
      ),
    );
  };

  const handleAddSet = (groupId: string) => {
    if (!workout) return;

    const group = exerciseGroups.find((item) => item.id === groupId);
    if (!group) return;

    const exercise = exercises.find((item) => item.id === group.exerciseId);
    if (!exercise) return;

    const newSet =
      exercise.type === "REPS"
        ? createRepSetTemplate(group.exerciseId, workout.id)
        : createDurationSetTemplate(group.exerciseId, workout.id);
    newSet.rest = exerciseRestTimes[groupId] ?? group.sets[0]?.rest ?? 0;

    if (exercise.type === "REPS") {
      setRepSets((prev) => [...prev, newSet as RepSet]);
    } else {
      setDurationSets((prev) => [...prev, newSet as DurationSet]);
    }

    setExerciseGroups((prev) => {
      return prev.map((item) =>
        item.id === groupId ? { ...item, sets: [...item.sets, newSet] } : item,
      );
    });
  };

  const saveEditedWorkout = async (
    targetWorkoutId = workout?.id,
    createOnly = false,
  ) => {
    if (!workout) return;
    if (targetWorkoutId === undefined) return;

    const toNumberOrNull = (
      value: string | undefined,
      fallback: number | null,
    ) => {
      if (value?.trim()) {
        const parsed = Number.parseFloat(value);
        return Number.isFinite(parsed) ? parsed : fallback;
      }
      return fallback;
    };

    const currentRepSets: RepSet[] = [];
    const currentDurationSets: DurationSet[] = [];

    // Preserve order by iterating through exercise groups in order
    exerciseGroups.forEach((group) => {
      group.sets.forEach((set) => {
        if ("reps" in set) {
          currentRepSets.push(set as RepSet);
        } else {
          currentDurationSets.push(set as DurationSet);
        }
      });
    });
    const currentRepSetIds = new Set(currentRepSets.map((set) => set.id));
    const currentDurationSetIds = new Set(
      currentDurationSets.map((set) => set.id),
    );
    const positions = new Map<number, number>();
    exerciseGroups.forEach((group, groupIndex) => {
      group.sets.forEach((set, setIndex) => {
        positions.set(getSetKey(set), groupIndex * 1000 + setIndex);
      });
    });

    if (!createOnly) {
      await Promise.all([
        ...Array.from(initialRepSetIdsRef.current)
          .filter((setId) => !currentRepSetIds.has(setId))
          .map((setId) => api.deleteRepSet(setId)),
        ...Array.from(initialDurationSetIdsRef.current)
          .filter((setId) => !currentDurationSetIds.has(setId))
          .map((setId) => api.deleteDurationSet(setId)),
      ]);
    }

    const saveRepSet = (set: RepSet) => {
      const setKey = getSetKey(set);
      const type_ = selectedSetTypes.get(setKey) ?? set.type_ ?? "WORKSET";
      const payload = {
        workout_id: targetWorkoutId,
        exercise_id: set.exercise_id,
        position: positions.get(setKey) ?? 0,
        type_,
        weight: toNumberOrNull(inputs[`${setKey}-weight`], set.weight),
        rpe: toNumberOrNull(inputs[`${setKey}-rpe`], set.rpe),
        rest: set.rest,
        reps: Math.round(
          toNumberOrNull(inputs[`${setKey}-reps`], set.reps) ?? 0,
        ),
      };

      if (createOnly || !initialRepSetIdsRef.current.has(set.id)) {
        return api.createRepSet(payload);
      }

      const originalSet = initialRepSetsRef.current.get(set.id);
      if (
        originalSet &&
        payload.type_ === originalSet.type_ &&
        payload.weight === originalSet.weight &&
        payload.rpe === originalSet.rpe &&
        payload.rest === originalSet.rest &&
        payload.reps === originalSet.reps &&
        payload.position === originalSet.position
      ) {
        return Promise.resolve();
      }

      return api.updateRepSet(set.id, payload);
    };

    const saveDurationSet = (set: DurationSet) => {
      const setKey = getSetKey(set);
      const type_ = selectedSetTypes.get(setKey) ?? set.type_ ?? "WORKSET";
      const payload = {
        workout_id: targetWorkoutId,
        exercise_id: set.exercise_id,
        position: positions.get(setKey) ?? 0,
        type_,
        weight: toNumberOrNull(inputs[`${setKey}-weight`], set.weight),
        rpe: toNumberOrNull(inputs[`${setKey}-rpe`], set.rpe),
        rest: set.rest,
        duration: Math.round(
          toNumberOrNull(inputs[`${setKey}-duration`], set.duration) ?? 0,
        ),
      };

      if (createOnly || !initialDurationSetIdsRef.current.has(set.id)) {
        return api.createDurationSet(payload);
      }

      const originalSet = initialDurationSetsRef.current.get(set.id);
      if (
        originalSet &&
        payload.type_ === originalSet.type_ &&
        payload.weight === originalSet.weight &&
        payload.rpe === originalSet.rpe &&
        payload.rest === originalSet.rest &&
        payload.position === originalSet.position &&
        payload.duration === originalSet.duration
      ) {
        return Promise.resolve();
      }

      return api.updateDurationSet(set.id, payload);
    };

    await Promise.all([
      ...currentRepSets.map(saveRepSet),
      ...currentDurationSets.map(saveDurationSet),
    ]);

    // Save workout metadata (name, description, note)
    if (!createOnly) {
      await api.updateWorkout(targetWorkoutId, {
        name: workout.name,
        planned: workout.planned,
        description: workout.description,
        note: postWorkoutNote.trim() || null,
        rpe: workoutRpe,
        mesocycle_id: workout.mesocycle_id,
      });
    }

    // Save workout exercises (create/update/delete based on exercise groups)
    if (!createOnly) {
      // Delete workout exercises that are no longer in the exercise groups
      const currentExerciseIds = new Set(
        exerciseGroups.map((group) => group.exerciseId),
      );
      await Promise.all(
        workoutExercises
          .filter((we) => !currentExerciseIds.has(we.exercise_id))
          .map((we) => api.deleteWorkoutExercise(we.id)),
      );
    }

    // Create or update workout exercises for each exercise group
    for (const [index, group] of exerciseGroups.entries()) {
      const existingWorkoutExercise = workoutExercises.find(
        (we) => we.exercise_id === group.exerciseId,
      );
      const note = exerciseNotes[group.exerciseId.toString()] || null;

      if (existingWorkoutExercise) {
        // Update existing workout exercise
        await api.updateWorkoutExercise(existingWorkoutExercise.id, {
          position: index,
          note,
        });
      } else {
        // Create new workout exercise
        await api.createWorkoutExercise({
          workout_id: targetWorkoutId,
          exercise_id: group.exerciseId,
          position: index,
          note,
        });
      }
    }
  };

  const checkForPersonalRecord = async (
    set: RepSet | DurationSet,
    setKey: number,
    actualValues: Record<string, string>,
  ) => {
    if (!("reps" in set)) return;
    const weight = Number.parseFloat(actualValues.weight ?? "");
    const reps = Number.parseInt(actualValues.reps ?? "", 10);
    if (!(weight > 0) || !(reps > 0)) return;
    const exercise = exercises.find((item) => item.id === set.exercise_id);
    if (exercise?.equipment === "ASSISTED_BODYWEIGHT") return;

    // Mirrors the Epley estimate in backend/src/workout/prs.py
    const rpe = actualValues.rpe ? Number.parseFloat(actualValues.rpe) : 10;
    const effectiveReps =
      reps + Math.max(0, 10 - (Number.isNaN(rpe) ? 10 : rpe));
    const e1rm = effectiveReps > 1 ? weight * (1 + effectiveReps / 30) : weight;

    try {
      const prs: ExercisePRs = await api.getExercisePRs(set.exercise_id);
      const recordOf = (type: string) =>
        prs.records.find((record) => record.type === type)?.value;
      const priorE1rm = recordOf("ESTIMATED_1RM");
      const priorHeaviest = recordOf("HEAVIEST_WEIGHT");
      // Without history there is nothing to beat
      if (priorE1rm === undefined && priorHeaviest === undefined) return;

      const sessionBest = bestE1rmRef.current.get(set.exercise_id) ?? 0;
      const beatsE1rm =
        priorE1rm !== undefined &&
        Math.round(e1rm * 10) / 10 > Math.max(priorE1rm, sessionBest);
      const beatsWeight = priorHeaviest !== undefined && weight > priorHeaviest;
      bestE1rmRef.current.set(set.exercise_id, Math.max(sessionBest, e1rm));
      if (!beatsE1rm && !beatsWeight) return;

      setPrSetKeys((prev) => new Set(prev).add(setKey));
      setConfettiTrigger((value) => value + 1);
    } catch {
      // PR detection is best-effort
    }
  };

  const handleSetComplete = (set: RepSet | DurationSet, restTime: number) => {
    const setKey = getSetKey(set);
    const currentCompletion = setCompletions.get(setKey);

    if (currentCompletion?.completed) {
      setSetCompletions((prev) => {
        const next = new Map(prev);
        next.delete(setKey);
        return next;
      });
      setPrSetKeys((prev) => {
        if (!prev.has(setKey)) return prev;
        const next = new Set(prev);
        next.delete(setKey);
        return next;
      });
      setActiveRestTime(null);
      return;
    }

    const actualValues: Record<string, string> = {};
    const getValueOrPlaceholder = (key: string, placeholder: string) => {
      const value = inputs[`${setKey}-${key}`] ?? "";
      return value.trim() || placeholder;
    };

    const weightValue = getValueOrPlaceholder(
      "weight",
      set.weight?.toString() || "0",
    );
    const rawRpeValue = getValueOrPlaceholder("rpe", set.rpe?.toString() || "");

    if (weightValue) actualValues.weight = weightValue;
    if (rawRpeValue && rawRpeValue !== "0") actualValues.rpe = rawRpeValue;

    if ("reps" in set) {
      const repsValue = getValueOrPlaceholder(
        "reps",
        set.reps?.toString() || "0",
      );
      if (repsValue) actualValues.reps = repsValue;
    }

    if ("duration" in set) {
      const durationValue = getValueOrPlaceholder(
        "duration",
        set.duration?.toString() || "0",
      );
      if (durationValue) actualValues.duration = durationValue;
    }

    setSetCompletions((prev) => {
      const next = new Map(prev);
      next.set(setKey, {
        completed: true,
        restStartTime: Date.now(),
        actualValues,
      });
      return next;
    });

    setInputs((prev) => {
      const next = { ...prev };
      for (const [key, value] of Object.entries(actualValues)) {
        next[`${setKey}-${key}`] = String(value);
      }
      return next;
    });

    playSetCheckSound();
    void checkForPersonalRecord(set, setKey, actualValues);

    if (restTime > 0) {
      setActiveRestTime({ setId: setKey, remaining: restTime });
    }
  };

  if (loading) {
    return <div className="container mx-auto p-6">Loading...</div>;
  }

  if (!workout) {
    notFound();
  }

  const exerciseSets = new Map<number, (RepSet | DurationSet)[]>();

  repSets.forEach((set) => {
    const currentSets = exerciseSets.get(set.exercise_id);
    if (!currentSets) {
      exerciseSets.set(set.exercise_id, [set]);
      return;
    }
    currentSets.push(set);
  });

  durationSets.forEach((set) => {
    const currentSets = exerciseSets.get(set.exercise_id);
    if (!currentSets) {
      exerciseSets.set(set.exercise_id, [set]);
      return;
    }
    currentSets.push(set);
  });

  const orderedExerciseGroups =
    exerciseGroups.length > 0
      ? exerciseGroups
      : Array.from(exerciseSets.entries()).map(([exerciseId, sets]) => ({
          id: createExerciseGroupId(),
          exerciseId,
          sets,
        }));

  return (
    <div className="container mx-auto p-6">
      <Confetti trigger={confettiTrigger} />
      <div className="mt-4">
        <div>
          <div className="flex flex-col items-end">
            <div className="w-full">
              <div className="flex justify-between">
                <Input
                  aria-label="Workout name"
                  className="font-bold text-2xl mr-2"
                  placeholder="Workout name"
                  value={workout.name}
                  onChange={(event) =>
                    setWorkout((current) =>
                      current
                        ? { ...current, name: event.target.value }
                        : current,
                    )
                  }
                />
                {!isNewMode && (
                  <div className="text-2xl font-mono">
                    {formatTime(elapsedTime)}
                  </div>
                )}
              </div>
              <Input
                className="mt-2 mb-3"
                aria-label="Workout description"
                placeholder="Description (optional)"
                value={workout.description ?? ""}
                onChange={(event) =>
                  setWorkout((current) =>
                    current
                      ? {
                          ...current,
                          description: event.target.value || null,
                        }
                      : current,
                  )
                }
              />
              <div className="flex items-center gap-3 mb-4 flex-wrap">
                {!isNewMode && (
                  <Button
                    type="button"
                    variant="outline"
                    size="sm"
                    className="gap-2 font-medium"
                    onClick={() => setRestTimerDialogOpen(true)}
                  >
                    <Timer className="size-4 text-orange-500" />
                    Rest Timer
                  </Button>
                )}

                {activeRestTime &&
                  activeRestTime.remaining > 0 &&
                  !isEditMode &&
                  !isNewMode && (
                    <div className="flex items-center gap-2 bg-orange-50 dark:bg-orange-950/40 border border-orange-200 dark:border-orange-800/60 rounded-lg px-3 py-1 font-mono text-sm text-orange-600 dark:text-orange-400 font-semibold animate-in fade-in duration-200">
                      <span>
                        Rest:{" "}
                        {formatRemainingRestTime(activeRestTime.remaining)}
                      </span>
                      <div className="flex items-center gap-1 font-sans">
                        <Button
                          type="button"
                          size="xs"
                          variant="ghost"
                          className="h-6 px-1.5 text-xs text-muted-foreground hover:text-foreground"
                          onClick={() => handleAdjustRestTimer(-15)}
                        >
                          -15s
                        </Button>
                        <Button
                          type="button"
                          size="xs"
                          variant="ghost"
                          className="h-6 px-1.5 text-xs text-muted-foreground hover:text-foreground"
                          onClick={() => handleAdjustRestTimer(15)}
                        >
                          +15s
                        </Button>
                        <Button
                          type="button"
                          size="xs"
                          variant="ghost"
                          className="h-6 px-1.5 text-xs text-destructive hover:text-destructive"
                          onClick={handleStopRestTimer}
                        >
                          Skip
                        </Button>
                      </div>
                    </div>
                  )}
              </div>
            </div>
          </div>
        </div>
        <div>
          {orderedExerciseGroups.length === 0 ? (
            <p className="text-muted-foreground">
              No exercises in this workout.
            </p>
          ) : (
            <div className="space-y-6">
              {orderedExerciseGroups.map((group) => {
                const { id: groupId, exerciseId, sets } = group;
                const exercise = exercises.find(
                  (item) => item.id === exerciseId,
                );
                if (!exercise) return null;

                const isRepExercise = exercise.type === "REPS";
                const weightLabel =
                  exercise.equipment === "ASSISTED_BODYWEIGHT"
                    ? "-kg"
                    : exercise.equipment === "BODYWEIGHT"
                      ? "+kg"
                      : "kg";

                const showBefore =
                  dropIndicator?.groupId === groupId &&
                  dropIndicator.position === "before";
                const showAfter =
                  dropIndicator?.groupId === groupId &&
                  dropIndicator.position === "after";

                return (
                  <div key={group.id}>
                    {showBefore && <div className="h-1 rounded bg-blue-500" />}
                    <section
                      role="none"
                      className="border rounded-lg p-4 w-full"
                      onDragOver={(event) =>
                        handleDragOverExercise(event, groupId)
                      }
                      onDrop={() => handleDropExercise(groupId)}
                    >
                      <div className="flex items-center justify-between gap-3 mb-2">
                        <div className="flex items-center gap-2">
                          <h3
                            draggable
                            onDragStart={() => setDraggedGroupId(groupId)}
                            onDragEnd={() => {
                              setDraggedGroupId(null);
                              setDropIndicator(null);
                            }}
                            className="text-lg font-semibold cursor-grab active:cursor-grabbing select-none hover:text-primary transition-colors"
                            title="Hold and drag to reorder exercise"
                          >
                            {exercise.name}
                          </h3>
                        </div>
                        <Button
                          size="icon-sm"
                          variant="destructive"
                          className="border-destructive/40"
                          onClick={() => handleDeleteExercise(groupId)}
                          title="Delete exercise"
                        >
                          <Trash2 className="size-4" />
                        </Button>
                      </div>

                      <div className="mb-2">
                        <Input
                          aria-label="Exercise note"
                          className="text-sm"
                          placeholder="Add a note"
                          value={exerciseNotes[exerciseId] ?? ""}
                          onChange={(event) =>
                            setExerciseNotes((prev) => ({
                              ...prev,
                              [exerciseId]: event.target.value,
                            }))
                          }
                        />
                      </div>

                      <div className="flex items-center gap-2 mb-4 text-sm">
                        <label
                          htmlFor={`rest-${groupId}`}
                          className="font-medium"
                        >
                          Rest (s)
                        </label>
                        <Input
                          id={`rest-${groupId}`}
                          type="number"
                          min="0"
                          className="w-13"
                          value={
                            exerciseRestTimes[groupId] ?? sets[0]?.rest ?? 0
                          }
                          onChange={(event) =>
                            handleRestTimeChange(groupId, event.target.value)
                          }
                        />
                      </div>

                      <Table>
                        <TableHeader>
                          <TableRow className="border-b">
                            <TableHead className="p-2 text-center">
                              Type
                            </TableHead>
                            <TableHead className="p-2 text-center">
                              {weightLabel}
                            </TableHead>
                            {isRepExercise ? (
                              <TableHead className="p-2 text-center">
                                Reps
                              </TableHead>
                            ) : (
                              <TableHead className="p-2 text-center">
                                duration
                              </TableHead>
                            )}
                            <TableHead className="p-2 text-center">
                              RPE
                            </TableHead>
                            <TableHead className="p-2 w-8" />
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {sets.map((set) => {
                            const setKey = getSetKey(set);
                            const completion = setCompletions.get(setKey);
                            const isCompleted = completion?.completed;
                            const actualValues = completion?.actualValues || {};
                            const selectColor =
                              SET_TYPE_COLORS[
                                selectedSetTypes.get(setKey) || set.type_
                              ] || "bg-background";

                            return (
                              <SwipeableSetRow
                                key={setKey}
                                onDelete={() => handleDeleteSet(set)}
                                className={
                                  isCompleted
                                    ? "bg-green-50 dark:bg-green-950/50 dark:text-green-50"
                                    : ""
                                }
                              >
                                <TableCell className="p-2 text-center">
                                  <Select
                                    value={
                                      selectedSetTypes.get(setKey) || set.type_
                                    }
                                    onValueChange={(selectedType) => {
                                      if (!selectedType) return;
                                      setSelectedSetTypes((prev) => {
                                        const next = new Map(prev);
                                        next.set(setKey, selectedType);
                                        return next;
                                      });
                                      if (selectedType === "FAILURE") {
                                        setInputs((prev) => ({
                                          ...prev,
                                          [`${setKey}-rpe`]: "10",
                                        }));
                                      }
                                    }}
                                  >
                                    <SelectTrigger
                                      showIcon={false}
                                      className={cn(
                                        "justify-center px-2 text-center font-semibold min-w-8 rounded border shadow-xs",
                                        selectColor,
                                      )}
                                    >
                                      <SelectValue className="justify-center text-center">
                                        {getSetTypeDisplay(
                                          set,
                                          sets,
                                          selectedSetTypes,
                                        )}
                                      </SelectValue>
                                    </SelectTrigger>
                                    <SelectContent>
                                      {SET_TYPES.map((type) => (
                                        <SelectItem key={type} value={type}>
                                          {SET_TYPE_LABELS[type] || type}
                                        </SelectItem>
                                      ))}
                                    </SelectContent>
                                  </Select>
                                </TableCell>

                                <TableCell className="p-2 text-center">
                                  <Input
                                    type="number"
                                    placeholder={
                                      set.weight !== null
                                        ? set.weight.toString()
                                        : actualValues.weight || "0"
                                    }
                                    value={
                                      inputs[`${setKey}-weight`] ??
                                      (isCompleted && actualValues.weight
                                        ? String(actualValues.weight)
                                        : set.weight !== null
                                          ? String(set.weight)
                                          : "")
                                    }
                                    className="text-center"
                                    onChange={(e) =>
                                      setInputs((prev) => ({
                                        ...prev,
                                        [`${setKey}-weight`]: e.target.value,
                                      }))
                                    }
                                  />
                                </TableCell>

                                <TableCell className="text-center">
                                  {isRepExercise ? (
                                    <Input
                                      type="number"
                                      placeholder={
                                        "reps" in set && set.reps !== null
                                          ? set.reps.toString()
                                          : actualValues.reps || "0"
                                      }
                                      value={
                                        inputs[`${setKey}-reps`] ??
                                        (isCompleted && actualValues.reps
                                          ? String(actualValues.reps)
                                          : "reps" in set && set.reps !== null
                                            ? String(set.reps)
                                            : "")
                                      }
                                      min="0"
                                      className="text-center"
                                      onChange={(e) =>
                                        setInputs((prev) => ({
                                          ...prev,
                                          [`${setKey}-reps`]: e.target.value,
                                        }))
                                      }
                                    />
                                  ) : (
                                    <Input
                                      type="number"
                                      placeholder={
                                        "duration" in set &&
                                        set.duration !== null
                                          ? set.duration.toString()
                                          : actualValues.duration || "0"
                                      }
                                      value={
                                        inputs[`${setKey}-duration`] ??
                                        (isCompleted && actualValues.duration
                                          ? String(actualValues.duration)
                                          : "duration" in set &&
                                              set.duration !== null
                                            ? String(set.duration)
                                            : "")
                                      }
                                      min="0"
                                      className="text-center"
                                      onChange={(e) =>
                                        setInputs((prev) => ({
                                          ...prev,
                                          [`${setKey}-duration`]:
                                            e.target.value,
                                        }))
                                      }
                                    />
                                  )}
                                </TableCell>

                                <TableCell className="p-2 text-center">
                                  <Input
                                    type="number"
                                    placeholder={
                                      set.rpe !== null
                                        ? set.rpe.toString()
                                        : actualValues.rpe || "0"
                                    }
                                    value={
                                      inputs[`${setKey}-rpe`] ??
                                      (isCompleted && actualValues.rpe
                                        ? String(actualValues.rpe)
                                        : set.rpe !== null
                                          ? String(set.rpe)
                                          : "")
                                    }
                                    className="text-center w-12"
                                    min="1"
                                    max="10"
                                    step="0.5"
                                    onChange={(e) =>
                                      setInputs((prev) => ({
                                        ...prev,
                                        [`${setKey}-rpe`]: e.target.value,
                                      }))
                                    }
                                  />
                                </TableCell>

                                <TableCell className="p-2 flex gap-1 text-center justify-center items-center">
                                  {isCompleted && prSetKeys.has(setKey) && (
                                    <Trophy
                                      className="size-4 text-amber-500"
                                      aria-label="New personal record"
                                    />
                                  )}
                                  {!isEditMode && !isNewMode && (
                                    <Button
                                      type="button"
                                      variant={
                                        isCompleted ? "default" : "outline"
                                      }
                                      className={cn(
                                        "transition-all font-semibold",
                                        isCompleted
                                          ? "bg-emerald-600 hover:bg-emerald-700 text-white border-transparent shadow-sm"
                                          : "bg-emerald-100 hover:bg-emerald-200 text-emerald-800 border-emerald-300 dark:bg-emerald-950/70 dark:hover:bg-emerald-900 dark:text-emerald-300 dark:border-emerald-700",
                                      )}
                                      onClick={() =>
                                        handleSetComplete(
                                          set,
                                          exerciseRestTimes[groupId] ??
                                            set.rest,
                                        )
                                      }
                                    >
                                      <Check className="size-4" />
                                    </Button>
                                  )}
                                </TableCell>
                              </SwipeableSetRow>
                            );
                          })}
                        </TableBody>
                      </Table>
                      <Button
                        className="w-full mt-2"
                        variant="outline"
                        onClick={() => handleAddSet(groupId)}
                      >
                        + Add set
                      </Button>
                    </section>
                    {showAfter && <div className="h-1 rounded bg-blue-500" />}
                  </div>
                );
              })}
            </div>
          )}

          <Button
            className="w-full my-4"
            variant="outline"
            onClick={() => setExerciseSearchDialogOpen(true)}
          >
            + Add exercise
          </Button>

          <div className="flex gap-4">
            <Button
              variant="outline"
              className="flex-1"
              onClick={() => {
                setDialogMode("cancel");
                setDialogOpen(true);
              }}
            >
              {isNewMode
                ? "Cancel"
                : isEditMode
                  ? "Discard Changes"
                  : "Cancel Workout"}
            </Button>
            <Button
              variant="default"
              className="flex-1"
              disabled={isNewMode && !workout.name.trim()}
              onClick={() => {
                setDialogMode("finish");
                setDialogOpen(true);
              }}
            >
              {isNewMode
                ? "Save Workout"
                : isEditMode
                  ? "Save Workout"
                  : "Finish Workout"}
            </Button>
          </div>

          <ExerciseSearchDialog
            open={exerciseSearchDialogOpen}
            onOpenChange={setExerciseSearchDialogOpen}
            exercises={exercises}
            onSelectExercise={handleSelectExerciseFromModal}
            onExerciseCreated={(newEx) =>
              setExercises((prev) => [...prev, newEx])
            }
          />

          {!isNewMode && (
            <RestTimerDialog
              open={restTimerDialogOpen}
              onOpenChange={setRestTimerDialogOpen}
              activeRemaining={activeRestTime?.remaining ?? null}
              onStartTimer={handleStartRestTimer}
              onStopTimer={handleStopRestTimer}
              onAdjustTimer={handleAdjustRestTimer}
            />
          )}

          <Dialog
            open={dialogOpen}
            onOpenChange={(open) => setDialogOpen(open)}
          >
            <DialogContent>
              <DialogHeader>
                <DialogTitle>
                  {dialogMode === "cancel"
                    ? isNewMode
                      ? "Cancel workout"
                      : isEditMode
                        ? "Discard changes"
                        : "Cancel workout"
                    : isNewMode || isEditMode
                      ? "Save workout"
                      : "Finish workout"}
                </DialogTitle>
              </DialogHeader>
              <DialogDescription>
                {dialogMode === "cancel"
                  ? isNewMode
                    ? "Are you sure you want to cancel creating this workout?"
                    : isEditMode
                      ? "Are you sure you want to discard your changes?"
                      : "Are you sure to cancel your workout?"
                  : isNewMode || isEditMode
                    ? "Are you sure you want to save your workout?"
                    : "Are you sure to finish your workout?"}
              </DialogDescription>
              <DialogFooter className="flex flex-row justify-end gap-2">
                <Button variant="outline" onClick={() => setDialogOpen(false)}>
                  No
                </Button>
                <Button
                  variant="default"
                  onClick={async () => {
                    if (dialogMode === "cancel") {
                      setDialogOpen(false);
                      router.push(
                        isEditMode ? `/workouts/${workout.id}` : "/workouts",
                      );
                      return;
                    }

                    if (isNewMode) {
                      // For new planned workouts, save directly (no post-workout modal)
                      try {
                        if (!workout.name.trim()) return;
                        const newWorkout = await api.createWorkout({
                          name: workout.name.trim(),
                          planned: true,
                          description: workout.description?.trim() || null,
                          note: postWorkoutNote.trim() || null,
                          rpe: workoutRpe,
                          mesocycle_id: workout.mesocycle_id,
                        });
                        await saveEditedWorkout(newWorkout.id, true);
                        setDialogOpen(false);
                        router.push(`/workouts/${newWorkout.id}`);
                      } catch (err) {
                        console.error("Error creating workout", err);
                        setDialogOpen(false);
                      }
                      return;
                    }

                    if (isEditMode) {
                      // For edit mode, save directly (no post-workout modal)
                      try {
                        await saveEditedWorkout();
                        setDialogOpen(false);
                        router.push(`/workouts/${workout.id}`);
                      } catch (err) {
                        console.error("Error updating workout", err);
                        setDialogOpen(false);
                      }
                      return;
                    }

                    // Active workout "Finish" — close confirmation, open post-workout modal
                    setDialogOpen(false);
                    setPendingFinishAction(() => async () => {
                      try {
                        const newWorkout = await api.createWorkout({
                          name: workout?.name ?? "Finished workout",
                          planned: false,
                          description: workout?.description ?? null,
                          note: postWorkoutNoteRef.current.trim() || null,
                          rpe: workoutRpeRef.current,
                          mesocycle_id: workout?.mesocycle_id ?? null,
                        });

                        const completedSets = exerciseGroups
                          .flatMap((group) => group.sets)
                          .filter(
                            (set) =>
                              setCompletions.get(getSetKey(set))?.completed,
                          );
                        const completedSetKeys = new Set(
                          completedSets.map(getSetKey),
                        );

                        // Save workout exercises with notes
                        for (const [index, group] of exerciseGroups.entries()) {
                          if (
                            !group.sets.some((set) =>
                              completedSetKeys.has(getSetKey(set)),
                            )
                          ) {
                            continue;
                          }
                          const note =
                            exerciseNotes[group.exerciseId.toString()] || null;
                          await api.createWorkoutExercise({
                            workout_id: newWorkout.id,
                            exercise_id: group.exerciseId,
                            position: index,
                            note,
                          });
                        }

                        const setPositions = new Map<number, number>();
                        exerciseGroups.forEach((group, groupIndex) => {
                          group.sets.forEach((set, setIndex) => {
                            setPositions.set(
                              getSetKey(set),
                              groupIndex * 1000 + setIndex,
                            );
                          });
                        });

                        for (const setObj of completedSets) {
                          const setKey = getSetKey(setObj);
                          const completion = setCompletions.get(setKey);
                          if (!completion?.completed) continue;

                          const selectedType = (
                            selectedSetTypes.get(setKey) ??
                            setObj.type_ ??
                            "WORKSET"
                          )
                            .toString()
                            .toUpperCase();
                          const rawRpe = completion.actualValues.rpe;
                          const numericWeight = completion.actualValues.weight
                            ? Number.parseFloat(completion.actualValues.weight)
                            : (setObj.weight ?? null);
                          const numericRpe = rawRpe
                            ? Number.parseFloat(rawRpe)
                            : (setObj.rpe ?? null);

                          const base = {
                            workout_id: newWorkout.id,
                            exercise_id: setObj.exercise_id,
                            position: setPositions.get(setKey) ?? 0,
                            type_: selectedType,
                            weight: Number.isFinite(numericWeight)
                              ? numericWeight
                              : null,
                            rpe:
                              numericRpe != null &&
                              Number.isFinite(numericRpe) &&
                              numericRpe > 0
                                ? numericRpe
                                : null,
                            rest: Number.isFinite(setObj.rest)
                              ? setObj.rest
                              : 0,
                          };

                          if ("reps" in setObj) {
                            const repsValue = completion.actualValues.reps
                              ? Number.parseInt(
                                  completion.actualValues.reps,
                                  10,
                                )
                              : (setObj.reps ?? 0);

                            await api.createRepSet({
                              ...base,
                              reps: Number.isFinite(repsValue) ? repsValue : 0,
                            });
                          } else {
                            const durationValue = completion.actualValues
                              .duration
                              ? Number.parseInt(
                                  completion.actualValues.duration,
                                  10,
                                )
                              : (setObj.duration ?? 0);

                            await api.createDurationSet({
                              ...base,
                              duration: Number.isFinite(durationValue)
                                ? durationValue
                                : 0,
                            });
                          }
                        }
                      } catch (err) {
                        console.error("Error saving finished workout", err);
                      } finally {
                        router.push("/workouts");
                      }
                    });
                    setPostWorkoutDialogOpen(true);
                  }}
                >
                  Yes
                </Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>

          <Dialog
            open={postWorkoutDialogOpen}
            onOpenChange={(open) => {
              if (!open) {
                setPostWorkoutDialogOpen(false);
                setPendingFinishAction(null);
              }
            }}
          >
            <DialogContent className="sm:max-w-md">
              <DialogHeader>
                <DialogTitle>Post Workout Summary</DialogTitle>
                <DialogDescription>
                  Rate how difficult this workout felt and add any notes.
                </DialogDescription>
              </DialogHeader>
              <div className="space-y-5 py-2">
                <div className="space-y-2">
                  <div className="font-semibold text-sm text-foreground">
                    Overall RPE
                  </div>
                  <p className="text-xs text-muted-foreground">
                    Rate the perceived difficulty of the entire workout (1-10)
                  </p>
                  <div className="flex items-center gap-1">
                    {Array.from({ length: 10 }, (_, i) => i + 1).map(
                      (value) => (
                        <button
                          key={value}
                          type="button"
                          className={cn(
                            "flex items-center justify-center w-8 h-8 rounded-full transition-all text-sm font-semibold cursor-pointer",
                            workoutRpe === value
                              ? "bg-primary text-primary-foreground shadow-md scale-110"
                              : "bg-muted text-muted-foreground hover:bg-accent hover:text-accent-foreground",
                          )}
                          onClick={() =>
                            setWorkoutRpe((prev) =>
                              prev === value ? null : value,
                            )
                          }
                        >
                          {value}
                        </button>
                      ),
                    )}
                  </div>
                </div>
                <div className="space-y-2">
                  <label
                    htmlFor="post-workout-note-modal"
                    className="font-semibold text-sm text-foreground"
                  >
                    Note
                  </label>
                  <Textarea
                    id="post-workout-note-modal"
                    placeholder="How did this workout feel? PRs, fatigue, reflections..."
                    value={postWorkoutNote}
                    onChange={(e: React.ChangeEvent<HTMLTextAreaElement>) =>
                      setPostWorkoutNote(e.target.value)
                    }
                    rows={3}
                  />
                </div>
              </div>
              <DialogFooter className="flex flex-row justify-end gap-2">
                <Button
                  variant="outline"
                  onClick={() => {
                    setPostWorkoutDialogOpen(false);
                    setPendingFinishAction(null);
                  }}
                >
                  Cancel
                </Button>
                <Button
                  variant="default"
                  onClick={async () => {
                    setPostWorkoutDialogOpen(false);
                    if (pendingFinishAction) {
                      await pendingFinishAction();
                    }
                    setPendingFinishAction(null);
                  }}
                >
                  Save Workout
                </Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>
        </div>
      </div>
    </div>
  );
}
