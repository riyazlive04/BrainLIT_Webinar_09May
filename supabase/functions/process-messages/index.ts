// Supabase Edge Function: process-messages
// Polls scheduled_messages for due rows and sends them via Evolution WhatsApp API.
// Triggered every minute by pg_cron.
//
// Required Edge Function secrets:
//   EVOLUTION_API_URL, EVOLUTION_INSTANCE, EVOLUTION_API_KEY
// (SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are auto-provided.)
//
// Attendance-gated stages (queued by trigger when admin clicks Attended/Missed):
//   post_attended  → sends only if reg.attended === true  (defensive re-check)
//   post_miss      → sends only if reg.attended === false (defensive re-check)
// If admin un-marks before the cron tick, the trigger cancels the row.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

Deno.serve(async (_req) => {
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )

  const EVOLUTION_URL      = Deno.env.get('EVOLUTION_API_URL')!
  const EVOLUTION_INSTANCE = Deno.env.get('EVOLUTION_INSTANCE')!
  const EVOLUTION_KEY      = Deno.env.get('EVOLUTION_API_KEY')!
  const MAX_ATTEMPTS = 3

  // 1. Atomically claim a batch of due messages
  const { data: claimed, error: claimErr } = await supabase
    .rpc('claim_due_messages', { claim_limit: 50 })

  if (claimErr) {
    return new Response(JSON.stringify({ ok: false, error: claimErr.message }), { status: 500 })
  }
  if (!claimed || claimed.length === 0) {
    return new Response(JSON.stringify({ ok: true, processed: 0 }), { status: 200 })
  }

  // 2. Bulk-fetch the related registrations + templates once
  const regIds = [...new Set(claimed.map((m: any) => m.registration_id))]
  const { data: regs } = await supabase.from('registrations').select('*').in('id', regIds)
  const regMap = new Map((regs ?? []).map((r: any) => [r.id, r]))

  const { data: templates } = await supabase
    .from('message_templates').select('stage, language, body').eq('enabled', true)
  const tplMap = new Map((templates ?? []).map((t: any) => [`${t.stage}::${t.language}`, t.body]))
  const getTemplate = (stage: string, language: string): string | null =>
    tplMap.get(`${stage}::${language}`) ?? tplMap.get(`${stage}::en`) ?? null

  let sent = 0, failed = 0, cancelled = 0

  for (const msg of claimed as any[]) {
    const reg = regMap.get(msg.registration_id) as any
    const finalize = (patch: Record<string, unknown>) =>
      supabase.from('scheduled_messages').update(patch).eq('id', msg.id)

    if (!reg) {
      await finalize({ status: 'failed', error: 'Registration not found' })
      failed++; continue
    }

    // Defensive re-check at send time (in case admin changed attendance between trigger and cron tick)
    if (msg.stage === 'post_attended' && reg.attended !== true) {
      await finalize({ status: 'cancelled', sent_at: new Date().toISOString(), error: 'Attendance no longer true; skipped' })
      cancelled++; continue
    }
    if (msg.stage === 'post_miss' && reg.attended !== false) {
      await finalize({ status: 'cancelled', sent_at: new Date().toISOString(), error: 'Attendance no longer false; skipped' })
      cancelled++; continue
    }

    let body = getTemplate(msg.stage, reg.language ?? 'en')
    if (!body) {
      await finalize({ status: 'failed', error: `No template for stage=${msg.stage}` })
      failed++; continue
    }

    // Variable substitution
    const dt = new Date(reg.webinar_date)
    const dateLocal = dt.toLocaleString('en-IN', {
      day: 'numeric', month: 'long', year: 'numeric',
      hour: 'numeric', minute: '2-digit', hour12: true, timeZone: 'Asia/Kolkata'
    })
    const timeLocal = dt.toLocaleString('en-IN', {
      hour: 'numeric', minute: '2-digit', hour12: true, timeZone: 'Asia/Kolkata'
    })
    body = body
      .replaceAll('{{parent_name}}', reg.parent_name ?? '')
      .replaceAll('{{webinar_date_local}}', dateLocal)
      .replaceAll('{{webinar_time_local}}', timeLocal)
      .replaceAll('{{meeting_link}}', reg.meeting_link ?? '')

    // Send via Evolution API
    try {
      const res = await fetch(`${EVOLUTION_URL}/message/sendText/${EVOLUTION_INSTANCE}`, {
        method: 'POST',
        headers: { 'apikey': EVOLUTION_KEY, 'Content-Type': 'application/json' },
        body: JSON.stringify({ number: String(reg.whatsapp), text: body })
      })

      if (res.ok) {
        await finalize({ status: 'sent', sent_at: new Date().toISOString(), error: null })
        sent++
      } else {
        const errText = (await res.text()).slice(0, 500)
        const isPermFailure = res.status >= 400 && res.status < 500 && res.status !== 429
        const exhausted = msg.attempts >= MAX_ATTEMPTS
        await finalize({
          status: (isPermFailure || exhausted) ? 'failed' : 'pending',
          error: `HTTP ${res.status}: ${errText}`
        })
        failed++
      }
    } catch (e) {
      const exhausted = msg.attempts >= MAX_ATTEMPTS
      await finalize({
        status: exhausted ? 'failed' : 'pending',
        error: String(e).slice(0, 500)
      })
      failed++
    }

    // Gentle rate limit (5 msg/sec max)
    await new Promise(r => setTimeout(r, 200))
  }

  return new Response(JSON.stringify({ ok: true, processed: claimed.length, sent, failed, cancelled }), {
    headers: { 'Content-Type': 'application/json' }, status: 200
  })
})
