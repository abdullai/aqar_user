import 'package:flutter/material.dart';

class SupportPage extends StatelessWidget {
  final String userId;
  final bool isAr;
  final Color bankColor;

  const SupportPage({
    super.key,
    required this.userId,
    required this.isAr,
    required this.bankColor,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isAr ? 'الدعم الفني' : 'Technical Support'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAr ? 'مركز الدعم الفني' : 'Support Center',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isAr
                          ? 'يسعدنا خدمتكم. يمكنكم التواصل معنا عبر:'
                          : 'We are happy to serve you. You can contact us via:',
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      leading: const Icon(Icons.email),
                      title: Text(isAr ? 'البريد الإلكتروني' : 'Email'),
                      subtitle: const Text('support@aqar.com'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.phone),
                      title: Text(isAr ? 'الهاتف' : 'Phone'),
                      subtitle: const Text('+966 500 000 000'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.schedule),
                      title: Text(isAr ? 'ساعات العمل' : 'Working Hours'),
                      subtitle: Text(isAr ? '9 ص - 5 م' : '9 AM - 5 PM'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAr ? 'الأسئلة الشائعة' : 'Frequently Asked Questions',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ExpansionTile(
                      title: Text(
                          isAr ? 'كيف أضيف إعلاناً؟' : 'How to add a listing?'),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(isAr
                              ? 'اضغط على زر "إضافة إعلان" في الصفحة الرئيسية أو صفحة إعلاناتي واملأ النموذج.'
                              : 'Click "Add Listing" button on Home or My Listings page and fill the form.'),
                        ),
                      ],
                    ),
                    ExpansionTile(
                      title: Text(isAr
                          ? 'كيف أحجز عقاراً؟'
                          : 'How to reserve a property?'),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(isAr
                              ? 'اضغط على زر "إضافة للسلة" في أي عقار متاح.'
                              : 'Click "Add to Cart" button on any available property.'),
                        ),
                      ],
                    ),
                    // أضف المزيد من الأسئلة هنا
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
