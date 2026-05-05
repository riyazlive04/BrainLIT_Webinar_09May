-- ============================================================================
-- POST-WEBINAR MESSAGES: ADMIN-CLICK-TRIGGERED (replaces scheduled post-*)
-- ============================================================================
-- Run this in Supabase SQL Editor.
--
-- New behaviour:
--   - Admin clicks "Attended"  → post_attended message sends within ~60s
--   - Admin clicks "Missed"    → post_miss     message sends within ~60s
--   - Admin un-marks (clicks active button again) → pending message cancelled
--   - No more 1h/6h auto-schedule. Only the 7 pre-webinar messages remain on a schedule.
--
-- Safe to re-run: all changes use IF/ON CONFLICT/REPLACE patterns.
-- ============================================================================

-- 1. Cancel any pending old-format messages so they don't fire
update scheduled_messages
set status = 'cancelled', error = 'Replaced by click-triggered post_attended/post_miss'
where stage in ('post_attended_1h', 'post_attended_6h', 'post_miss_1h', 'post_miss_6h')
  and status = 'pending';

-- 2. Drop old templates (the 4 scheduled post-* stages are no longer used)
delete from message_templates
where stage in ('post_attended_1h', 'post_attended_6h', 'post_miss_1h', 'post_miss_6h');

-- 3. Insert two new English templates (admin can edit them in the UI)
insert into message_templates (stage, language, body) values
  ('post_attended', 'en',
   'Hi {{parent_name}} 🙌

Thank you for joining today''s Brainlit webinar. The one-page framework is on its way to your inbox.

If something landed, hit reply and tell me what you''re going to try first.

— Brainlit'),

  ('post_miss', 'en',
   'Hi {{parent_name}}, sorry we missed you on today''s call.

Reply NEXT if you''d like to be the first to know about the next session.

— Brainlit')
on conflict (stage, language) do nothing;

-- 4. Update the registration insert trigger: only the 7 pre-webinar stages now
create or replace function schedule_registration_messages()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  rec record;
  send_time timestamptz;
begin
  for rec in
    select * from (values
      ('registration',  interval  '0 hours',     true),
      ('reminder_72h',  interval '-72 hours',    false),
      ('reminder_48h',  interval '-48 hours',    false),
      ('reminder_24h',  interval '-24 hours',    false),
      ('reminder_6h',   interval  '-6 hours',    false),
      ('reminder_15m',  interval '-15 minutes',  false),
      ('reminder_5m',   interval  '-5 minutes',  false)
    ) as t(stage, offset_val, is_immediate)
  loop
    if rec.is_immediate then
      send_time := now();
    else
      send_time := new.webinar_date + rec.offset_val;
    end if;

    if not rec.is_immediate and send_time < now() then
      continue;
    end if;

    insert into scheduled_messages (registration_id, stage, send_at)
    values (new.id, rec.stage, send_time);
  end loop;

  return new;
end;
$$;

-- 5. New trigger: queue the right post-* message when admin updates 'attended'
create or replace function on_attendance_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.attended is not distinct from new.attended then
    return new;
  end if;

  -- Cancel any still-pending click-triggered message from a prior click
  update scheduled_messages
  set status = 'cancelled', error = 'Attendance changed before send'
  where registration_id = new.id
    and stage in ('post_attended', 'post_miss')
    and status = 'pending';

  -- Queue the new message based on the new attended value
  if new.attended = true then
    insert into scheduled_messages (registration_id, stage, send_at)
    values (new.id, 'post_attended', now())
    on conflict (registration_id, stage) do update set
      send_at = excluded.send_at,
      status = 'pending',
      attempts = 0,
      error = null,
      sent_at = null
    where scheduled_messages.status not in ('sent', 'processing');
  elsif new.attended = false then
    insert into scheduled_messages (registration_id, stage, send_at)
    values (new.id, 'post_miss', now())
    on conflict (registration_id, stage) do update set
      send_at = excluded.send_at,
      status = 'pending',
      attempts = 0,
      error = null,
      sent_at = null
    where scheduled_messages.status not in ('sent', 'processing');
  end if;

  return new;
end;
$$;

drop trigger if exists trg_attendance_change on registrations;
create trigger trg_attendance_change
  after update of attended on registrations
  for each row execute function on_attendance_change();
