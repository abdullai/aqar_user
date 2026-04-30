/// خطافات توثيق لدمج لوحة الإشراف لاحقاً (لا منطق تشغيل هنا).
///
/// ADMIN_HOOK: Fetch live session logs — اربط لوحة الإدارة بجدول user_login_audit / user_session_state عبر Edge Function بصلاحية service_role.
/// ADMIN_HOOK: Remote force-logout trigger — استدعِ bump_user_session_epoch أو امسح refresh tokens عبر Admin API من الخادم فقط.
library admin_security_hooks;

