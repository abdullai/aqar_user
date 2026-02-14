part of 'user_dashboard.dart';

extension _UserDashboardState_model_helpers on _UserDashboardState {
  /// ✅ مطابق للاستدعاءات داخل loaders:
  /// _propertyFromDb(row, imageUrls: ..., ownerUsername: ...)
  Property _propertyFromDb(
    Map row, {
    List<String> imageUrls = const <String>[],
    String? ownerUsername,
  }) {
    return Property.fromDbRow(
      row,
      imageUrls: imageUrls,
      ownerUsername: ownerUsername,
    );
  }

  /// ✅ List<dynamic> -> List<Property>
  List<Property> _mapRowsToProperties(
    List<dynamic> rows, {
    List<String> Function(Map row)? imageUrlsOfRow,
    String? Function(Map row)? ownerUsernameOfRow,
  }) {
    return rows
        .whereType<Map>()
        .map((r) => _propertyFromDb(
              r,
              imageUrls: imageUrlsOfRow?.call(r) ?? const <String>[],
              ownerUsername: ownerUsernameOfRow?.call(r),
            ))
        .toList();
  }

  /// ✅ List<dynamic> -> List<String>
  List<String> _toStringList(List<dynamic> xs) =>
      xs.map((e) => e.toString()).toList();
}
