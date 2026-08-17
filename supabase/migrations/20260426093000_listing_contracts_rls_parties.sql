-- Allow listing contract parties to read their contracts, and keep the old
-- client insert path working until all deployed web bundles use the RPC.

BEGIN;

ALTER TABLE public.listing_contracts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS listing_contracts_select_parties
  ON public.listing_contracts;
CREATE POLICY listing_contracts_select_parties
  ON public.listing_contracts
  FOR SELECT
  TO authenticated
  USING (
    owner_id = auth.uid()
    OR marketer_id = auth.uid()
  );

DROP POLICY IF EXISTS listing_contracts_insert_selected_offer_marketer
  ON public.listing_contracts;
CREATE POLICY listing_contracts_insert_selected_offer_marketer
  ON public.listing_contracts
  FOR INSERT
  TO authenticated
  WITH CHECK (
    status = 'draft'::contract_status
    AND (
      owner_id = auth.uid()
      OR (
        marketer_id = auth.uid()
        AND EXISTS (
          SELECT 1
          FROM public.listing_requests lr
          JOIN public.listing_offers lo ON lo.id = listing_contracts.offer_id
          WHERE lr.id = listing_contracts.request_id
            AND lr.owner_id = listing_contracts.owner_id
            AND lr.selected_offer_id = listing_contracts.offer_id
            AND lo.request_id = listing_contracts.request_id
            AND lo.marketer_id = auth.uid()
            AND coalesce(lo.status::text, '') IN ('owner_accepted', 'selected')
        )
      )
    )
  );

DROP POLICY IF EXISTS listing_contracts_update_parties
  ON public.listing_contracts;
CREATE POLICY listing_contracts_update_parties
  ON public.listing_contracts
  FOR UPDATE
  TO authenticated
  USING (
    owner_id = auth.uid()
    OR marketer_id = auth.uid()
  )
  WITH CHECK (
    owner_id = auth.uid()
    OR marketer_id = auth.uid()
  );

COMMIT;
