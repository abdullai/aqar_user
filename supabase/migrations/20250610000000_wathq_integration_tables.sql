-- ============================================
-- ملف الهجرة: تكامل APIs Wathq
-- Wathq Integration Database Schema
-- ============================================

BEGIN;

-- ============================================
-- تحديث جدول users_profiles الموجود
-- ============================================

ALTER TABLE public.users_profiles
ADD COLUMN IF NOT EXISTS wathq_unified_id VARCHAR(20),
ADD COLUMN IF NOT EXISTS wathq_user_type VARCHAR(20),
ADD COLUMN IF NOT EXISTS wathq_data JSONB,
ADD COLUMN IF NOT EXISTS wathq_verified_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS wathq_integration_status VARCHAR(50);

-- إنشاء فهرس للبحث السريع
CREATE INDEX IF NOT EXISTS idx_users_profiles_wathq_unified_id
ON public.users_profiles(wathq_unified_id);

-- ============================================
-- جدول 1: بيانات الشركات
-- Table: company_profiles
-- ============================================

CREATE TABLE IF NOT EXISTS public.company_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  cr_number VARCHAR(20) NOT NULL UNIQUE,
  cr_national_number VARCHAR(20) NOT NULL UNIQUE,
  company_name_ar VARCHAR(255) NOT NULL,
  company_name_en VARCHAR(255),
  company_type VARCHAR(100),
  headquarters_city VARCHAR(100),
  capital DECIMAL(15,2),
  company_duration INTEGER,
  status VARCHAR(50),
  has_ecommerce BOOLEAN DEFAULT FALSE,
  issue_date TIMESTAMP WITH TIME ZONE,
  wathq_data JSONB,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- فهارس للشركات
CREATE INDEX IF NOT EXISTS idx_company_profiles_user_id
ON public.company_profiles(user_id);

CREATE INDEX IF NOT EXISTS idx_company_profiles_cr_number
ON public.company_profiles(cr_number);

CREATE INDEX IF NOT EXISTS idx_company_profiles_status
ON public.company_profiles(status);

-- ============================================
-- جدول 2: عناوين الشركات
-- Table: company_addresses
-- ============================================

CREATE TABLE IF NOT EXISTS public.company_addresses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.company_profiles(id) ON DELETE CASCADE,
  address_ar VARCHAR(500) NOT NULL,
  address_en VARCHAR(500),
  building_number VARCHAR(50),
  street_name VARCHAR(200),
  district VARCHAR(100),
  city VARCHAR(100),
  postal_code VARCHAR(10),
  latitude DECIMAL(10,8),
  longitude DECIMAL(11,8),
  is_primary_address BOOLEAN DEFAULT FALSE,
  wathq_data JSONB,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- فهارس للعناوين
CREATE INDEX IF NOT EXISTS idx_company_addresses_company_id
ON public.company_addresses(company_id);

CREATE INDEX IF NOT EXISTS idx_company_addresses_city
ON public.company_addresses(city);

CREATE INDEX IF NOT EXISTS idx_company_addresses_is_primary
ON public.company_addresses(is_primary_address);

-- ============================================
-- جدول 3: بيانات الموظفين
-- Table: employee_information
-- ============================================

CREATE TABLE IF NOT EXISTS public.employee_information (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  national_id VARCHAR(20) NOT NULL,
  employer_name VARCHAR(255),
  job_title VARCHAR(200),
  employment_date TIMESTAMP WITH TIME ZONE,
  contract_end_date TIMESTAMP WITH TIME ZONE,
  salary DECIMAL(12,2),
  employment_type VARCHAR(50),
  employment_status VARCHAR(50),
  company_sector VARCHAR(100),
  company_name_ar VARCHAR(255),
  company_name_en VARCHAR(255),
  work_location VARCHAR(255),
  insurance_number VARCHAR(50),
  wathq_data JSONB,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- فهارس لبيانات الموظفين
CREATE INDEX IF NOT EXISTS idx_employee_information_user_id
ON public.employee_information(user_id);

CREATE INDEX IF NOT EXISTS idx_employee_information_national_id
ON public.employee_information(national_id);

CREATE INDEX IF NOT EXISTS idx_employee_information_employer
ON public.employee_information(employer_name);

-- ============================================
-- جدول 4: الصكوك العقارية
-- Table: real_estate_deeds
-- ============================================

CREATE TABLE IF NOT EXISTS public.real_estate_deeds (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  deed_number VARCHAR(50) NOT NULL UNIQUE,
  deed_serial VARCHAR(50),
  property_type VARCHAR(100),
  location VARCHAR(500),
  area DECIMAL(12,2),
  deed_date TIMESTAMP WITH TIME ZONE,
  property_owner_id VARCHAR(20),
  owner_type VARCHAR(50),
  owner_nationality VARCHAR(100),
  property_status VARCHAR(50),
  municipality_sector VARCHAR(100),
  city VARCHAR(100),
  district VARCHAR(100),
  mortgage_status VARCHAR(50),
  has_charges BOOLEAN DEFAULT FALSE,
  registration_date TIMESTAMP WITH TIME ZONE,
  registration_authority VARCHAR(255),
  wathq_data JSONB,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- فهارس للصكوك
CREATE INDEX IF NOT EXISTS idx_real_estate_deeds_user_id
ON public.real_estate_deeds(user_id);

CREATE INDEX IF NOT EXISTS idx_real_estate_deeds_deed_number
ON public.real_estate_deeds(deed_number);

CREATE INDEX IF NOT EXISTS idx_real_estate_deeds_property_type
ON public.real_estate_deeds(property_type);

CREATE INDEX IF NOT EXISTS idx_real_estate_deeds_city
ON public.real_estate_deeds(city);

-- ============================================
-- جدول 5: سجل التحقق والمزامنة
-- Table: verification_audit_log
-- ============================================

CREATE TABLE IF NOT EXISTS public.verification_audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  verification_type VARCHAR(50), -- 'nafath', 'wathq_commercial', 'wathq_employee', 'deed'
  status VARCHAR(50), -- 'success', 'failed', 'pending'
  result JSONB,
  error_message TEXT,
  ip_address VARCHAR(45),
  user_agent TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- فهارس لسجل التحقق
CREATE INDEX IF NOT EXISTS idx_verification_audit_log_user_id
ON public.verification_audit_log(user_id);

CREATE INDEX IF NOT EXISTS idx_verification_audit_log_created_at
ON public.verification_audit_log(created_at);

CREATE INDEX IF NOT EXISTS idx_verification_audit_log_status
ON public.verification_audit_log(status);

-- ============================================
-- جدول 6: إعدادات التكامل لكل مستخدم
-- Table: wathq_integration_settings
-- ============================================

CREATE TABLE IF NOT EXISTS public.wathq_integration_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  auto_sync_enabled BOOLEAN DEFAULT TRUE,
  sync_frequency VARCHAR(50) DEFAULT 'weekly', -- 'daily', 'weekly', 'monthly', 'manual'
  last_sync_at TIMESTAMP WITH TIME ZONE,
  next_sync_at TIMESTAMP WITH TIME ZONE,
  verification_required_for_posting BOOLEAN DEFAULT FALSE,
  accept_terms_and_conditions BOOLEAN DEFAULT FALSE,
  terms_accepted_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- فهارس
CREATE INDEX IF NOT EXISTS idx_wathq_integration_settings_user_id
ON public.wathq_integration_settings(user_id);

-- ============================================
-- دالة: تحديث updated_at تلقائياً
-- Function: Auto-update timestamp
-- ============================================

CREATE OR REPLACE FUNCTION public.update_wathq_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- تطبيق الدالة على الجداول
DROP TRIGGER IF EXISTS trigger_update_timestamp_company_profiles ON public.company_profiles;
CREATE TRIGGER trigger_update_timestamp_company_profiles
BEFORE UPDATE ON public.company_profiles
FOR EACH ROW
EXECUTE FUNCTION public.update_wathq_timestamp();

DROP TRIGGER IF EXISTS trigger_update_timestamp_company_addresses ON public.company_addresses;
CREATE TRIGGER trigger_update_timestamp_company_addresses
BEFORE UPDATE ON public.company_addresses
FOR EACH ROW
EXECUTE FUNCTION public.update_wathq_timestamp();

DROP TRIGGER IF EXISTS trigger_update_timestamp_employee_information ON public.employee_information;
CREATE TRIGGER trigger_update_timestamp_employee_information
BEFORE UPDATE ON public.employee_information
FOR EACH ROW
EXECUTE FUNCTION public.update_wathq_timestamp();

DROP TRIGGER IF EXISTS trigger_update_timestamp_real_estate_deeds ON public.real_estate_deeds;
CREATE TRIGGER trigger_update_timestamp_real_estate_deeds
BEFORE UPDATE ON public.real_estate_deeds
FOR EACH ROW
EXECUTE FUNCTION public.update_wathq_timestamp();

DROP TRIGGER IF EXISTS trigger_update_timestamp_wathq_integration_settings ON public.wathq_integration_settings;
CREATE TRIGGER trigger_update_timestamp_wathq_integration_settings
BEFORE UPDATE ON public.wathq_integration_settings
FOR EACH ROW
EXECUTE FUNCTION public.update_wathq_timestamp();

-- ============================================
-- سياسات الأمان (RLS)
-- Security Policies
-- ============================================

-- تفعيل RLS
ALTER TABLE public.company_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_addresses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.employee_information ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.real_estate_deeds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wathq_integration_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.verification_audit_log ENABLE ROW LEVEL SECURITY;

-- سياسات company_profiles
DROP POLICY IF EXISTS company_profiles_users_can_view_own ON public.company_profiles;
CREATE POLICY company_profiles_users_can_view_own
  ON public.company_profiles FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS company_profiles_users_can_insert ON public.company_profiles;
DROP POLICY IF EXISTS company_profiles_users_can_update_own ON public.company_profiles;

-- سياسات company_addresses
DROP POLICY IF EXISTS company_addresses_users_can_view_own ON public.company_addresses;
CREATE POLICY company_addresses_users_can_view_own
  ON public.company_addresses FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM company_profiles
    WHERE company_profiles.id = company_addresses.company_id
    AND company_profiles.user_id = auth.uid()
  ));

DROP POLICY IF EXISTS company_addresses_users_can_insert ON public.company_addresses;

-- سياسات employee_information
DROP POLICY IF EXISTS employee_information_users_can_view_own ON public.employee_information;
CREATE POLICY employee_information_users_can_view_own
  ON public.employee_information FOR SELECT
  USING (auth.uid() = user_id);

-- سياسات real_estate_deeds
DROP POLICY IF EXISTS real_estate_deeds_users_can_view_own ON public.real_estate_deeds;
CREATE POLICY real_estate_deeds_users_can_view_own
  ON public.real_estate_deeds FOR SELECT
  USING (auth.uid() = user_id);

-- سياسات wathq_integration_settings
DROP POLICY IF EXISTS wathq_integration_settings_users_can_view_own ON public.wathq_integration_settings;
CREATE POLICY wathq_integration_settings_users_can_view_own
  ON public.wathq_integration_settings FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS wathq_integration_settings_users_can_update_own ON public.wathq_integration_settings;
CREATE POLICY wathq_integration_settings_users_can_update_own
  ON public.wathq_integration_settings FOR UPDATE
  USING (auth.uid() = user_id);

-- سياسات verification_audit_log (للقراءة فقط للمستخدم الخاص به)
DROP POLICY IF EXISTS verification_audit_log_users_can_view_own ON public.verification_audit_log;
CREATE POLICY verification_audit_log_users_can_view_own
  ON public.verification_audit_log FOR SELECT
  USING (auth.uid() = user_id);

-- ============================================
-- تعليقات على الجداول والأعمدة
-- ============================================

COMMENT ON TABLE public.company_profiles IS 'بيانات الشركات والمؤسسات من السجل التجاري';
COMMENT ON TABLE public.company_addresses IS 'العناوين الوطنية للشركات';
COMMENT ON TABLE public.employee_information IS 'بيانات العمل والموظفين';
COMMENT ON TABLE public.real_estate_deeds IS 'الصكوك العقارية والممتلكات';
COMMENT ON TABLE public.verification_audit_log IS 'سجل عمليات التحقق والمزامنة';
COMMENT ON TABLE public.wathq_integration_settings IS 'إعدادات تكامل Wathq لكل مستخدم';

-- ============================================
-- البيانات الأولية (اختياري)
-- ============================================

-- إذا كان لديك مستخدمين موجودين، يمكنك إنشاء إعدادات التكامل لهم:
-- INSERT INTO public.wathq_integration_settings (user_id, auto_sync_enabled)
-- SELECT user_id, true FROM public.users_profiles
-- ON CONFLICT (user_id) DO NOTHING;

COMMIT;
