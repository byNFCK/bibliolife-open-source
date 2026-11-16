import 'dart:typed_data';

import 'package:bibliolife/core/network/request_cancellation.dart';
import 'package:bibliolife/features/catalog_sources/data/metadata_parser_executor.dart';
import 'package:bibliolife/features/catalog_sources/data/metadata_parsing_policy.dart';
import 'package:bibliolife/features/catalog_sources/data/metadata_payload_parser_dispatcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'small local and forced background routes return equivalent Google DTOs',
    () async {
      final bytes = Uint8List.fromList(
        '{"totalItems":1,"items":[{"id":"id","volumeInfo":{"title":"Book"}}]}'
            .codeUnits,
      );
      final token = CancellationTokenSource();
      final local = MetadataPayloadParserDispatcher(
        const MetadataParsingPolicy(googleBooksThresholdBytes: 1024),
        MetadataParserExecutor(),
      );
      final background = MetadataPayloadParserDispatcher(
        const MetadataParsingPolicy(googleBooksThresholdBytes: 1),
        MetadataParserExecutor(),
      );
      await MetadataRequestScope.run(
        MetadataRequestContext(
          token: token.token,
          sourceId: 'google',
          priority: MetadataRequestPriority.activeSearch,
        ),
        () async {
          final a = await local.google(
            bytes,
            sourceId: 'google',
            details: false,
          );
          final b = await background.google(
            bytes,
            sourceId: 'google',
            details: false,
          );
          expect(a.books.single.id, b.books.single.id);
          expect(
            a.books.single.volume['title'],
            b.books.single.volume['title'],
          );
        },
      );
    },
  );
}
