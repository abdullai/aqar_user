-- عمود اختياري لمسافة الدعوة (كان الكود يستعلم عنه فيقدّم PostgREST 42703 إن لم يوجد).
ALTER TABLE public.listing_request_invites
  ADD COLUMN IF NOT EXISTS distance_km double precision;

COMMENT ON COLUMN public.listing_request_invites.distance_km IS
  'Optional distance in km from marketer to listing (if computed server-side).';
