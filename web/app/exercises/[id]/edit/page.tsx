"use client";

import { Trash2 } from "lucide-react";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
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

type Equipment = Exercise["equipment"];

export default function EditExercisePage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const router = useRouter();
  const [exercise, setExercise] = useState<Exercise | null>(null);
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [type, setType] = useState<Exercise["type"]>("REPS");
  const [equipment, setEquipment] = useState<Equipment | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    async function loadExercise() {
      try {
        const { id } = await params;
        const exerciseData = await api.getExercise(Number.parseInt(id, 10));
        setExercise(exerciseData);
        setName(exerciseData.name);
        setDescription(exerciseData.description || "");
        setType(exerciseData.type);
        setEquipment(exerciseData.equipment);
      } catch (loadError) {
        console.error("Error loading exercise:", loadError);
        setError("Unable to load this exercise.");
      } finally {
        setLoading(false);
      }
    }
    loadExercise();
  }, [params]);

  const handleSave = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!exercise || !name.trim() || !equipment) return;

    setSaving(true);
    setError(null);
    try {
      await api.updateExercise(exercise.id, {
        name: name.trim(),
        description: description.trim() || null,
        type,
        equipment,
      });
      router.push(`/exercises/${exercise.id}`);
    } catch (saveError) {
      console.error("Error updating exercise:", saveError);
      setError("Unable to save exercise changes.");
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = async () => {
    if (
      !exercise ||
      !confirm("Are you sure you want to delete this exercise?")
    ) {
      return;
    }

    setDeleting(true);
    setError(null);
    try {
      await api.deleteExercise(exercise.id);
      router.push("/exercises");
    } catch (deleteError) {
      console.error("Error deleting exercise:", deleteError);
      setError("Unable to delete exercise.");
    } finally {
      setDeleting(false);
    }
  };

  if (loading) {
    return <div className="container mx-auto p-6">Loading...</div>;
  }

  if (!exercise) {
    return (
      <div className="container mx-auto p-6">
        {error || "Exercise not found"}
      </div>
    );
  }

  return (
    <div className="container mx-auto p-6">
      <Card className="mx-auto max-w-2xl">
        <CardHeader>
          <CardTitle>Edit Exercise</CardTitle>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSave} className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="name">Name</Label>
              <Input
                id="name"
                value={name}
                onChange={(event) => setName(event.target.value)}
                placeholder="Exercise name"
                required
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="description">Description (optional)</Label>
              <Input
                id="description"
                value={description}
                onChange={(event) => setDescription(event.target.value)}
                placeholder="Exercise description"
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="type">Type</Label>
              <Select
                value={type}
                onValueChange={(value) => {
                  if (value === "REPS" || value === "DURATION") setType(value);
                }}
              >
                <SelectTrigger id="type">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="REPS">Rep-based</SelectItem>
                  <SelectItem value="DURATION">Duration-based</SelectItem>
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-2">
              <Label htmlFor="equipment">Equipment</Label>
              <Select
                value={equipment ?? ""}
                onValueChange={(value) => {
                  if (
                    value === "BARBELL" ||
                    value === "DUMBBELL" ||
                    value === "MACHINE" ||
                    value === "BODYWEIGHT" ||
                    value === "ASSISTED_BODYWEIGHT"
                  ) {
                    setEquipment(value);
                  }
                }}
              >
                <SelectTrigger id="equipment">
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

            {error && <p className="text-sm text-destructive">{error}</p>}
            <div className="flex items-center justify-between gap-2">
              <Button
                type="button"
                size="icon"
                variant="destructive"
                className="border-destructive/40"
                onClick={handleDelete}
                disabled={saving || deleting}
                title="Delete exercise"
              >
                <Trash2 className="size-4" />
              </Button>
              <div className="flex gap-2">
                <Button
                  type="button"
                  variant="outline"
                  onClick={() => router.push(`/exercises/${exercise.id}`)}
                  disabled={saving || deleting}
                >
                  Cancel
                </Button>
                <Button
                  type="submit"
                  disabled={saving || deleting || !name.trim() || !equipment}
                >
                  {saving ? "Saving..." : "Save"}
                </Button>
              </div>
            </div>
          </form>
        </CardContent>
      </Card>
    </div>
  );
}
