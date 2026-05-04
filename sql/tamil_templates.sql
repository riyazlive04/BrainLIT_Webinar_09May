-- ============================================================================
-- TAMIL MESSAGE TEMPLATES
-- ============================================================================
-- Run this in Supabase SQL Editor to add Tamil versions of all 9 stages.
--
-- IMPORTANT: Have a native Tamil speaker review these before sending to real
-- parents. The translations preserve meaning but tone/phrasing may need a
-- local touch-up. After running, edit them in admin → Message templates.
-- ============================================================================

insert into message_templates (stage, language, body) values
  ('registration', 'ta',
   'வணக்கம் {{parent_name}} 👋

நீங்கள் {{webinar_date_local}} அன்று நடக்கும் Brainlit பெற்றோர் வெபினாருக்கு பதிவு செய்துள்ளீர்கள்.

Zoom லிங்க் மற்றும் நினைவூட்டல்களை உங்கள் WhatsApp-க்கே அனுப்புவோம். அழைப்பில் சந்திப்போம்!

— Brainlit'),

  ('reminder_72h', 'ta',
   'வணக்கம் {{parent_name}}, உங்கள் Brainlit வெபினார் இன்னும் 3 நாட்களில் ({{webinar_date_local}}).

நேரத்தை உங்கள் கேலண்டரில் குறித்துக்கொள்ளுங்கள், ஒரு நோட்புக் வைத்துக்கொள்ளுங்கள்.

— Brainlit'),

  ('reminder_48h', 'ta',
   'வணக்கம் {{parent_name}}, இன்னும் 2 நாட்களில் — உங்கள் Brainlit வெபினார் {{webinar_date_local}} அன்று நடைபெறுகிறது.

— Brainlit'),

  ('reminder_24h', 'ta',
   'வணக்கம் {{parent_name}} 👋 நாளையே நாள். உங்கள் Brainlit வெபினார் {{webinar_time_local}} மணிக்கு.

Zoom லிங்க்: {{meeting_link}}

— Brainlit'),

  ('reminder_6h', 'ta',
   'வணக்கம் {{parent_name}}, உங்கள் Brainlit வெபினார் இன்னும் 6 மணி நேரத்தில்.

Zoom லிங்க்: {{meeting_link}}

நாங்கள் சரியான நேரத்தில் தொடங்குவோம்.

— Brainlit'),

  ('reminder_15m', 'ta',
   '15 நிமிடங்கள்! Brainlit வெபினாரில் இங்கே சேருங்கள்:
{{meeting_link}}'),

  ('reminder_5m', 'ta',
   '5 நிமிடங்களில் தொடங்குகிறது. இப்போதே சேருங்கள்:
{{meeting_link}}'),

  ('post_miss_1h', 'ta',
   'வணக்கம் {{parent_name}}, இன்றைய அழைப்பில் உங்களைச் சந்திக்க முடியவில்லை, மன்னிக்கவும்.

அடுத்த அமர்வைப் பற்றி முதலில் தெரிந்துகொள்ள விரும்பினால் NEXT என்று பதிலளியுங்கள்.

— Brainlit'),

  ('post_miss_6h', 'ta',
   'வணக்கம் {{parent_name}}, இன்னொரு நினைவூட்டல் — அடுத்த Brainlit வெபினார் விரைவில் நிரம்பிவிடும்.

NEXT என்று பதிலளியுங்கள், உங்களுக்கு ஒரு இடம் ஒதுக்குகிறேன்.

— Brainlit')
on conflict (stage, language) do nothing;
