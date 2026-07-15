-- باقات الاشتراك واشتراكات المستخدمين
-- شغّل هذا الملف في Supabase SQL Editor إن رغبت بالمزامنة السحابية.
-- التطبيق يعمل أيضاً بدون الجداول عبر SharedPreferences + الباقات المضمّنة.

create table if not exists public.subscription_plans (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name_ar text not null,
  name_en text not null,
  description_ar text not null default '',
  description_en text not null default '',
  price_sar numeric(12,2) not null default 0,
  duration_days int not null default 30,
  max_active_listings int null,
  featured_listings boolean not null default false,
  priority_support boolean not null default false,
  is_popular boolean not null default false,
  features_ar jsonb not null default '[]'::jsonb,
  features_en jsonb not null default '[]'::jsonb,
  sort_order int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.user_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  plan_code text not null references public.subscription_plans(code),
  status text not null default 'active'
    check (status in ('none','active','pending','expired','cancelled')),
  started_at timestamptz,
  expires_at timestamptz,
  requested_at timestamptz default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_user_subscriptions_user_id
  on public.user_subscriptions(user_id);

alter table public.subscription_plans enable row level security;
alter table public.user_subscriptions enable row level security;

drop policy if exists "plans_read_all" on public.subscription_plans;
create policy "plans_read_all"
  on public.subscription_plans for select
  to authenticated, anon
  using (is_active = true);

drop policy if exists "user_subs_select_own" on public.user_subscriptions;
create policy "user_subs_select_own"
  on public.user_subscriptions for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "user_subs_insert_own" on public.user_subscriptions;
create policy "user_subs_insert_own"
  on public.user_subscriptions for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "user_subs_update_own" on public.user_subscriptions;
create policy "user_subs_update_own"
  on public.user_subscriptions for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

insert into public.subscription_plans (
  code, name_ar, name_en, description_ar, description_en,
  price_sar, duration_days, max_active_listings, featured_listings,
  priority_support, is_popular, features_ar, features_en, sort_order
) values
(
  'free', 'مجاني', 'Free',
  'ابدأ بنشر إعلان واحد مجاناً.',
  'Start with one free active listing.',
  0, 3650, 1, false, false, false,
  '["إعلان نشط واحد","حجز لمدة 72 ساعة","دردشة مرتبطة بالعقار"]'::jsonb,
  '["1 active listing","72-hour reservations","Property-linked chat"]'::jsonb,
  10
),
(
  'basic', 'أساسي', 'Basic',
  'مناسب للأفراد الذين ينشرون عدة عقارات.',
  'Ideal for individuals listing several properties.',
  49, 30, 5, false, false, false,
  '["حتى 5 إعلانات نشطة","إدارة الحجوزات والدردشة","أولوية ظهور أعلى من المجاني"]'::jsonb,
  '["Up to 5 active listings","Reservations & chat management","Higher visibility than Free"]'::jsonb,
  20
),
(
  'pro', 'احترافي', 'Pro',
  'للوسطاء والمحترفين مع ظهور مميز.',
  'For brokers and pros with featured visibility.',
  149, 30, 20, true, true, true,
  '["حتى 20 إعلاناً نشطاً","إعلانات مميزة (Featured)","دعم فني ذو أولوية","شارة مشترك احترافي"]'::jsonb,
  '["Up to 20 active listings","Featured listings","Priority support","Pro subscriber badge"]'::jsonb,
  30
),
(
  'business', 'أعمال', 'Business',
  'للمكاتب والمؤسسات دون حد للإعلانات.',
  'For agencies with unlimited listings.',
  399, 30, null, true, true, false,
  '["إعلانات غير محدودة","إعلانات مميزة","دعم فني ذو أولوية","لوحة متابعة موسّعة قريباً"]'::jsonb,
  '["Unlimited listings","Featured listings","Priority support","Extended dashboard (coming soon)"]'::jsonb,
  40
)
on conflict (code) do update set
  name_ar = excluded.name_ar,
  name_en = excluded.name_en,
  description_ar = excluded.description_ar,
  description_en = excluded.description_en,
  price_sar = excluded.price_sar,
  duration_days = excluded.duration_days,
  max_active_listings = excluded.max_active_listings,
  featured_listings = excluded.featured_listings,
  priority_support = excluded.priority_support,
  is_popular = excluded.is_popular,
  features_ar = excluded.features_ar,
  features_en = excluded.features_en,
  sort_order = excluded.sort_order,
  is_active = true;
