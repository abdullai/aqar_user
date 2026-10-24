import 'package:flutter_test/flutter_test.dart';
import 'package:aqar_user/core/listing/deed_row_meta.dart';

void main() {
  test('empty row yields no deed values', () {
    expect(DeedRowMeta.number({'id': 'x'}), '');
    expect(DeedRowMeta.date({'id': 'x', 'deed_date': null}), '');
  });

  test('reads preview columns and JSON-string payload', () {
    expect(DeedRowMeta.number({'preview_deed_number': ' 123 '}), '123');
    expect(
      DeedRowMeta.date({'payload': '{"deed_date":"2024-03-05"}'}),
      '2024-03-05',
    );
    expect(
        DeedRowMeta.number({
          'payload_json': {'deed_number': '9'}
        }),
        '9');
  });

  test('property value wins and literal null is ignored', () {
    expect(DeedRowMeta.number({'deed_number': '1'}, '7'), '7');
    expect(DeedRowMeta.number({'deed_number': 'null'}), '');
  });
}
