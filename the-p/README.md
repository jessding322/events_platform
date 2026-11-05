# Event Hosting Platform

## Overview

A lightweight platform for creating private events and sharing a simple RSVP page with friends. Hosts publish event details, track responses and plus ones, and send attendees a reminder on the day of the event.

## Goals

- Let a host create and manage an event with a title, date, time, location, and description.
- Give each event a shareable RSVP link that guests can use without a complicated signup flow.
- Let guests respond and indicate how many people are attending, including plus ones.
- Give hosts a clear attendee count and guest list.
- Send an event-day reminder to guests who plan to attend.

## Users and Main Flows

### Host

1. Create an account or start a host session.
2. Create an event with its title, date, local start time, location, and description.
3. Review the event page and copy its unique share link.
4. See guest responses, attendance totals, and plus-one counts.
5. Edit or cancel the event; notify guests if important details change.

### Guest

1. Open the shared event link.
2. Review the event details.
3. Submit an RSVP with their name, email address, response (attending or unable to attend), and number of additional guests.
4. Update their response later using a secure link or an email-based sign-in flow.
5. Receive an event-day reminder if attending and they provided a valid email address.

## MVP Scope

- Host account and event creation/editing.
- Public, unlisted event page with a hard-to-guess share URL.
- RSVP form with attending / unable to attend responses and a configurable plus-one limit.
- Optional host setting to close RSVPs or set a response deadline.
- Host view of responses and total expected attendance.
- Event-day email reminder for attending guests, with a configurable send time and event timezone.
- Basic event cancellation and guest notification.
- Responsive, accessible pages for mobile and desktop.

## Out of Scope for the First Version

- Ticket sales, payments, seating charts, and check-in tools.
- Public event discovery or search.
- Complex invitation roles, group messaging, or recurring events.
- Native mobile apps and multi-channel reminders (SMS, push notifications).

## Core Data Model

- **User**: id, name, email, authentication fields, created_at.
- **Event**: id, host_id, title, description, location, starts_at, timezone, rsvp_deadline, plus_one_limit, status, share_token, created_at, updated_at.
- **RSVP**: id, event_id, guest_name, guest_email, status, plus_one_count, reminder_opt_in, manage_token, created_at, updated_at.
- **Reminder delivery**: id, event_id, rsvp_id, scheduled_at, sent_at, status, provider_message_id, error details.

Store event time as a timezone-aware timestamp and retain the IANA timezone (for example, `America/New_York`) so event details and reminder delivery remain correct across daylight-saving changes. Calculate attendance as attending RSVPs plus their plus-one counts; do not count declined RSVPs.

## Product Rules

- Require title, date/time, location, and a host; allow the description to be blank.
- Validate that the event date is in the future when it is created, while allowing a host to edit a past event if needed.
- A guest can submit one RSVP per event email address; provide a way to revise it.
- Plus-one counts must be whole numbers from zero through the host's configured limit.
- Only attending guests with a deliverable email address receive reminders.
- Make reminder jobs idempotent so retries do not send duplicate messages.
- If an event is edited or canceled, update pending reminder jobs and clearly notify affected guests.
- Protect guest email addresses and manage tokens; avoid exposing attendee details on the public event page.

## Key Screens

1. **Host dashboard** — upcoming and past events, attendee totals, create-event action.
2. **Event editor** — event details, timezone, RSVP deadline, plus-one limit, reminder settings.
3. **Shareable event page** — event details and RSVP form.
4. **Host attendee view** — response list, plus-one counts, totals, and export option (optional for MVP).
5. **RSVP confirmation/manage page** — response summary and update/cancel controls.

## Reminder Behavior

- Schedule one reminder per attending RSVP for the event day, at a host-selected local time (default: 9:00 AM in the event's timezone).
- Show the guest's event date, start time, location, and a link to the event page in the email.
- Skip reminders for declined RSVPs, missing/invalid addresses, canceled events, or guests who opted out.
- Re-check RSVP and event status immediately before sending.
- Record send attempts and failures, retry temporary provider errors with a bounded backoff, and expose delivery status to the host.
- Define behavior for events created after the reminder time: send promptly if the event has not started, or skip according to an explicit product setting.

## Suggested Technical Shape

Keep the first release as a small web application with:

- A frontend for the host dashboard, event editor, and public RSVP pages.
- A backend API that validates ownership, event state, RSVP changes, and plus-one limits.
- A relational database for users, events, RSVPs, and reminder records.
- A background worker and durable job queue for scheduling and sending reminders.
- An email provider integration for RSVP confirmations, event updates, cancellations, and reminders.

Choose the framework, database, hosting provider, and email service based on the project's existing stack. Keep reminder scheduling behind a provider-neutral service so the email vendor can change without rewriting event logic.

## Privacy, Security, and Accessibility

- Treat share links as unlisted rather than secret-proof; make the host aware that anyone with the link can view event details and RSVP.
- Use unpredictable tokens for share and RSVP management links, and support revoking or rotating the event share link.
- Rate-limit RSVP submissions and use server-side validation for all guest input.
- Limit host access to events they own; avoid publishing guest names, emails, or RSVP totals unless the host explicitly chooses to.
- Collect only the guest data needed to manage attendance and send requested reminders; provide a clear way to opt out of reminder emails.
- Use semantic form labels, keyboard navigation, visible focus states, and readable error messages.

## Success Measures

- Hosts can create an event and share its RSVP link without assistance.
- Guests can RSVP and update their response on mobile.
- Host attendance totals match RSVP and plus-one counts.
- Event-day reminders are delivered at the configured local time without duplicate sends.
- Hosts can identify failed reminder deliveries and correct invalid addresses.

## Open Product Decisions

- Are guest accounts ever required, or should RSVP always work by email and secure manage link?
- Should the host be able to cap total attendance in addition to limiting plus ones per RSVP?
- Can guests RSVP without giving an email address, and if so, how should they manage their response?
- Should guests see other attendees, and should hosts be able to hide or reveal the attendee list?
- What should happen when an event is created after its configured reminder time?
- Should reminders be sent only by email in the MVP, or is SMS a launch requirement?

## Suggested Delivery Sequence

1. Define the event and RSVP rules, including timezone and plus-one behavior.
2. Build event creation, editing, and the shareable event page.
3. Add RSVP submission, revision, and host attendee totals.
4. Add email confirmations and host notifications for new RSVPs.
5. Add durable event-day reminder scheduling, delivery logs, and retry handling.
6. Add cancellation/update notifications, accessibility review, and privacy safeguards.
