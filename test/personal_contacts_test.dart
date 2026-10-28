import 'dart:io';

import 'package:drinphone/app/phone_controller.dart';
import 'package:drinphone/core/contacts/personal_contacts.dart';
import 'package:drinphone/core/security/settings_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_sip_engine.dart';

void main() {
  group('importazione', () {
    test('CSV Outlook: virgole, virgolette, fax escluso', () {
      const csv =
          'First Name,Last Name,Company,E-mail Address,Business Phone,Mobile Phone,Business Fax\r\n'
          'Mario,Rossi,"Rossi, Bianchi & C.",m@x.it,02 555 1234,333 1234567,02 555 9999\r\n'
          'Senza,Numero,,,,,\r\n';
      final list = ContactImport.parse('outlook.csv', csv);
      expect(list.length, 1);
      final m = list.single;
      expect(m.name, 'Mario Rossi');
      expect(m.company, 'Rossi, Bianchi & C.');
      expect(m.email, 'm@x.it');
      expect(m.numbers, [
        ('Ufficio', '02 555 1234'),
        ('Cellulare', '333 1234567'),
      ]);
    });

    test('CSV italiano con punto e virgola', () {
      const csv =
          'Nome;Cognome;Azienda;Cellulare;Telefono casa\n'
          'Anna;Verdi;Studio Verdi;+39 347 000111;06 1234\n';
      final a = ContactImport.parse('rubrica.csv', csv).single;
      expect(a.name, 'Anna Verdi');
      expect(a.company, 'Studio Verdi');
      expect(a.numbers, [('Cellulare', '+39 347 000111'), ('Casa', '06 1234')]);
    });

    test('CSV Google: le colonne "Type" non sono numeri', () {
      const csv =
          'Name,Phone 1 - Type,Phone 1 - Value\n'
          'Luca Neri,Mobile,320 9998887\n';
      final l = ContactImport.parse('google.csv', csv).single;
      expect(l.name, 'Luca Neri');
      expect(l.numbers.single.$2, '320 9998887');
    });

    test('vCard: righe piegate, FN, ORG, TEL per tipo, fax e senza numero esclusi', () {
      const vcf =
          'BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Giulia Bianchi\r\n'
          'N:Bianchi;Giulia;;;\r\nORG:Acme\\, S.p.A.;Vendite\r\n'
          'TEL;TYPE=CELL:+39 333 11\r\n 22 333\r\n'
          'TEL;TYPE=WORK,VOICE:02 1111\r\nTEL;TYPE=FAX:02 2222\r\n'
          'EMAIL;TYPE=INTERNET:g@acme.it\r\nEND:VCARD\r\n'
          'BEGIN:VCARD\r\nVERSION:2.1\r\nN:Solo;Nome\r\nEND:VCARD\r\n'
          'BEGIN:VCARD\r\nVERSION:2.1\r\nN:Esposito;Ciro\r\nTEL;HOME:081 55\r\nEND:VCARD\r\n';
      final list = ContactImport.parse('export.vcf', vcf);
      expect(list.map((c) => c.name), ['Giulia Bianchi', 'Ciro Esposito']);
      final g = list.first;
      expect(g.company, 'Acme, S.p.A.');
      expect(g.email, 'g@acme.it');
      expect(g.numbers, [
        ('Cellulare', '+39 333 1122 333'),
        ('Ufficio', '02 1111'),
      ]);
      expect(list.last.numbers, [('Casa', '081 55')]);
    });
  });

  test(
    'contatti personali: salvati per profilo, nome chiamante, doppioni',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final tmp = await Directory.systemTemp.createTemp('drinphone_pc');
      final sep = Platform.pathSeparator;
      final settings = SettingsStore('${tmp.path}${sep}s.json');
      await settings.save(const Settings());
      PersonalContactsStore storeFor(String id) =>
          PersonalContactsStore('${tmp.path}${sep}contacts-$id.json');
      final phone = PhoneController(
        FakeSipEngine(),
        settings,
        engineDataDir: tmp.path,
        logDir: tmp.path,
        personalStoreFor: storeFor,
      );
      await phone.init();
      await phone.savePersonal(
        const PersonalContact(
          id: 'a',
          name: 'Mario Rossi',
          numbers: [('Cellulare', '+39 333 1234567')],
        ),
      );
      expect((await storeFor('default').load()).single.name, 'Mario Rossi');
      expect(phone.nameFor('3331234567'), 'Mario Rossi');
      expect(phone.search('rossi').single.number, '+39 333 1234567');
      final rows = phone.contactsMatching('');
      expect(rows.single.$3?.id, 'a');
      expect(rows.single.$2.phonebooks, [PhoneController.personalBook]);

      final added = await phone.importPersonal([
        const PersonalContact(
          id: 'b',
          name: 'Doppio',
          numbers: [('Altro', '0039 333 123 4567')],
        ),
        const PersonalContact(
          id: 'c',
          name: 'Nuovo',
          numbers: [('Altro', '06 5555')],
        ),
      ]);
      expect(added, 1);
      expect(phone.personal.map((x) => x.name), ['Mario Rossi', 'Nuovo']);

      await phone.deletePersonal('a');
      expect((await storeFor('default').load()).single.name, 'Nuovo');
      await phone.shutdown();
      await tmp.delete(recursive: true);
    },
  );
}
