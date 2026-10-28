"use client";

import { Timer } from "lucide-react";
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

interface RestTimerDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  activeRemaining: number | null;
  onStartTimer: (seconds: number) => void;
  onStopTimer: () => void;
  onAdjustTimer: (deltaSeconds: number) => void;
}

const PRESETS = [
  { label: "30s", seconds: 30 },
  { label: "60s", seconds: 60 },
  { label: "90s", seconds: 90 },
  { label: "2m", seconds: 120 },
  { label: "2m 30s", seconds: 150 },
  { label: "3m", seconds: 180 },
  { label: "5m", seconds: 300 },
];

export function RestTimerDialog({
  open,
  onOpenChange,
  activeRemaining,
  onStartTimer,
  onStopTimer,
  onAdjustTimer,
}: RestTimerDialogProps) {
  const [customMinutes, setCustomMinutes] = useState("1");
  const [customSeconds, setCustomSeconds] = useState("30");

  const formatTime = (secs: number) => {
    const mins = Math.floor(secs / 60);
    const remainder = secs % 60;
    return `${mins}:${remainder.toString().padStart(2, "0")}`;
  };

  const handleStartCustom = () => {
    const mins = Number.parseInt(customMinutes, 10) || 0;
    const secs = Number.parseInt(customSeconds, 10) || 0;
    const total = mins * 60 + secs;
    if (total > 0) {
      onStartTimer(total);
      onOpenChange(false);
    }
  };

  const handleStartPreset = (seconds: number) => {
    onStartTimer(seconds);
    onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <div className="flex items-center gap-2">
            <Timer className="size-5 text-orange-500" />
            <DialogTitle>Rest Timer</DialogTitle>
          </div>
          <DialogDescription>
            Start or adjust your rest timer between sets.
          </DialogDescription>
        </DialogHeader>

        {activeRemaining !== null && activeRemaining > 0 && (
          <div className="p-4 rounded-xl bg-orange-500/10 border border-orange-500/30 text-center space-y-3">
            <div className="text-xs font-semibold text-orange-600 dark:text-orange-400 uppercase tracking-wider">
              Active Timer Running
            </div>
            <div className="text-4xl font-mono font-bold text-orange-600 dark:text-orange-400">
              {formatTime(activeRemaining)}
            </div>
            <div className="flex items-center justify-center gap-2">
              <Button
                size="sm"
                variant="outline"
                onClick={() => onAdjustTimer(-15)}
              >
                -15s
              </Button>
              <Button
                size="sm"
                variant="outline"
                onClick={() => onAdjustTimer(15)}
              >
                +15s
              </Button>
              <Button
                size="sm"
                variant="destructive"
                onClick={() => {
                  onStopTimer();
                  onOpenChange(false);
                }}
              >
                Stop Timer
              </Button>
            </div>
          </div>
        )}

        <div className="space-y-4 py-2">
          <div>
            <Label className="text-xs font-medium text-muted-foreground uppercase tracking-wider mb-2 block">
              Quick Presets
            </Label>
            <div className="grid grid-cols-4 gap-2">
              {PRESETS.map((preset) => (
                <Button
                  key={preset.seconds}
                  type="button"
                  variant="outline"
                  size="sm"
                  className="font-medium hover:border-primary hover:text-primary transition-all"
                  onClick={() => handleStartPreset(preset.seconds)}
                >
                  {preset.label}
                </Button>
              ))}
            </div>
          </div>

          <div className="pt-2 border-t space-y-2">
            <Label className="text-xs font-medium text-muted-foreground uppercase tracking-wider block">
              Custom Duration
            </Label>
            <div className="flex items-center gap-3">
              <div className="flex-1 space-y-1">
                <span className="text-xs text-muted-foreground">Minutes</span>
                <Input
                  type="number"
                  min="0"
                  max="60"
                  value={customMinutes}
                  onChange={(e) => setCustomMinutes(e.target.value)}
                  className="text-center"
                />
              </div>
              <span className="text-2xl font-bold text-muted-foreground pt-4">
                :
              </span>
              <div className="flex-1 space-y-1">
                <span className="text-xs text-muted-foreground">Seconds</span>
                <Input
                  type="number"
                  min="0"
                  max="59"
                  value={customSeconds}
                  onChange={(e) => setCustomSeconds(e.target.value)}
                  className="text-center"
                />
              </div>
            </div>
          </div>
        </div>

        <DialogFooter className="flex flex-row justify-end gap-2 pt-2 border-t">
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Close
          </Button>
          <Button onClick={handleStartCustom}>Start Timer</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
