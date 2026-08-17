import 'package:flutter/material.dart';

import '../../widgets/form_exit_confirm_dialog.dart';

/// تسجيل نموذج نشط (إعلان / طلب) لاعتراض تبديل التبويب أو إغلاق مسار اللوحة.
class ActiveFormGuardHandle {
  const ActiveFormGuardHandle({
    required this.id,
    required this.hasUnsavedInput,
    required this.isPublishing,
    required this.onSaveDraft,
    required this.onDiscard,
    this.leaveTitleAr,
    this.leaveTitleEn,
  });

  final String id;
  final bool Function() hasUnsavedInput;
  final bool Function() isPublishing;
  final Future<void> Function() onSaveDraft;
  final Future<void> Function() onDiscard;
  final String? leaveTitleAr;
  final String? leaveTitleEn;
}

class ActiveFormGuard {
  ActiveFormGuard._();

  static final ActiveFormGuard instance = ActiveFormGuard._();

  ActiveFormGuardHandle? _active;

  void register(ActiveFormGuardHandle handle) {
    _active = handle;
  }

  void unregister(String id) {
    if (_active?.id == id) _active = null;
  }

  bool get hasBlockingForm {
    final h = _active;
    if (h == null) return false;
    if (h.isPublishing()) return true;
    return h.hasUnsavedInput();
  }

  /// true = يمكن المتابعة (تبديل تبويب / إغلاق المسار).
  Future<bool> confirmLeaveIfNeeded(
    BuildContext context, {
    required bool isAr,
    Future<void> Function()? popFormRoute,
  }) async {
    final h = _active;
    if (h == null) return true;
    if (h.isPublishing()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(isAr
              ? 'جاري النشر… يرجى الانتظار.'
              : 'Publishing in progress… please wait.'),
        ),
      );
      return false;
    }
    if (!h.hasUnsavedInput()) return true;

    final choice = await showFormExitConfirmDialog(
      context: context,
      isAr: isAr,
      title: isAr
          ? (h.leaveTitleAr ?? 'هل تريد الإغلاق؟')
          : (h.leaveTitleEn ?? 'Leave this form?'),
    );
    if (!context.mounted || choice == null) return false;
    if (choice == FormExitChoice.keepEditing) return false;
    if (choice == FormExitChoice.saveDraft) {
      await h.onSaveDraft();
    } else {
      await h.onDiscard();
    }
    if (popFormRoute != null) {
      await popFormRoute();
    }
    return true;
  }
}
