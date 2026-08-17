// ignore_for_file: avoid_web_libraries_in_flutter

/// سابقاً: إعادة تحميل كاملة للصفحة بعد الخروج.
///
/// **تم تعطيلها:** `reload` / `location.replace` لنفس المسار أثناء أو بعد `Navigator.pushNamedAndRemoveUntil`
/// كان يتسبب في تجمّد التبويب (تعارض مع محرك Flutter على الويب) وفي تعارض مع تحديث الصفحة وحذف الكاش.
/// التنقل إلى `/login` + تنظيف الجلسة محلياً يكفي؛ أي حاجة لإعادة بناء كاملة يفضّلها المستخدم يدوياً من المتصفح.
void appWebHardReloadAfterLogout() {}
