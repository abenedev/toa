export function repUnit(count: number): string {
  return count > 1 ? "reps" : "rep";
}

export function pluralizeRepCounts(text: string): string {
  return text.replace(
    /\b(\d+(?:,\d{3})*(?:\.\d+)?)\s+reps?\b/gi,
    (_match, count: string) => {
      const unit = repUnit(Number(count.replaceAll(",", "")));
      return `${count} ${unit}`;
    },
  );
}
