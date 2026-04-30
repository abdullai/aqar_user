// dart run tool/generate_in_app_chime.dart
// يولّد assets/sounds/in_app_chime.wav — نغمة قصيرة مزدوجة النبرة.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

void main() {
  const sampleRate = 22050;
  const twoPi = 2 * math.pi;

  final buf = BytesBuilder();

  void addSilence(double seconds) {
    final n = (sampleRate * seconds).round();
    for (var i = 0; i < n; i++) {
      buf.addByte(0);
      buf.addByte(0);
    }
  }

  void addTone(double hz, double seconds) {
    final n = (sampleRate * seconds).round();
    for (var i = 0; i < n; i++) {
      final t = i / sampleRate;
      final env = i < 100
          ? i / 100.0
          : (i > n - 150 ? (n - i) / 150.0 : 1.0);
      final s = (32767 *
              0.32 *
              env *
              math.sin(twoPi * hz * t))
          .round()
          .clamp(-32768, 32767);
      buf.addByte(s & 0xff);
      buf.addByte((s >> 8) & 0xff);
    }
  }

  addTone(659.25, 0.07);
  addSilence(0.02);
  addTone(783.99, 0.09);
  addSilence(0.025);
  addTone(1046.5, 0.055);

  final pcm = buf.toBytes();
  final dataSize = pcm.length;
  final fileSize = 36 + dataSize;

  final header = ByteData(44);
  var o = 0;
  void wStr(String s) {
    for (final c in s.codeUnits) {
      header.setUint8(o++, c);
    }
  }

  wStr('RIFF');
  header.setUint32(o, fileSize, Endian.little);
  o += 4;
  wStr('WAVE');
  wStr('fmt ');
  header.setUint32(o, 16, Endian.little);
  o += 4;
  header.setUint16(o, 1, Endian.little);
  o += 2;
  header.setUint16(o, 1, Endian.little);
  o += 2;
  header.setUint32(o, sampleRate, Endian.little);
  o += 4;
  header.setUint32(o, sampleRate * 2, Endian.little);
  o += 4;
  header.setUint16(o, 2, Endian.little);
  o += 2;
  header.setUint16(o, 16, Endian.little);
  o += 2;
  wStr('data');
  header.setUint32(o, dataSize, Endian.little);
  o += 4;

  final all = Uint8List(o + dataSize);
  all.setRange(0, o, header.buffer.asUint8List().sublist(0, o));
  all.setRange(o, o + dataSize, pcm);

  final f = File('assets/sounds/in_app_chime.wav');
  f.parent.createSync(recursive: true);
  f.writeAsBytesSync(all);
  // ignore: avoid_print
  print('Wrote ${f.path} (${all.length} bytes)');
}
