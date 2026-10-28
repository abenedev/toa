"use client";

import { Plus, Search } from "lucide-react";
import { useState } from "react";
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
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { api, type Exercise } from "@/lib/api";

function formatEquipment(equipment: string): string {
  return equipment
    .replace(/_/g, " ")
    .toLowerCase()
    .replace(/\b\w/g, (c) => c.toUpperCase());
}

interface ExerciseSearchDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  exercises: Exercise[];
  onSelectExercise: (exercise: Exercise) => void;
  onExerciseCreated?: (exercise: Exercise) => void;
}

export function ExerciseSearchDialog({
  open,
  onOpenChange,
  exercises,
  onSelectExercise,
  onExerciseCreated,
}: ExerciseSearchDialogProps) {
  const [searchQuery, setSearchQuery] = useState("");
  const [createModalOpen, setCreateModalOpen] = useState(false);

  // New exercise form states
  const [newName, setNewName] = useState("");
  const [newDescription, setNewDescription] = useState("");
  const [newType, setNewType] = useState<"REPS" | "DURATION">("REPS");
  const [newEquipment, setNewEquipment] = useState<
    | "BARBELL"
    | "DUMBBELL"
    | "MACHINE"
    | "BODYWEIGHT"
    | "ASSISTED_BODYWEIGHT"
    | null
  >(null);
  const [creating, setCreating] = useState(false);

  const filteredExercises = exercises.filter((ex) => {
    if (!searchQuery.trim()) return true;
    const q = searchQuery.toLowerCase();
    return (
      ex.name.toLowerCase().includes(q) ||
      (ex.description?.toLowerCase().includes(q) ?? false) ||
      ex.type.toLowerCase().includes(q) ||
      ex.equipment.toLowerCase().includes(q)
    );
  });

  const handleCreateExercise = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!newName.trim() || !newEquipment) return;

    setCreating(true);
    try {
      const created = await api.createExercise({
        name: newName.trim(),
        description: newDescription.trim() || null,
        type: newType,
        equipment: newEquipment,
      });

      onExerciseCreated?.(created);
      onSelectExercise(created);
      setCreateModalOpen(false);
      onOpenChange(false);
      // Reset form
      setNewName("");
      setNewDescription("");
      setNewType("REPS");
      setNewEquipment(null);
    } catch (err) {
      console.error("Failed to create exercise:", err);
    } finally {
      setCreating(false);
    }
  };

  return (
    <>
      <Dialog
        open={open}
        onOpenChange={(next) => {
          onOpenChange(next);
          if (!next) setSearchQuery("");
        }}
      >
        <DialogContent className="max-w-lg max-h-[85vh] flex flex-col p-6">
          <DialogHeader>
            <div className="flex items-center justify-between pr-6">
              <DialogTitle className="text-xl">Select Exercise</DialogTitle>
              <Button
                size="sm"
                variant="default"
                className="gap-1.5"
                onClick={() => setCreateModalOpen(true)}
              >
                Create exercise
              </Button>
            </div>
            <DialogDescription>
              Search existing exercises or create a new one.
            </DialogDescription>
          </DialogHeader>

          <div className="relative my-2">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 size-4 text-muted-foreground" />
            <Input
              placeholder="Search exercise by name or equipment..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="pl-9"
              autoFocus
            />
          </div>

          <div className="flex-1 overflow-y-auto min-h-[240px] max-h-[380px] -mx-2 px-2 divide-y divide-border/50">
            {filteredExercises.length === 0 ? (
              <div className="py-8 text-center space-y-3">
                <p className="text-muted-foreground text-sm">
                  {searchQuery
                    ? `No exercises found matching "${searchQuery}"`
                    : "No exercises available."}
                </p>
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => {
                    setNewName(searchQuery);
                    setCreateModalOpen(true);
                  }}
                >
                  <Plus className="size-4 mr-1" />
                  {searchQuery ? `Create "${searchQuery}"` : "Create Exercise"}
                </Button>
              </div>
            ) : (
              filteredExercises.map((exercise) => (
                <button
                  key={exercise.id}
                  type="button"
                  onClick={() => {
                    onSelectExercise(exercise);
                    onOpenChange(false);
                  }}
                  className="w-full text-left py-3 px-3 rounded-lg hover:bg-accent/60 transition-colors flex items-center justify-between group cursor-pointer"
                >
                  <div>
                    <div className="font-medium text-foreground group-hover:text-primary transition-colors">
                      {exercise.name}
                    </div>
                    {exercise.description && (
                      <div className="text-xs text-muted-foreground line-clamp-1">
                        {exercise.description}
                      </div>
                    )}
                  </div>
                  <div className="flex items-center gap-1.5 shrink-0">
                    <span className="text-xs px-2 py-0.5 rounded bg-muted text-muted-foreground font-medium">
                      {formatEquipment(exercise.equipment)}
                    </span>
                    <span className="text-xs px-2 py-0.5 rounded bg-muted/60 text-muted-foreground font-medium">
                      {exercise.type === "REPS" ? "Reps" : "Duration"}
                    </span>
                  </div>
                </button>
              ))
            )}
          </div>

          <DialogFooter className="flex flex-row justify-end gap-2 pt-2 border-t">
            <Button variant="outline" onClick={() => onOpenChange(false)}>
              Cancel
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Exercise Creation Modal */}
      <Dialog open={createModalOpen} onOpenChange={setCreateModalOpen}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Create Exercise</DialogTitle>
            <DialogDescription>
              Add a new exercise to your library.
            </DialogDescription>
          </DialogHeader>

          <form onSubmit={handleCreateExercise} className="space-y-4 py-2">
            <div className="space-y-1.5">
              <Label htmlFor="create-exercise-name">Name</Label>
              <Input
                id="create-exercise-name"
                value={newName}
                onChange={(e) => setNewName(e.target.value)}
                placeholder="e.g. Barbell Bench Press"
                required
                autoFocus
              />
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="create-exercise-desc">
                Description (optional)
              </Label>
              <Input
                id="create-exercise-desc"
                value={newDescription}
                onChange={(e) => setNewDescription(e.target.value)}
                placeholder="e.g. Flat bench, shoulder-width grip"
              />
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="create-exercise-type">Type</Label>
              <Select
                value={newType}
                onValueChange={(val) => setNewType(val as "REPS" | "DURATION")}
              >
                <SelectTrigger id="create-exercise-type">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="REPS">Rep-based</SelectItem>
                  <SelectItem value="DURATION">Duration-based</SelectItem>
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="create-exercise-equipment">Equipment</Label>
              <Select
                value={newEquipment ?? ""}
                onValueChange={(val) =>
                  setNewEquipment(
                    val as
                      | "BARBELL"
                      | "DUMBBELL"
                      | "MACHINE"
                      | "BODYWEIGHT"
                      | "ASSISTED_BODYWEIGHT",
                  )
                }
              >
                <SelectTrigger id="create-exercise-equipment">
                  <SelectValue placeholder="Select equipment" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="BARBELL">Barbell</SelectItem>
                  <SelectItem value="DUMBBELL">Dumbbell</SelectItem>
                  <SelectItem value="MACHINE">Machine</SelectItem>
                  <SelectItem value="BODYWEIGHT">Bodyweight</SelectItem>
                  <SelectItem value="ASSISTED_BODYWEIGHT">
                    Assisted Bodyweight
                  </SelectItem>
                </SelectContent>
              </Select>
            </div>

            <DialogFooter className="flex flex-row justify-end gap-2 pt-2">
              <Button
                type="button"
                variant="outline"
                onClick={() => setCreateModalOpen(false)}
                disabled={creating}
              >
                Cancel
              </Button>
              <Button
                type="submit"
                disabled={creating || !newName.trim() || !newEquipment}
              >
                {creating ? "Creating..." : "Create & Add"}
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </>
  );
}
