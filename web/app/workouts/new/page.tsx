import ActiveWorkoutPage from "../[id]/active/page";

export default function NewWorkoutPage() {
  return <ActiveWorkoutPage params={Promise.resolve({ id: "new" })} />;
}
