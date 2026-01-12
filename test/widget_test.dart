import 'package:flutter_test/flutter_test.dart';
import 'package:bos_panglong_app/main.dart';

void main() {
  testWidgets('Dashboard smoke test', (WidgetTester tester) async {
    // 1. Ubah MyApp() menjadi BosPanglongApp() agar tidak error
    await tester.pumpWidget(const BosPanglongApp());

    // 2. Cek apakah teks judul aplikasi muncul di layar
    expect(find.text('Bos Panglong & TB'), findsOneWidget);

    // 3. Cek apakah tombol Menu Utama muncul
    expect(find.text('GUDANG'), findsOneWidget);
    expect(find.text('KASIR'), findsOneWidget);
  });
}