-- أعمدة اختيارية لمرفقات الدردشة (صورة/ملف/موقع) دون تكرار جداول.
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS attachment_url text,
  ADD COLUMN IF NOT EXISTS attachment_type text;

COMMENT ON COLUMN public.messages.attachment_url IS
  'رابط عام أو مسار تخزين للمرفق (صورة، ملف، إلخ).';
COMMENT ON COLUMN public.messages.attachment_type IS
  'قيم مقترحة: image | file | location | contact';
