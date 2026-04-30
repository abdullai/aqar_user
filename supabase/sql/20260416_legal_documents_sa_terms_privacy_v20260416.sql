-- =============================================================================
-- نسخة شروط وخصوصية متوافقة مع ممارسات تطبيقات العقار في المملكة (مرجعية)
-- تُحدَّث النسخة النشطة عبر get_active_legal_version() حسب effective_at.
-- بعد التنفيذ: يجب أن يقبل المستخدمون الجدد هذه النسخة من PostAuthShell.
-- =============================================================================

INSERT INTO public.legal_documents_versions (
  version,
  title_ar,
  title_en,
  body_ar,
  body_en,
  effective_at
)
VALUES (
  '2026-04-05-SA',
  'الشروط والأحكام وسياسة الخصوصية — موثوق العقاري',
  'Terms of Use & Privacy Policy — Motawoq Real Estate',
  $ar$
1) التعريف
منصة «موثوق العقاري» تتيح عرض العقارات والتواصل والخدمات المرتبطة بالتسويق العقاري وفق الأنظمة المعمول بها في المملكة العربية السعودية.

2) قبول الشروط
باستخدامك للتطبيق أو الموقع الإلكتروني فإنك تقر بقراءة هذه الوثيقة وموافقتك على ما ورد فيها. إن لم توافق، يُرجى عدم استخدام الخدمة.

3) البيانات التي نعالجها
قد تشمل: بيانات الهوية/الإقامة أو ما يعادلها للتحقق، بيانات الاتصال، بيانات العقار والوسائط (صور، مستندات)، بيانات الرخص المهنية (مثل فال) عند الاقتضاء، وسجلات استخدام تقنية (مثل سجلات الأمان والأعطال) لتحسين الخدمة وحمايتها.

4) الأغراض والأساس النظامي
نستخدم البيانات لتقديم الخدمة، والتحقق من الهوية والامتثال، والتواصل معك، وللالتزام بالمتطلبات التنظيمية ذات الصلة بالقطاع العقاري في المملكة، بما في ذلك ما يتعلق بالهيئة العامة للعقار عند الاقتضاء. يستند المعالجة إلى التعاقد، والموافقة عند الحاجة، والالتزامات النظامية.

5) مشاركة البيانات
لا نبيع بياناتك الشخصية. قد نشارك بيانات ضرورية مع مزودي بنية تحتية (مثل الاستضافة والمراسلات) بعقود سرية، أو عند طلب جهة مختصة وفق الأنظمة.

6) التخزين والأمن
نطبق إجراءات أمنية معقولة لحماية البيانات. لا يمكن ضمان أمان مطلق على الشبكات.

7) حقوقك
حسب الأنظمة المعمول بها (بما يشمل نظام حماية البيانات الشخصية في المملكة حيث ينطبق)، قد يحق لك طلب الاطلاع أو التصحيح أو الحذف أو الاعتراض في الحدود المسموح بها. يُرسل الطلب عبر قنوات الدعم المعتمدة في التطبيق.

8) الاحتفاظ
نحتفظ بالبيانات للمدة اللازمة لأغراض الخدمة والامتثال ثم نُحدّث أو نُلغي الاحتفاظ وفق السياسات الداخلية والأنظمة.

9) التعديلات
قد نُحدّث هذه الوثيقة. عند إصدار نسخة جديدة قد يُطلب منك الموافقة مجدداً قبل المتابعة.

10) الاتصال
للاستفسارات المتعلقة بالخصوصية أو الشروط، استخدم بيانات التواصل المعروضة في التطبيق أو الموقع.
$ar$,
  $en$
1) About
Motawoq Real Estate provides property listings, messaging, and related marketing workflows in line with applicable laws in the Kingdom of Saudi Arabia.

2) Acceptance
By using the app or website you confirm that you have read and agree to this document. If you do not agree, please do not use the service.

3) Data we process
May include: national/Iqama-style identifiers for verification, contact details, property and media (photos, documents), professional licence data (e.g. FAL) where required, and limited technical logs for security and reliability.

4) Purposes and legal bases
We process data to deliver the service, verify identity and compliance, communicate with you, and meet regulatory expectations for the Saudi real estate sector, including REGA-related requirements where applicable. Processing relies on contract, consent where needed, and legal obligations.

5) Sharing
We do not sell personal data. We may share necessary data with infrastructure providers under confidentiality, or with authorities when required by law.

6) Storage and security
We apply reasonable safeguards. No online service can guarantee absolute security.

7) Your rights
Under applicable law (including Saudi PDPL where it applies), you may request access, correction, deletion, or objection within legal limits via the app’s official support channels.

8) Retention
We keep data as long as needed for service delivery and compliance, then update or delete according to policy and law.

9) Changes
We may update this document. A new version may require renewed acceptance before you continue.

10) Contact
Use the in-app or website contact details for privacy or terms questions.
$en$,
  now()
)
ON CONFLICT (version) DO UPDATE SET
  title_ar = EXCLUDED.title_ar,
  title_en = EXCLUDED.title_en,
  body_ar = EXCLUDED.body_ar,
  body_en = EXCLUDED.body_en,
  effective_at = EXCLUDED.effective_at;
