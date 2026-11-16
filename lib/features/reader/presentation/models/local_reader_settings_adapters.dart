import 'package:bibliolife/features/reader/domain/models/reader_settings.dart';
import 'package:bibliolife/features/reader/domain/repositories/reader_settings_repository.dart';
import 'package:bibliolife/features/reader/presentation/models/reader_ui_controller.dart';
import 'package:flutter/foundation.dart';

abstract class LocalReaderSettingsAdapter extends ChangeNotifier
    implements ReaderSettingsHost {
  LocalReaderSettingsAdapter({
    required this.settingsCapabilities,
    required ReaderSettingsState defaults,
    required this.repository,
  }) : _defaults = defaults,
       _state = defaults;

  @override
  final ReaderSettingsCapabilities settingsCapabilities;
  final ReaderSettingsRepository repository;
  final ReaderSettingsState _defaults;
  ReaderSettingsState _state;
  @override
  ReaderSettingsState get state => _state;

  Future<void> initialize() async {
    final saved = await repository.load(settingsCapabilities.profile);
    if (saved != null && saved.profile == settingsCapabilities.profile) {
      _state = switch (settingsCapabilities.profile) {
        ReaderSettingsProfile.pdf => ReaderSettingsState(
          profile: ReaderSettingsProfile.pdf,
          spacing: saved.spacing ?? _defaults.spacing,
        ),
        ReaderSettingsProfile.comic => ReaderSettingsState(
          profile: ReaderSettingsProfile.comic,
          spacing: saved.spacing ?? _defaults.spacing,
          page: saved.page ?? _defaults.page,
        ),
        ReaderSettingsProfile.readiumReflowable => saved,
      };
      notifyListeners();
    }
  }

  @override
  Future<void> previewSettings(ReaderSettingsState settings) async {
    _accept(settings);
    _state = settings;
    notifyListeners();
  }

  @override
  Future<void> commitSettings(ReaderSettingsState settings) async {
    _accept(settings);
    final previous = _state;
    _state = settings;
    notifyListeners();
    try {
      await repository.save(settings);
    } on Object {
      _state = previous;
      notifyListeners();
      rethrow;
    }
  }

  @override
  Future<void> restoreSettings(ReaderSettingsState settings) =>
      previewSettings(settings);

  void _accept(ReaderSettingsState settings) {
    if (settings.profile != settingsCapabilities.profile) {
      throw ArgumentError.value(settings.profile, 'settings.profile');
    }
  }
}

class PdfReaderSettingsAdapter extends LocalReaderSettingsAdapter {
  PdfReaderSettingsAdapter(ReaderSettingsRepository repository)
    : super(
        settingsCapabilities: ReaderSettingsCapabilities.pdf,
        defaults: ReaderSettingsState.pdfDefaults,
        repository: repository,
      );
}

/// One adapter is intentionally shared by both CBZ and CBR archive sources.
class ComicReaderSettingsAdapter extends LocalReaderSettingsAdapter {
  ComicReaderSettingsAdapter(ReaderSettingsRepository repository)
    : super(
        settingsCapabilities: ReaderSettingsCapabilities.comic,
        defaults: ReaderSettingsState.comicDefaults,
        repository: repository,
      );
}
