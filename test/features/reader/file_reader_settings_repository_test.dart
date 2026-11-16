import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bibliolife/features/reader/data/repositories/file_reader_settings_repository.dart';
import 'package:bibliolife/features/reader/domain/models/reader_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'typed renderer profiles persist independently without Drift schema',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'bibliolife-reader-settings-',
      );
      addTearDown(() async => directory.delete(recursive: true));
      final repository = FileReaderSettingsRepository(() async => directory);
      final pdf = ReaderSettingsState.pdfDefaults.copyWith(
        spacing: const ReaderSpacingSettings(pageGap: 26),
      );
      final comic = ReaderSettingsState.comicDefaults.copyWith(
        page: const ReaderPageSettings(imageFit: ReaderImageFit.width),
      );

      await repository.save(pdf);
      await repository.save(comic);

      expect(await repository.load(ReaderSettingsProfile.pdf), pdf);
      expect(await repository.load(ReaderSettingsProfile.comic), comic);
      expect(
        await repository.load(ReaderSettingsProfile.readiumReflowable),
        isNull,
      );
    },
  );

  test(
    'missing corrupt truncated and unsupported files recover safely',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'bibliolife-reader-settings-corrupt-',
      );
      addTearDown(() async => directory.delete(recursive: true));
      final repository = FileReaderSettingsRepository(() async => directory);
      final file = File('${directory.path}/reader-settings-v1.json');

      expect(await repository.load(ReaderSettingsProfile.pdf), isNull);
      for (final invalid in <String>[
        '',
        '{"version":1',
        '[]',
        '{"profiles":{}}',
        '{"version":"one","profiles":{}}',
        '{"version":2,"profiles":{}}',
      ]) {
        await file.writeAsString(invalid, flush: true);
        expect(
          await repository.load(ReaderSettingsProfile.pdf),
          isNull,
          reason: invalid,
        );
      }
    },
  );

  test(
    'unknown fields are tolerated and malformed values are bounded',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'bibliolife-reader-settings-values-',
      );
      addTearDown(() async => directory.delete(recursive: true));
      final file = File('${directory.path}/reader-settings-v1.json');
      await file.writeAsString(
        jsonEncode({
          'version': 1,
          'unknownRoot': true,
          'profiles': {
            'pdf': {
              'profile': 'pdf',
              'unknownProfile': 7,
              'spacing': {'pageGap': -999999, 'unknownSpacing': 'safe'},
            },
          },
        }),
        flush: true,
      );
      final repository = FileReaderSettingsRepository(() async => directory);

      final loaded = await repository.load(ReaderSettingsProfile.pdf);
      expect(loaded, isNotNull);
      expect(loaded!.spacing!.pageGap, 0);
    },
  );

  test('Readium sidecar stores only fields not owned by Drift', () async {
    final directory = await Directory.systemTemp.createTemp(
      'bibliolife-reader-settings-ownership-',
    );
    addTearDown(() async => directory.delete(recursive: true));
    final repository = FileReaderSettingsRepository(() async => directory);
    final value = ReaderSettingsState.readiumDefaults.copyWith(
      appearance: const ReaderAppearanceSettings(theme: ReaderTheme.sepia),
      typography: const ReaderTypographySettings(
        fontFamily: ReaderFontFamily.monospace,
        fontSize: 1.8,
        fontWeight: 1.4,
      ),
      spacing: const ReaderSpacingSettings(lineHeight: 2, textMargins: 3),
      textLayout: const ReaderTextLayoutSettings(
        alignment: ReaderTextAlignment.justify,
        readingMode: ReaderReadingMode.continuous,
        columns: ReaderColumnCount.two,
      ),
      sourceSpecific: const ReaderSourceSpecificSettings(
        publisherStyles: false,
      ),
    );

    await repository.save(value);
    final root =
        jsonDecode(
              await File(
                '${directory.path}/reader-settings-v1.json',
              ).readAsString(),
            )
            as Map<String, Object?>;
    final profiles = root['profiles']! as Map<String, Object?>;
    final readium = profiles['readiumReflowable']! as Map<String, Object?>;
    final typography = readium['typography']! as Map<String, Object?>;

    expect(readium, isNot(contains('appearance')));
    expect(readium, isNot(contains('spacing')));
    expect(readium, isNot(contains('sourceSpecific')));
    expect(typography, isNot(contains('fontSize')));
    expect(typography['fontFamily'], 'monospace');
    expect(typography['fontWeight'], 1.4);
    expect(readium['textLayout'], isNotNull);
  });

  test('concurrent writes are serialized and newest state wins', () async {
    final directory = await Directory.systemTemp.createTemp(
      'bibliolife-reader-settings-concurrent-',
    );
    addTearDown(() async => directory.delete(recursive: true));
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    var replacements = 0;
    final repository = FileReaderSettingsRepository(
      () async => directory,
      replaceFile: (temporary, destination) async {
        replacements++;
        if (replacements == 1) {
          firstStarted.complete();
          await releaseFirst.future;
        }
        if (await destination.exists()) await destination.delete();
        await temporary.rename(destination.path);
      },
    );
    final first = ReaderSettingsState.pdfDefaults.copyWith(
      spacing: const ReaderSpacingSettings(pageGap: 12),
    );
    final newest = ReaderSettingsState.pdfDefaults.copyWith(
      spacing: const ReaderSpacingSettings(pageGap: 34),
    );

    final writeFirst = repository.save(first);
    await firstStarted.future;
    final writeNewest = repository.save(newest);
    releaseFirst.complete();
    await Future.wait([writeFirst, writeNewest]);

    expect(await repository.load(ReaderSettingsProfile.pdf), newest);
  });

  test('failed replacement preserves the last valid settings file', () async {
    final directory = await Directory.systemTemp.createTemp(
      'bibliolife-reader-settings-failure-',
    );
    addTearDown(() async => directory.delete(recursive: true));
    final stable = FileReaderSettingsRepository(() async => directory);
    final original = ReaderSettingsState.pdfDefaults.copyWith(
      spacing: const ReaderSpacingSettings(pageGap: 14),
    );
    await stable.save(original);
    final failing = FileReaderSettingsRepository(
      () async => directory,
      replaceFile: (_, _) async => throw FileSystemException('injected'),
    );

    await expectLater(
      failing.save(
        ReaderSettingsState.pdfDefaults.copyWith(
          spacing: const ReaderSpacingSettings(pageGap: 35),
        ),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await stable.load(ReaderSettingsProfile.pdf), original);
  });

  test(
    'a future schema is never overwritten by this older repository',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'bibliolife-reader-settings-future-',
      );
      addTearDown(() async => directory.delete(recursive: true));
      final file = File('${directory.path}/reader-settings-v1.json');
      const futurePayload = '{"version":2,"profiles":{"future":true}}';
      await file.writeAsString(futurePayload, flush: true);
      final repository = FileReaderSettingsRepository(() async => directory);

      await expectLater(
        repository.save(ReaderSettingsState.pdfDefaults),
        throwsUnsupportedError,
      );
      expect(await file.readAsString(), futurePayload);
    },
  );

  test(
    'an interrupted replace recovers the previous backup on next access',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'bibliolife-reader-settings-recovery-',
      );
      addTearDown(() async => directory.delete(recursive: true));
      final repository = FileReaderSettingsRepository(() async => directory);
      final original = ReaderSettingsState.comicDefaults.copyWith(
        spacing: const ReaderSpacingSettings(pageGap: 18),
      );
      await repository.save(original);
      final file = File('${directory.path}/reader-settings-v1.json');
      await file.rename('${file.path}.bak');

      expect(await repository.load(ReaderSettingsProfile.comic), original);
      expect(await file.exists(), isTrue);
      expect(await File('${file.path}.bak').exists(), isFalse);
    },
  );
}
