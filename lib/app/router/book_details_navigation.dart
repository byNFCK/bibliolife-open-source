import 'package:bibliolife/app/router/app_routes.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

void openBookDetailsForPublication(
  BuildContext context, {
  required String sourceId,
  required Object remoteDetailsRequest,
  String? importedBookId,
}) {
  final localBookId = importedBookId;
  if (localBookId != null) {
    context.pushNamed(
      AppRoutes.bookDetailsName,
      pathParameters: {'bookId': localBookId},
    );
    return;
  }
  context.pushNamed(
    AppRoutes.publicationOnlineLibraryName,
    pathParameters: {'sourceId': sourceId},
    extra: remoteDetailsRequest,
  );
}

void replaceWithCanonicalLocalBookDetails(
  BuildContext context,
  String bookId,
) => context.replaceNamed(
  AppRoutes.bookDetailsName,
  pathParameters: {'bookId': bookId},
);
