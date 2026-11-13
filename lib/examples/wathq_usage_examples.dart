// 📚 مثال عملي شامل - استخدام تكامل Wathq + Nafath
// Example: Complete Integration Implementation

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/nafath_login_sheet.dart';

// ============================================
// مثال 1: استخدام الخدمة في شاشة الدخول
// ============================================

class LoginScreenExample extends StatelessWidget {
  const LoginScreenExample({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تسجيل الدخول عبر نفاذ')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () => NafathLoginSheet.show(context, isAr: true),
              child: const Text('دخول عبر نفاذ'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================
// مثال 2: عرض بيانات الشركة
// ============================================

class CompanyProfilePageExample extends StatefulWidget {
  final String companyId;

  const CompanyProfilePageExample({
    super.key,
    required this.companyId,
  });

  @override
  State<CompanyProfilePageExample> createState() =>
      _CompanyProfilePageExampleState();
}

class _CompanyProfilePageExampleState extends State<CompanyProfilePageExample> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('بيانات الشركة')),
      body: FutureBuilder(
        future: Supabase.instance.client
            .from('company_profiles')
            .select()
            .eq('id', widget.companyId)
            .single(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('خطأ: ${snapshot.error}'));
          }

          final data = snapshot.data as Map<String, dynamic>;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _InfoCard(
                title: 'اسم الشركة (العربية)',
                value: data['company_name_ar'] ?? 'غير متوفر',
              ),
              _InfoCard(
                title: 'اسم الشركة (الإنجليزية)',
                value: data['company_name_en'] ?? 'غير متوفر',
              ),
              _InfoCard(
                title: 'رقم السجل التجاري',
                value: data['cr_number'] ?? 'غير متوفر',
              ),
              _InfoCard(
                title: 'نوع الشركة',
                value: data['company_type'] ?? 'غير متوفر',
              ),
              _InfoCard(
                title: 'رأس المال',
                value: '${data['capital'] ?? 0} ريال',
              ),
              _InfoCard(
                title: 'المدينة الرئيسية',
                value: data['headquarters_city'] ?? 'غير متوفر',
              ),
              _InfoCard(
                title: 'الحالة',
                value: data['status'] ?? 'غير متوفر',
              ),
            ],
          );
        },
      ),
    );
  }
}

// ============================================
// مثال 3: عرض بيانات الموظف
// ============================================

class EmployeeProfilePageExample extends StatefulWidget {
  final String userId;

  const EmployeeProfilePageExample({
    super.key,
    required this.userId,
  });

  @override
  State<EmployeeProfilePageExample> createState() =>
      _EmployeeProfilePageExampleState();
}

class _EmployeeProfilePageExampleState
    extends State<EmployeeProfilePageExample> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('بيانات الموظف')),
      body: FutureBuilder(
        future: Supabase.instance.client
            .from('employee_information')
            .select()
            .eq('user_id', widget.userId)
            .maybeSingle(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('خطأ: ${snapshot.error}'));
          }

          if (snapshot.data == null) {
            return const Center(child: Text('لا توجد بيانات موظف'));
          }

          final data = snapshot.data as Map<String, dynamic>;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _InfoCard(
                title: 'اسم صاحب العمل',
                value: data['employer_name'] ?? 'غير متوفر',
              ),
              _InfoCard(
                title: 'المسمى الوظيفي',
                value: data['job_title'] ?? 'غير متوفر',
              ),
              _InfoCard(
                title: 'حالة التوظيف',
                value: data['employment_status'] ?? 'غير متوفر',
              ),
              _InfoCard(
                title: 'قطاع الشركة',
                value: data['company_sector'] ?? 'غير متوفر',
              ),
              _InfoCard(
                title: 'الراتب',
                value: '${data['salary'] ?? 0} ريال',
              ),
              _InfoCard(
                title: 'مكان العمل',
                value: data['work_location'] ?? 'غير متوفر',
              ),
            ],
          );
        },
      ),
    );
  }
}

// ============================================
// Widget مساعد لعرض المعلومات
// ============================================

class _InfoCard extends StatelessWidget {
  final String title;
  final String value;

  const _InfoCard({
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
