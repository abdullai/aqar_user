-- تصعيد بلاغات الإعلانات: عدة مبلّغين مختلفين → إخفاء من الرئيسية + طابور عاجل للإدارة.
-- يعتمد على وجود جدول listing_user_reports (انظر 20260409_listing_user_reports.sql).
--
-- سياسة مبدئية (قابلة للتعديل):
--   • يُحسب عدد المبلّغين المميزين (reporter_user_id) في آخر 7 أيام بحالة pending أو reviewing.
--   • إذا العدد >= 3: home_feed_suppressed = true، وتحديث طابور المراجعة.
--   • فهرس فريد: لا يُسمح بأكثر من بلاغ مفتوح (pending/reviewing) لنفس المستخدم على نفس العقار
--     (يقلّل التضخيم والكيد من حساب واحد؛ سحب البلاغ يتيح إعادة البلاغ لاحقاً).

-- ---------------------------------------------------------------------------
-- أعمدة على properties
-- ---------------------------------------------------------------------------
alter table public.properties
  add column if not exists home_feed_suppressed boolean not null default false;

alter table public.properties
  add column if not exists report_escalated_at timestamptz;

alter table public.properties
  add column if not exists report_distinct_reporters_7d integer not null default 0;

comment on column public.properties.home_feed_suppressed is
  'إخفاء من تغذية الرئيسية/المميز عند تجاوز عتبة بلاغات متعددة من مستخدمين مختلفين (ليس حذف الإعلان).';

-- ---------------------------------------------------------------------------
-- منع بلاغين مفتوحين لنفس المستخدم على نفس العقار
-- ---------------------------------------------------------------------------
create unique index if not exists listing_user_reports_one_open_per_user_property
  on public.listing_user_reports (property_id, reporter_user_id)
  where status in ('pending', 'reviewing')
    and reporter_user_id is not null;

-- ---------------------------------------------------------------------------
-- طابور مراجعة للإدارة (لوحة تستخدم service role)
-- ---------------------------------------------------------------------------
create table if not exists public.listing_moderation_escalations (
  property_id uuid primary key references public.properties (id) on delete cascade,
  distinct_reporters_7d integer not null default 0,
  status text not null default 'open'
    check (status in ('open', 'resolved')),
  first_escalated_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.listing_moderation_escalations enable row level security;

-- لا سياسات لـ authenticated — القراءة/التحديث عبر service role أو لوحة داخلية فقط.

create index if not exists listing_moderation_escalations_status_idx
  on public.listing_moderation_escalations (status)
  where status = 'open';

-- ---------------------------------------------------------------------------
-- دالة + محفزات
-- ---------------------------------------------------------------------------
create or replace function public.refresh_listing_report_aggregate_for_property(p_property_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  distinct_count integer;
  should_suppress boolean;
begin
  if p_property_id is null then
    return;
  end if;

  select count(distinct r.reporter_user_id) into distinct_count
  from public.listing_user_reports r
  where r.property_id = p_property_id
    and r.reporter_user_id is not null
    and r.status in ('pending', 'reviewing')
    and r.created_at > (now() - interval '7 days');

  should_suppress := distinct_count >= 3;

  update public.properties p
  set
    report_distinct_reporters_7d = distinct_count,
    home_feed_suppressed = should_suppress,
    report_escalated_at = case
      when should_suppress and p.report_escalated_at is null then now()
      when not should_suppress then null
      else p.report_escalated_at
    end
  where p.id = p_property_id;

  if should_suppress then
    insert into public.listing_moderation_escalations as m (
      property_id,
      distinct_reporters_7d,
      status,
      first_escalated_at,
      updated_at
    )
    values (
      p_property_id,
      distinct_count,
      'open',
      now(),
      now()
    )
    on conflict (property_id) do update
      set
        distinct_reporters_7d = excluded.distinct_reporters_7d,
        updated_at = now(),
        status = 'open';
  else
    update public.listing_moderation_escalations
    set
      status = 'resolved',
      updated_at = now(),
      distinct_reporters_7d = distinct_count
    where property_id = p_property_id;
  end if;
end;
$$;

create or replace function public.trg_listing_user_reports_refresh_aggregate()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  pid uuid;
begin
  if tg_op = 'DELETE' then
    pid := old.property_id;
  else
    pid := new.property_id;
  end if;
  perform public.refresh_listing_report_aggregate_for_property(pid);
  return coalesce(new, old);
end;
$$;

drop trigger if exists listing_user_reports_aggregate_i on public.listing_user_reports;
drop trigger if exists listing_user_reports_aggregate_u on public.listing_user_reports;
drop trigger if exists listing_user_reports_aggregate_d on public.listing_user_reports;

create trigger listing_user_reports_aggregate_i
  after insert on public.listing_user_reports
  for each row
  execute procedure public.trg_listing_user_reports_refresh_aggregate();

create trigger listing_user_reports_aggregate_u
  after update on public.listing_user_reports
  for each row
  execute procedure public.trg_listing_user_reports_refresh_aggregate();

create trigger listing_user_reports_aggregate_d
  after delete on public.listing_user_reports
  for each row
  execute procedure public.trg_listing_user_reports_refresh_aggregate();

-- إعادة حساب عند تطبيق السكربت على بيانات قائمة (اختياري — قد يكون ثقيلاً على قواعد ضخمة)
-- يمكن تشغيله يدوياً:
-- select refresh_listing_report_aggregate_for_property(id) from properties limit 0;
