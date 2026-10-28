"use client";

import { Trash2 } from "lucide-react";
import type React from "react";
import { useRef, useState } from "react";
import { TableRow } from "@/components/ui/table";
import { cn } from "@/lib/utils";

interface SwipeableSetRowProps extends React.ComponentProps<typeof TableRow> {
  onDelete: () => void;
  children: React.ReactNode;
}

export function SwipeableSetRow({
  onDelete,
  children,
  className,
  ...props
}: SwipeableSetRowProps) {
  const [translateX, setTranslateX] = useState(0);
  const [isSwiping, setIsSwiping] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const startXRef = useRef<number | null>(null);
  const startYRef = useRef<number | null>(null);
  const isHorizontalSwipeRef = useRef<boolean | null>(null);

  const handleTouchStart = (e: React.TouchEvent) => {
    startXRef.current = e.touches[0].clientX;
    startYRef.current = e.touches[0].clientY;
    isHorizontalSwipeRef.current = null;
    setIsSwiping(true);
  };

  const handleTouchMove = (e: React.TouchEvent) => {
    if (startXRef.current === null || startYRef.current === null) return;
    const currentX = e.touches[0].clientX;
    const currentY = e.touches[0].clientY;
    const diffX = currentX - startXRef.current;
    const diffY = currentY - startYRef.current;

    if (isHorizontalSwipeRef.current === null) {
      if (Math.abs(diffX) > 6 || Math.abs(diffY) > 6) {
        isHorizontalSwipeRef.current = Math.abs(diffX) > Math.abs(diffY);
      }
    }

    if (isHorizontalSwipeRef.current) {
      if (diffX < 0) {
        setTranslateX(Math.max(-120, diffX));
      } else {
        setTranslateX(0);
      }
    }
  };

  const handleTouchEnd = () => {
    if (translateX < -65) {
      setIsDeleting(true);
      setTimeout(() => {
        onDelete();
      }, 160);
    } else {
      setTranslateX(0);
    }
    setIsSwiping(false);
    startXRef.current = null;
    startYRef.current = null;
    isHorizontalSwipeRef.current = null;
  };

  const handlePointerDown = (e: React.PointerEvent) => {
    const target = e.target as HTMLElement;
    if (
      target.tagName === "INPUT" ||
      target.tagName === "SELECT" ||
      target.tagName === "BUTTON" ||
      target.closest("button") ||
      target.closest("input") ||
      target.closest("select")
    ) {
      return;
    }
    startXRef.current = e.clientX;
    startYRef.current = e.clientY;
    setIsSwiping(true);
  };

  const handlePointerMove = (e: React.PointerEvent) => {
    if (startXRef.current === null || isDeleting) return;
    const diffX = e.clientX - startXRef.current;
    if (diffX < 0) {
      setTranslateX(Math.max(-120, diffX));
    }
  };

  const handlePointerUp = () => {
    if (startXRef.current === null) return;
    if (translateX < -65) {
      setIsDeleting(true);
      setTimeout(() => {
        onDelete();
      }, 160);
    } else {
      setTranslateX(0);
    }
    setIsSwiping(false);
    startXRef.current = null;
  };

  const isPastThreshold = translateX < -65;

  return (
    <TableRow
      className={cn(
        "transition-all touch-pan-y relative",
        isDeleting && "opacity-0 -translate-x-full h-0",
        translateX < 0 && (isPastThreshold ? "bg-red-500/25" : "bg-red-500/10"),
        className,
      )}
      style={{
        transform: isDeleting
          ? "translateX(-100%)"
          : `translateX(${translateX}px)`,
        transition: isSwiping
          ? "none"
          : "transform 0.2s ease-out, background-color 0.2s",
      }}
      onTouchStart={handleTouchStart}
      onTouchMove={handleTouchMove}
      onTouchEnd={handleTouchEnd}
      onPointerDown={handlePointerDown}
      onPointerMove={handlePointerMove}
      onPointerUp={handlePointerUp}
      onPointerCancel={handlePointerUp}
      {...props}
    >
      {children}
      {translateX < -20 && (
        <td
          className="absolute inset-y-0 right-0 flex items-center justify-end pr-3 pointer-events-none text-red-600 dark:text-red-400 font-semibold text-xs gap-1"
          style={{ transform: `translateX(${-translateX}px)` }}
        >
          <Trash2 className="size-4 animate-pulse" />
          <span>Swipe to delete</span>
        </td>
      )}
    </TableRow>
  );
}
