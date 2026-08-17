-- إصلاح جذري لأخطاء الإنتاج (2026-07-29):
-- 1) column "round_no" of relation "listing_request_invites" does not exist
-- 2) column lp.broker_nid does not exist

BEGIN;

-- A) listing_request_invites.round_no
ALTER TABLE IF EXISTS public.listing_request_invites
  ADD COLUMN IF NOT EXISTS round_no integer;

UPDATE public.listing_request_invites inv
   SET round_no = coalesce(
         (
           SELECT lr.marketing_round
           FROM public.listing_requests lr
           WHERE lr.id = inv.request_id
           LIMIT 1
         ),
         1
       )
 WHERE inv.round_no IS NULL;

ALTER TABLE IF EXISTS public.listing_request_invites
  ALTER COLUMN round_no SET DEFAULT 1;

UPDATE public.listing_request_invites
   SET round_no = 1
 WHERE round_no IS NULL;

DO $$
BEGIN
  IF to_regclass('public.listing_request_invites') IS NULL THEN
    RETURN;
  END IF;
  BEGIN
    ALTER TABLE public.listing_request_invites
      ALTER COLUMN round_no SET NOT NULL;
  EXCEPTION
    WHEN others THEN
      RAISE NOTICE 'round_no NOT NULL skipped: %', SQLERRM;
  END;
  BEGIN
    CREATE INDEX IF NOT EXISTS idx_listing_request_invites_request_round
      ON public.listing_request_invites (request_id, round_no);
  EXCEPTION
    WHEN undefined_column THEN
      RAISE NOTICE 'idx on request_id skipped';
  END;
END;
$$;

-- B) listing_permits.broker_nid
ALTER TABLE IF EXISTS public.listing_permits
  ADD COLUMN IF NOT EXISTS broker_nid text;

UPDATE public.listing_permits
   SET broker_nid = nullif(
         trim(substring(notes from 'broker_nid:[[:space:]]*(.+)$')),
         ''
       )
 WHERE coalesce(nullif(trim(broker_nid), ''), '') = ''
   AND notes IS NOT NULL
   AND notes ~* 'broker_nid:';

-- C) upsert يكتب العمود + notes
CREATE OR REPLACE FUNCTION public.upsert_listing_permit_for_publish(
  p_request_id uuid,
  p_permit_no text,
  p_broker_nid text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  req record;
  v_id uuid;
  v_notes text;
  v_nid text := nullif(trim(coalesce(p_broker_nid, '')), '');
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT * INTO req FROM public.listing_requests WHERE id = p_request_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'request_not_found';
  END IF;

  IF req.selected_marketer_id IS NULL OR uid IS DISTINCT FROM req.selected_marketer_id THEN
    RAISE EXCEPTION 'not_selected_marketer';
  END IF;

  v_notes := CASE
    WHEN v_nid IS NULL THEN NULL
    ELSE 'broker_nid:' || v_nid
  END;

  SELECT p.id
    INTO v_id
  FROM public.listing_permits p
  WHERE p.request_id = p_request_id
    AND p.marketer_id = uid
    AND p.status <> 'rejected'::permit_status
  ORDER BY
    CASE WHEN p.status::text = 'approved' THEN 0 ELSE 1 END,
    p.created_at DESC NULLS LAST,
    p.id DESC
  LIMIT 1
  FOR UPDATE;

  IF v_id IS NOT NULL THEN
    UPDATE public.listing_permits
       SET permit_no = trim(p_permit_no),
           license_no = trim(p_permit_no),
           authority_name = 'REGA',
           status = 'submitted'::permit_status,
           submitted_at = now(),
           notes = v_notes,
           broker_nid = coalesce(v_nid, broker_nid)
     WHERE id = v_id;
  ELSE
    INSERT INTO public.listing_permits (
      request_id,
      marketer_id,
      permit_no,
      license_no,
      authority_name,
      status,
      submitted_at,
      notes,
      broker_nid,
      created_at
    ) VALUES (
      p_request_id,
      uid,
      trim(p_permit_no),
      trim(p_permit_no),
      'REGA',
      'submitted'::permit_status,
      now(),
      v_notes,
      v_nid,
      now()
    )
    RETURNING id INTO v_id;
  END IF;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_listing_permit_for_publish(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_listing_permit_for_publish(uuid, text, text) TO authenticated;

COMMIT;
