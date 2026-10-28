"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { api, type Exercise } from "@/lib/api";

function formatEquipment(equipment: string): string {
  return equipment
    .replace(/_/g, " ")
    .toLowerCase()
    .replace(/\b\w/g, (c) => c.toUpperCase());
}

export default function ExercisesPage() {
  const [exercises, setExercises] = useState<Exercise[]>([]);
  const [searchQuery, setSearchQuery] = useState("");
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function loadExercises() {
      try {
        const data = await api.getExercises();
        setExercises(data);
      } catch (error) {
        console.error("Failed to load exercises:", error);
      } finally {
        setLoading(false);
      }
    }
    loadExercises();
  }, []);

  const filteredExercises = exercises.filter((exercise) => {
    if (!searchQuery.trim()) return true;
    const query = searchQuery.toLowerCase();
    return (
      exercise.name.toLowerCase().includes(query) ||
      (exercise.description?.toLowerCase().includes(query) ?? false) ||
      exercise.type.toLowerCase().includes(query) ||
      (exercise.equipment?.toLowerCase().includes(query) ?? false)
    );
  });

  if (loading) {
    return <div className="container mx-auto p-6">Loading...</div>;
  }

  return (
    <div className="container mx-auto p-6 space-y-8">
      <div className="flex items-center justify-between">
        <h2 className="text-2xl font-bold">Exercises</h2>
        <Link href="/exercises/new">
          <Button>Create exercise</Button>
        </Link>
      </div>
      <div className="max-w-md">
        <Input
          type="text"
          placeholder="Search exercises..."
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          className="w-full"
        />
      </div>
      {filteredExercises.length === 0 ? (
        <p className="text-muted-foreground">
          {searchQuery
            ? "No exercises match your search."
            : "No exercises yet."}
        </p>
      ) : (
        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
          {filteredExercises.map((exercise) => (
            <Link key={exercise.id} href={`/exercises/${exercise.id}`}>
              <Card className="hover:shadow-lg transition-shadow cursor-pointer h-full">
                <CardHeader>
                  <CardTitle className="flex items-center justify-between gap-2">
                    <span>{exercise.name}</span>
                    {!exercise.private && (
                      <span className="rounded-full bg-muted px-2 py-0.5 text-xs font-medium text-muted-foreground">
                        Default
                      </span>
                    )}
                  </CardTitle>
                </CardHeader>
                <CardContent>
                  <div className="space-y-2">
                    {exercise.description && (
                      <p className="text-sm text-muted-foreground">
                        {exercise.description}
                      </p>
                    )}
                    <div className="text-sm font-medium">
                      Type: {exercise.type}
                    </div>
                    {exercise.equipment && (
                      <div className="text-sm font-medium">
                        Equipment: {formatEquipment(exercise.equipment)}
                      </div>
                    )}
                  </div>
                </CardContent>
              </Card>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
