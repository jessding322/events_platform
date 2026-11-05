"use client";

import { FormEvent, useState } from "react";
import { createClient } from "@/lib/supabase/client";

export default function LoginPage() {
  const [email, setEmail] = useState("");
  const [message, setMessage] = useState("");

  async function signIn(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const supabase = createClient();
    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: { emailRedirectTo: `${window.location.origin}/auth/callback` },
    });
    setMessage(error ? error.message : "Check your inbox for a secure sign-in link.");
  }

  return <main className="login-page"><section className="login-card"><p className="eyebrow">GATHER</p><h1>Welcome back.</h1><p>Sign in to create events and manage your guest lists.</p><form onSubmit={signIn}><label>Email<input type="email" required value={email} onChange={(event) => setEmail(event.target.value)} placeholder="you@example.com" /></label><button className="primary-button" type="submit">Email me a sign-in link</button></form>{message && <p className="login-message">{message}</p>}</section></main>;
}
