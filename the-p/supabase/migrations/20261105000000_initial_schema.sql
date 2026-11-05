create extension if not exists pgcrypto;

create type public.event_status as enum ('draft', 'published', 'cancelled');
create type public.rsvp_status as enum ('going', 'maybe', 'declined');
create type public.reminder_status as enum ('pending', 'sent', 'failed', 'skipped');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.events (
  id uuid primary key default gen_random_uuid(),
  host_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 1 and 160),
  description text,
  location text not null check (char_length(trim(location)) between 1 and 500),
  starts_at timestamptz not null,
  timezone text not null check (char_length(timezone) between 1 and 100),
  rsvp_deadline timestamptz,
  plus_one_limit integer not null default 0 check (plus_one_limit between 0 and 20),
  status public.event_status not null default 'published',
  share_token uuid not null unique default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (rsvp_deadline is null or rsvp_deadline <= starts_at)
);

create table public.rsvps (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  guest_name text not null check (char_length(trim(guest_name)) between 1 and 120),
  guest_email text not null check (guest_email = lower(guest_email) and char_length(guest_email) <= 320),
  status public.rsvp_status not null,
  plus_one_count integer not null default 0 check (plus_one_count between 0 and 20),
  reminder_opt_in boolean not null default true,
  manage_token uuid not null unique default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (event_id, guest_email)
);

create table public.reminder_deliveries (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  rsvp_id uuid not null references public.rsvps(id) on delete cascade,
  scheduled_at timestamptz not null,
  sent_at timestamptz,
  status public.reminder_status not null default 'pending',
  provider_message_id text,
  error_message text,
  attempt_count integer not null default 0 check (attempt_count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (rsvp_id, scheduled_at)
);

create index events_host_starts_at_idx on public.events(host_id, starts_at);
create index rsvps_event_id_idx on public.rsvps(event_id);
create index reminder_deliveries_due_idx on public.reminder_deliveries(status, scheduled_at);

create function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at before update on public.profiles for each row execute function public.set_updated_at();
create trigger events_set_updated_at before update on public.events for each row execute function public.set_updated_at();
create trigger rsvps_set_updated_at before update on public.rsvps for each row execute function public.set_updated_at();
create trigger reminder_deliveries_set_updated_at before update on public.reminder_deliveries for each row execute function public.set_updated_at();

create function public.create_profile_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', new.raw_user_meta_data ->> 'full_name'));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.create_profile_for_new_user();

alter table public.profiles enable row level security;
alter table public.events enable row level security;
alter table public.rsvps enable row level security;
alter table public.reminder_deliveries enable row level security;

create policy "Hosts can read their profile" on public.profiles for select to authenticated using (id = auth.uid());
create policy "Hosts can update their profile" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

create policy "Hosts can read their events" on public.events for select to authenticated using (host_id = auth.uid());
create policy "Hosts can create their events" on public.events for insert to authenticated with check (host_id = auth.uid());
create policy "Hosts can update their events" on public.events for update to authenticated using (host_id = auth.uid()) with check (host_id = auth.uid());
create policy "Hosts can delete their events" on public.events for delete to authenticated using (host_id = auth.uid());

create policy "Hosts can read their event RSVPs" on public.rsvps for select to authenticated using (exists (select 1 from public.events where events.id = rsvps.event_id and events.host_id = auth.uid()));
create policy "Hosts can update their event RSVPs" on public.rsvps for update to authenticated using (exists (select 1 from public.events where events.id = rsvps.event_id and events.host_id = auth.uid())) with check (exists (select 1 from public.events where events.id = rsvps.event_id and events.host_id = auth.uid()));
create policy "Hosts can delete their event RSVPs" on public.rsvps for delete to authenticated using (exists (select 1 from public.events where events.id = rsvps.event_id and events.host_id = auth.uid()));

create policy "Hosts can read their reminder deliveries" on public.reminder_deliveries for select to authenticated using (exists (select 1 from public.events where events.id = reminder_deliveries.event_id and events.host_id = auth.uid()));

create function public.get_public_event(p_share_token uuid)
returns table (
  id uuid,
  title text,
  description text,
  location text,
  starts_at timestamptz,
  timezone text,
  rsvp_deadline timestamptz,
  plus_one_limit integer
)
language sql
security definer
set search_path = public
as $$
  select id, title, description, location, starts_at, timezone, rsvp_deadline, plus_one_limit
  from public.events
  where share_token = p_share_token and status = 'published';
$$;

create function public.submit_rsvp(
  p_share_token uuid,
  p_name text,
  p_email text,
  p_status public.rsvp_status,
  p_plus_one_count integer,
  p_reminder_opt_in boolean default true
)
returns table (rsvp_id uuid, manage_token uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  target_event public.events;
begin
  select * into target_event from public.events where share_token = p_share_token and status = 'published';
  if not found then raise exception 'Event not found'; end if;
  if target_event.rsvp_deadline is not null and now() > target_event.rsvp_deadline then raise exception 'RSVPs are closed'; end if;
  if p_plus_one_count < 0 or p_plus_one_count > target_event.plus_one_limit then raise exception 'Invalid plus-one count'; end if;

  return query
  insert into public.rsvps (event_id, guest_name, guest_email, status, plus_one_count, reminder_opt_in)
  values (target_event.id, trim(p_name), lower(trim(p_email)), p_status, p_plus_one_count, p_reminder_opt_in)
  on conflict (event_id, guest_email) do update
    set guest_name = excluded.guest_name,
        status = excluded.status,
        plus_one_count = excluded.plus_one_count,
        reminder_opt_in = excluded.reminder_opt_in
  returning id, manage_token;
end;
$$;

create function public.update_rsvp_with_token(
  p_manage_token uuid,
  p_status public.rsvp_status,
  p_plus_one_count integer,
  p_reminder_opt_in boolean default true
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.rsvps r
  set status = p_status, plus_one_count = p_plus_one_count, reminder_opt_in = p_reminder_opt_in
  from public.events e
  where r.event_id = e.id and r.manage_token = p_manage_token and p_plus_one_count between 0 and e.plus_one_limit;
  if not found then raise exception 'RSVP not found or plus-one count is invalid'; end if;
end;
$$;

revoke all on function public.get_public_event(uuid) from public;
revoke all on function public.submit_rsvp(uuid, text, text, public.rsvp_status, integer, boolean) from public;
revoke all on function public.update_rsvp_with_token(uuid, public.rsvp_status, integer, boolean) from public;
grant execute on function public.get_public_event(uuid) to anon, authenticated;
grant execute on function public.submit_rsvp(uuid, text, text, public.rsvp_status, integer, boolean) to anon, authenticated;
grant execute on function public.update_rsvp_with_token(uuid, public.rsvp_status, integer, boolean) to anon, authenticated;
