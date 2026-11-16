import 'package:bibliolife/features/reader/domain/models/reader_settings.dart';
import 'package:bibliolife/features/reader/presentation/models/local_reader_settings_adapters.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_reader_settings_repository.dart';

void main() {
  test('PDF preview restore and commit do not persist slider ticks', () async {
    final repository = FakeReaderSettingsRepository();
    final adapter = PdfReaderSettingsAdapter(repository);
    await adapter.initialize();
    final original = adapter.state;
    final changed = original.copyWith(
      spacing: original.spacing!.copyWith(pageGap: 24),
    );

    await adapter.previewSettings(changed);
    expect(adapter.state.spacing!.pageGap, 24);
    expect(repository.saveCount, 0);
    await adapter.restoreSettings(original);
    expect(adapter.state, original);
    expect(repository.saveCount, 0);
    await adapter.commitSettings(changed);
    expect(repository.saveCount, 1);
    expect(repository.values[ReaderSettingsProfile.pdf], changed);
    adapter.dispose();
  });

  test(
    'Comic preview applies all visible renderer values without extraction',
    () async {
      final repository = FakeReaderSettingsRepository();
      final adapter = ComicReaderSettingsAdapter(repository);
      final originalIdentity = adapter;
      final changed = adapter.state.copyWith(
        spacing: adapter.state.spacing!.copyWith(pageGap: 30),
        page: adapter.state.page!.copyWith(
          readingMode: ReaderReadingMode.continuous,
          readingDirection: ReaderReadingDirection.rightToLeft,
          imageFit: ReaderImageFit.width,
        ),
      );

      await adapter.previewSettings(changed);
      expect(adapter, same(originalIdentity));
      expect(adapter.state.page!.readingMode, ReaderReadingMode.continuous);
      expect(
        adapter.state.page!.readingDirection,
        ReaderReadingDirection.rightToLeft,
      );
      expect(adapter.state.page!.imageFit, ReaderImageFit.width);
      expect(adapter.state.spacing!.pageGap, 30);
      expect(repository.loadCount, 0);
      expect(repository.saveCount, 0);
      adapter.dispose();
    },
  );

  test('route reopen restores committed global renderer profile', () async {
    final repository = FakeReaderSettingsRepository();
    final first = ComicReaderSettingsAdapter(repository);
    final changed = first.state.copyWith(
      page: first.state.page!.copyWith(imageFit: ReaderImageFit.width),
    );
    await first.commitSettings(changed);
    first.dispose();

    final reopened = ComicReaderSettingsAdapter(repository);
    await reopened.initialize();
    expect(reopened.state, changed);
    reopened.dispose();
  });

  test(
    'partial persisted local profiles are completed from safe defaults',
    () async {
      final repository = FakeReaderSettingsRepository(
        initial: {
          ReaderSettingsProfile.pdf: const ReaderSettingsState(
            profile: ReaderSettingsProfile.pdf,
          ),
          ReaderSettingsProfile.comic: const ReaderSettingsState(
            profile: ReaderSettingsProfile.comic,
            spacing: ReaderSpacingSettings(pageGap: 22),
          ),
        },
      );
      final pdf = PdfReaderSettingsAdapter(repository);
      final comic = ComicReaderSettingsAdapter(repository);

      await pdf.initialize();
      await comic.initialize();

      expect(pdf.state.spacing, ReaderSettingsState.pdfDefaults.spacing);
      expect(comic.state.spacing!.pageGap, 22);
      expect(comic.state.page, ReaderSettingsState.comicDefaults.page);
      pdf.dispose();
      comic.dispose();
    },
  );

  test('failed local Apply restores the previous renderer state', () async {
    final repository = _FailingRepository();
    final adapter = PdfReaderSettingsAdapter(repository);
    final original = adapter.state;
    final changed = original.copyWith(
      spacing: original.spacing!.copyWith(pageGap: 28),
    );

    await expectLater(adapter.commitSettings(changed), throwsStateError);
    expect(adapter.state, original);
    adapter.dispose();
  });
}

class _FailingRepository extends FakeReaderSettingsRepository {
  @override
  Future<void> save(ReaderSettingsState settings) async {
    saveCount++;
    throw StateError('injected_save_failure');
  }
}
