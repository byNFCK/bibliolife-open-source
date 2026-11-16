import 'package:bibliolife/features/collections/domain/models/system_collection.dart';
import 'package:flutter/material.dart';

// Cache by identity and brightness; ordinary collections use the app theme.
final _systemSchemes = <(String, Brightness), ColorScheme>{
  for (final brightness in Brightness.values)
    for (final entry in {
      systemFinishedId: Colors.green,
      systemReadingId: Colors.blue,
      systemToReadId: Colors.orange,
    }.entries)
      (entry.key, brightness): ColorScheme.fromSeed(
        seedColor: entry.value,
        brightness: brightness,
      ),
};

ColorScheme? systemCollectionColorScheme(String id, Brightness brightness) =>
    _systemSchemes[(id, brightness)];

class SystemCollectionTheme extends StatelessWidget {
  const SystemCollectionTheme({
    required this.collectionId,
    required this.child,
    super.key,
  });
  final String collectionId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = systemCollectionColorScheme(collectionId, theme.brightness);
    return scheme == null
        ? child
        : Theme(
            data: theme.copyWith(colorScheme: scheme),
            child: child,
          );
  }
}
