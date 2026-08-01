-- هوية الناشر العامة: اسم رسمي vs مستعار، جوال أساسي vs إضافي، ظهور الحضور على البطاقات.
-- أعمدة اختيارية تُضاف بأمان إن لم تكن موجودة.

do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'users_profiles'
      and column_name = 'display_name'
  ) then
    alter table public.users_profiles
      add column display_name text;
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'users_profiles'
      and column_name = 'public_name_source'
  ) then
    alter table public.users_profiles
      add column public_name_source text
        not null default 'official'
        check (public_name_source in ('official', 'display'));
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'users_profiles'
      and column_name = 'secondary_phone'
  ) then
    alter table public.users_profiles
      add column secondary_phone text;
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'users_profiles'
      and column_name = 'public_phone_source'
  ) then
    alter table public.users_profiles
      add column public_phone_source text
        not null default 'primary'
        check (public_phone_source in ('primary', 'secondary', 'hidden'));
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'users_profiles'
      and column_name = 'publish_presence_on_cards'
  ) then
    alter table public.users_profiles
      add column publish_presence_on_cards boolean
        not null default true;
  end if;
end $$;

comment on column public.users_profiles.display_name is
  'اسم الظهور المستعار (قابل للتعديل) — المعاملات الرسمية تستخدم الاسم/الصفة المعتمدة.';
comment on column public.users_profiles.public_name_source is
  'official = الاسم المعتمد | display = المستعار';
comment on column public.users_profiles.secondary_phone is
  'جوال إضافي (مستقبلاً للرسائل النصية)';
comment on column public.users_profiles.public_phone_source is
  'primary | secondary | hidden — أي رقم يظهر للآخرين';
comment on column public.users_profiles.publish_presence_on_cards is
  'هل يظهر متصل الآن / آخر ظهور على بطاقات إعلاناتي وطلباتي عند النشر';
