-- طبّق في Supabase SQL Editor إن لم تُشغَّل الهجرة.
ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS listing_request_id uuid;

CREATE INDEX IF NOT EXISTS idx_conversations_listing_request_id
  ON public.conversations (listing_request_id)
  WHERE listing_request_id IS NOT NULL;
