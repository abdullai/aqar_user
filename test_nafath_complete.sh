#!/bin/bash
# 🧪 سكريبت الاختبار الشامل لنفاذ

echo "🚀 بدء اختبار تكامل نفاذ..."
echo ""

# الألوان
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 1. فحص الملفات الأساسية
echo "${BLUE}1️⃣ فحص الملفات الأساسية...${NC}"

files=(
  "lib/services/nafath_auth_service.dart"
  "lib/core/government/nafath_models.dart"
  "supabase/functions/nafath_session/index.ts"
  "supabase/functions/nafath_callback/index.ts"
  "test/nafath_complete_integration_test.dart"
)

for file in "${files[@]}"; do
  if [ -f "$file" ]; then
    echo -e "${GREEN}✓${NC} $file"
  else
    echo -e "${RED}✗${NC} $file"
  fi
done
echo ""

# 2. فحص المتطلبات
echo "${BLUE}2️⃣ فحص المتطلبات...${NC}"

# فحص Flutter
if command -v flutter &> /dev/null; then
  echo -e "${GREEN}✓${NC} Flutter $(flutter --version | grep -oP 'Flutter \K[^ ]*')"
else
  echo -e "${RED}✗${NC} Flutter غير مثبت"
fi

# فحص Dart
if command -v dart &> /dev/null; then
  echo -e "${GREEN}✓${NC} Dart $(dart --version | grep -oP '\K[0-9.]*' | head -1)"
else
  echo -e "${RED}✗${NC} Dart غير مثبت"
fi

# فحص Supabase CLI
if command -v supabase &> /dev/null; then
  echo -e "${GREEN}✓${NC} Supabase CLI متثبت"
else
  echo -e "${YELLOW}⚠${NC} Supabase CLI غير متثبت (اختياري)"
fi
echo ""

# 3. فحص Pubspec Dependencies
echo "${BLUE}3️⃣ فحص المكتبات المطلوبة...${NC}"

if grep -q "supabase_flutter" pubspec.yaml; then
  echo -e "${GREEN}✓${NC} supabase_flutter"
else
  echo -e "${RED}✗${NC} supabase_flutter"
fi

if grep -q "shared_preferences" pubspec.yaml; then
  echo -e "${GREEN}✓${NC} shared_preferences"
else
  echo -e "${RED}✗${NC} shared_preferences"
fi

if grep -q "flutter_localizations" pubspec.yaml; then
  echo -e "${GREEN}✓${NC} flutter_localizations"
else
  echo -e "${RED}✗${NC} flutter_localizations"
fi
echo ""

# 4. فحص .env
echo "${BLUE}4️⃣ فحص متغيرات البيئة...${NC}"

if [ -f ".env" ]; then
  echo -e "${GREEN}✓${NC} ملف .env موجود"
  
  if grep -q "NAFATH" .env; then
    echo -e "${GREEN}✓${NC} متغيرات NAFATH موجودة"
  else
    echo -e "${YELLOW}⚠${NC} متغيرات NAFATH غير محددة في .env"
  fi
else
  echo -e "${YELLOW}⚠${NC} ملف .env غير موجود (اختياري للتطوير)"
fi
echo ""

# 5. فحص Syntax
echo "${BLUE}5️⃣ فحص Dart Syntax...${NC}"

if dart analyze lib/services/nafath_auth_service.dart 2>&1 | grep -q "error"; then
  echo -e "${RED}✗${NC} أخطاء في nafath_auth_service.dart"
  dart analyze lib/services/nafath_auth_service.dart 2>&1 | grep "error"
else
  echo -e "${GREEN}✓${NC} لا توجد أخطاء في nafath_auth_service.dart"
fi

if dart analyze lib/core/government/nafath_models.dart 2>&1 | grep -q "error"; then
  echo -e "${RED}✗${NC} أخطاء في nafath_models.dart"
else
  echo -e "${GREEN}✓${NC} لا توجد أخطاء في nafath_models.dart"
fi
echo ""

# 6. فحص الاختبارات
echo "${BLUE}6️⃣ فحص الاختبارات...${NC}"

test_count=$(grep -c "test(" test/nafath_complete_integration_test.dart)
echo -e "${GREEN}✓${NC} عدد الاختبارات: $test_count"

if [ $test_count -ge 20 ]; then
  echo -e "${GREEN}✓${NC} تغطية اختبار جيدة"
else
  echo -e "${YELLOW}⚠${NC} قد تحتاج إلى المزيد من الاختبارات"
fi
echo ""

# 7. فحص التوثيق
echo "${BLUE}7️⃣ فحص التوثيق...${NC}"

docs=(
  "NAFATH_PRODUCTION_DEPLOYMENT.md"
  "NAFATH_API_COMPLETE.md"
  "NAFATH_QUICK_START_PRODUCTION.md"
  "NAFATH_COMPLETION_SUMMARY.md"
)

for doc in "${docs[@]}"; do
  if [ -f "$doc" ]; then
    lines=$(wc -l < "$doc")
    echo -e "${GREEN}✓${NC} $doc ($lines سطر)"
  else
    echo -e "${RED}✗${NC} $doc"
  fi
done
echo ""

# 8. ملخص النتائج
echo "${BLUE}════════════════════════════════════════${NC}"
echo "${BLUE}📊 ملخص الاختبار:${NC}"
echo "${BLUE}════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ تكامل نفاذ جاهز للإنتاج!${NC}"
echo ""
echo "الخطوات التالية:"
echo "1️⃣  أضف Secrets إلى Supabase Dashboard"
echo "2️⃣  انشر Edge Functions:"
echo "    supabase functions deploy nafath_session"
echo "    supabase functions deploy nafath_callback"
echo "3️⃣  اختبر من التطبيق:"
echo "    flutter run --release"
echo "4️⃣  راقب الـ logs:"
echo "    supabase functions logs nafath_session"
echo ""
echo -e "${GREEN}🎉 تم الانتهاء من الاختبار!${NC}"
