import "server-only";

import { createClient } from "@/lib/supabase/server";

export type CreateEventInput = {
  title: string;
  description?: string;
  location: string;
  startsAt: string;
  timezone: string;
  rsvpDeadline?: string;
  plusOneLimit?: number;
};

async function requireUser() {
  const supabase = await createClient();
  const { data: { user }, error } = await supabase.auth.getUser();
  if (error || !user) throw new Error("You must be signed in to manage events.");
  return { supabase, user };
}

export async function listHostedEvents() {
  const { supabase, user } = await requireUser();
  const { data, error } = await supabase
    .from("events")
    .select("id, title, description, location, starts_at, timezone, rsvp_deadline, plus_one_limit, share_token, status, created_at")
    .eq("host_id", user.id)
    .order("starts_at", { ascending: true });

  if (error) throw error;
  return data;
}

export async function createEvent(input: CreateEventInput) {
  const { supabase, user } = await requireUser();
  const { data, error } = await supabase
    .from("events")
    .insert({
      host_id: user.id,
      title: input.title.trim(),
      description: input.description?.trim() || null,
      location: input.location.trim(),
      starts_at: input.startsAt,
      timezone: input.timezone,
      rsvp_deadline: input.rsvpDeadline || null,
      plus_one_limit: input.plusOneLimit ?? 0,
    })
    .select("id, share_token")
    .single();

  if (error) throw error;
  return data;
}

export async function getHostedEvent(eventId: string) {
  const { supabase, user } = await requireUser();
  const { data, error } = await supabase
    .from("events")
    .select("*, rsvps(id, guest_name, guest_email, status, plus_one_count, reminder_opt_in, created_at)")
    .eq("id", eventId)
    .eq("host_id", user.id)
    .single();

  if (error) throw error;
  return data;
}
