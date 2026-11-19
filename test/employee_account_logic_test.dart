import 'package:bos_panglong_app/helpers/employee_account_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EmployeeAccountHelper - validation & normalization', () {
    test('normalizes email to trimmed lowercase', () {
      expect(
        EmployeeAccountHelper.normalizeEmail('  Budi.Kasir@Depot.COM  '),
        'budi.kasir@depot.com',
      );
    });

    test('validates employee name, email, and password clearly', () {
      expect(
        EmployeeAccountHelper.validateNewEmployee(
          name: '',
          email: 'budi@depot.com',
          password: 'password123',
        ),
        isNotNull,
      );
      expect(
        EmployeeAccountHelper.validateNewEmployee(
          name: 'Budi',
          email: 'bukan-email',
          password: 'password123',
        ),
        isNotNull,
      );
      expect(
        EmployeeAccountHelper.validateNewEmployee(
          name: 'Budi',
          email: 'budi@depot.com',
          password: '123',
        ),
        isNotNull,
      );
      expect(
        EmployeeAccountHelper.validateNewEmployee(
          name: 'Budi',
          email: 'budi@depot.com',
          password: 'password123',
        ),
        isNull,
      );
    });

    test('parses valid active employee account link pointing to boss storeId', () {
      final link = EmployeeAccountLink.fromMap('emp_uid_99', {
        'name': 'Budi Santoso',
        'email': 'budi@depot.com',
        'storeId': 'boss_uid_123',
        'employeeDocId': 'doc_abc',
        'storeName': 'Depot Kayu Esa',
        'isActive': true,
      });

      expect(link, isNotNull);
      expect(link!.authUid, 'emp_uid_99');
      expect(link.storeId, 'boss_uid_123');
      expect(link.name, 'Budi Santoso');
      expect(link.email, 'budi@depot.com');
      expect(link.employeeDocId, 'doc_abc');
      expect(link.isActive, isTrue);
    });

    test('marks disabled employee account as inactive and rejects missing storeId', () {
      final disabled = EmployeeAccountLink.fromMap('emp_uid_99', {
        'name': 'Budi',
        'email': 'budi@depot.com',
        'storeId': 'boss_uid_123',
        'isActive': false,
      });
      expect(disabled, isNotNull);
      expect(disabled!.isActive, isFalse);

      final malformed = EmployeeAccountLink.fromMap('emp_uid_99', {
        'name': 'Budi',
        'storeId': '',
        'isActive': true,
      });
      expect(malformed, isNull);
    });

    test('maps Firebase Auth error codes to clear Indonesian messages', () {
      expect(
        EmployeeAccountHelper.mapAuthErrorCode('email-already-in-use'),
        contains('sudah terdaftar'),
      );
      expect(
        EmployeeAccountHelper.mapAuthErrorCode('weak-password'),
        contains('6 karakter'),
      );
      expect(
        EmployeeAccountHelper.mapAuthErrorCode('invalid-credential'),
        contains('salah'),
      );
      expect(
        EmployeeAccountHelper.mapAuthErrorCode('operation-not-allowed'),
        contains('Firebase Console'),
      );
    });
  });
}
