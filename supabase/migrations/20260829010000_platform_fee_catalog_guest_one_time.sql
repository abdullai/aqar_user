-- دفع الضيف لمرة واحدة: السعر من الكتالوج لا من ثابت في الواجهة.
INSERT INTO public.platform_fee_catalog (fee_key, amount_sar, title_ar, title_en)
VALUES
  ('guest_one_time_deal', 59.00, N'دفع ضيف لمرة واحدة', 'Guest one-time unlock')
ON CONFLICT (fee_key) DO NOTHING;
