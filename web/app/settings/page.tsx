"use client";

import { Check, LogOut } from "lucide-react";
import { useState } from "react";
import { SubscriptionCard } from "@/components/subscription-card";
import { ThemeToggle } from "@/components/theme-toggle";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useAuth } from "@/contexts/AuthContext";
import { api } from "@/lib/api";

export default function SettingsPage() {
  const { user, logout } = useAuth();
  const [email, setEmail] = useState(user?.email ?? "");
  const [bodyweight, setBodyweight] = useState(
    user?.bodyweight == null ? "" : String(user.bodyweight),
  );
  const [saving, setSaving] = useState(false);
  const [updated, setUpdated] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const hasChanges =
    user !== null &&
    (email !== user.email ||
      bodyweight !== (user.bodyweight == null ? "" : String(user.bodyweight)));

  async function handleUpdateAccount(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!user || !hasChanges) return;

    setSaving(true);
    setError(null);
    try {
      const updatedUser = await api.updateUser(user.id, {
        email,
        bodyweight: bodyweight === "" ? null : Number(bodyweight),
      });
      setEmail(updatedUser.email);
      setBodyweight(
        updatedUser.bodyweight === null ? "" : String(updatedUser.bodyweight),
      );
      setUpdated(true);
    } catch (updateError) {
      console.error("Failed to update account", updateError);
      setError("Unable to update account.");
    } finally {
      setSaving(false);
    }
  }

  if (!user)
    return (
      <div className="container mx-auto p-6">Unable to load settings.</div>
    );

  return (
    <div className="container mx-auto p-6">
      <div className="space-y-6">
        <form className="space-y-4" onSubmit={handleUpdateAccount}>
          <div className="space-y-2">
            <Label htmlFor="email">Email</Label>
            <Input
              id="email"
              type="email"
              value={email}
              onChange={(event) => {
                setEmail(event.target.value);
                setUpdated(false);
              }}
              required
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="bodyweight">Bodyweight (kg)</Label>
            <Input
              id="bodyweight"
              type="number"
              min="0"
              step="0.1"
              value={bodyweight}
              onChange={(event) => {
                setBodyweight(event.target.value);
                setUpdated(false);
              }}
            />
          </div>

          <div className="flex items-center gap-2">
            <Button type="submit" disabled={!hasChanges || saving}>
              {saving ? "Updating..." : "Update account"}
            </Button>
            {updated && (
              <Check
                className="account-success text-green-600"
                aria-label="Account updated successfully"
                onAnimationEnd={() => setUpdated(false)}
              />
            )}
          </div>
          {error && <p className="text-sm text-destructive">{error}</p>}
        </form>

        <div className="border-t pt-6 space-y-4">
          <div>
            <div>
              <h3 className="text-lg font-semibold">Appearance</h3>
              <p className="text-sm text-muted-foreground">
                Choose your preferred display theme.
              </p>
            </div>
            <div className="mt-3">
              <ThemeToggle />
            </div>
          </div>
        </div>

        <SubscriptionCard />

        <div className="border-t pt-6">
          <h3 className="text-lg font-semibold mb-4">Password</h3>
          <Button variant="outline">Change Password</Button>
        </div>

        <div className="border-t pt-6">
          <h3 className="text-lg font-semibold mb-4">Account</h3>
          <Button variant="outline" onClick={logout} className="gap-2">
            <LogOut className="size-4" />
            Log Out
          </Button>
        </div>

        <div className="border-t pt-6">
          <h3 className="text-lg font-semibold mb-4 text-red-600">
            Danger Zone
          </h3>
          <Button variant="destructive">Delete Account</Button>
        </div>
      </div>
    </div>
  );
}
