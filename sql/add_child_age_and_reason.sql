-- ============================================================================
-- Add child_age and reason columns to registrations
-- ============================================================================
-- Run in Supabase SQL Editor before deploying the new form to production.
-- Existing registrations will have NULL for both columns; that's expected.
-- ============================================================================

alter table registrations
  add column if not exists child_age smallint check (child_age between 4 and 17),
  add column if not exists reason text check (reason in ('ai_literacy', 'future_readiness_with_ai', 'just_exploring'));
