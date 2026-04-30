-- طلب المالك إظهار اسمه للجمهور حتى لو عطّل المسوق إظهار المعلن.
ALTER TABLE public.properties
  ADD COLUMN IF NOT EXISTS owner_requests_public_name boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.properties.owner_requests_public_name IS
  'Owner requests their name shown on the listing even when show_advertiser_name is false.';
