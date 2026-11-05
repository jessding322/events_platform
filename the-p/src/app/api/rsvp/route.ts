import { NextResponse } from "next/server";
import { createPublicClient } from "@/lib/supabase/public";

type RsvpPayload = {
  shareToken?: string;
  name?: string;
  email?: string;
  status?: "going" | "declined" | "maybe";
  plusOneCount?: number;
  reminderOptIn?: boolean;
};

export async function POST(request: Request) {
  let payload: RsvpPayload;
  try {
    payload = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body." }, { status: 400 });
  }

  const plusOneCount = payload.plusOneCount ?? 0;
  const validStatus = payload.status === "going" || payload.status === "declined" || payload.status === "maybe";
  if (!payload.shareToken || !payload.name?.trim() || !payload.email?.includes("@") || !validStatus || !Number.isInteger(plusOneCount) || plusOneCount < 0 || plusOneCount > 20) {
    return NextResponse.json({ error: "Please provide a valid RSVP." }, { status: 400 });
  }

  try {
    const supabase = createPublicClient();
    const { data, error } = await supabase.rpc("submit_rsvp", {
      p_share_token: payload.shareToken,
      p_name: payload.name.trim(),
      p_email: payload.email.trim().toLowerCase(),
      p_status: payload.status,
      p_plus_one_count: plusOneCount,
      p_reminder_opt_in: payload.reminderOptIn ?? true,
    });
    if (error) return NextResponse.json({ error: error.message }, { status: 400 });
    return NextResponse.json({ rsvp: data?.[0] }, { status: 201 });
  } catch {
    return NextResponse.json({ error: "Supabase is not configured yet." }, { status: 503 });
  }
}
