-- عمود اختياري لربط المحادثة بطلب تسويق — التطبيق لا يعتمد عليه للفتح.
-- يمنع 42703 إن طُلب العمود من عميل قديم، ويوحّد المخطط مع المسارات الجديدة.

ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS listing_request_id uuid;

COMMENT ON COLUMN public.conversations.listing_request_id IS
  'اختياري: طلب تسويق مرتبط بالمحادثة. الفتح لا يتطلّب وجود القيمة.';

CREATE INDEX IF NOT EXISTS idx_conversations_listing_request_id
  ON public.conversations (listing_request_id)
  WHERE listing_request_id IS NOT NULL;
