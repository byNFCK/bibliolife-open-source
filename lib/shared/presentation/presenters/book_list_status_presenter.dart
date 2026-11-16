import 'package:bibliolife/app/localization/app_strings.dart';
import 'package:bibliolife/core/utils/date_time_formatter.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_access_hint.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_acquisition.dart';
import 'package:bibliolife/shared/models/library_book.dart';

/// Read-only presentation of existing state. Never fetches or infers history.
abstract final class BookListStatusPresenter {
  static String local(LibraryBook book, {DateTime? now}) {
    final current = (now ?? DateTime.now()).toLocal();
    final opened = book.lastOpenedAt?.toLocal();
    if (opened == null || opened.isAfter(current)) {
      return AppStrings.readyToRead;
    }
    final days = DateTime.utc(
      current.year,
      current.month,
      current.day,
    ).difference(DateTime.utc(opened.year, opened.month, opened.day)).inDays;
    if (days == 1) return AppStrings.openedYesterday;
    if (days > 1 && days < 31) return AppStrings.openedDaysAgo(days);
    if (days >= 31) {
      return AppStrings.openedOn(DateTimeFormatter.shortDateLabel(opened));
    }
    final age = current.difference(opened);
    if (age.inHours > 0) return AppStrings.openedHoursAgo(age.inHours);
    if (age.inMinutes > 0) return AppStrings.openedMinutesAgo(age.inMinutes);
    return AppStrings.openedJustNow;
  }

  static String? remote(RemoteCatalogPublicationSummary publication) {
    final metadata = publication.accessMetadata;
    bool usable(Uri? uri) => uri?.scheme == 'https' && uri!.host.isNotEmpty;
    final freeHint = publication.accessHints.any(
      (hint) =>
          (hint.type == RemoteCatalogAccessType.directDownload ||
              hint.type == RemoteCatalogAccessType.externalRead) &&
          hint.isFullBook &&
          !hint.requiresAuthentication &&
          usable(hint.uri),
    );
    final openAccess = publication.acquisitions.any(
      (link) =>
          link.kind == RemoteAcquisitionKind.openAccess &&
          !link.isMalformed &&
          link.isSecure &&
          !link.requiresAuthentication &&
          usable(Uri.tryParse(link.href)),
    );
    final unavailable = publication.accessHints.any(
      (hint) => hint.type == RemoteCatalogAccessType.unavailable,
    );
    final otherAccess = publication.accessHints.any(
      (hint) =>
          hint.type != RemoteCatalogAccessType.unavailable && usable(hint.uri),
    );
    if (unavailable && !otherAccess && !freeHint && !openAccess) {
      return AppStrings.bookUnavailable;
    }
    if (freeHint || openAccess || metadata['sale.saleability'] == 'FREE') {
      return AppStrings.readForFree;
    }
    // These exact keys are populated from authoritative Google Books saleInfo.
    for (final prefix in ['sale.retailPrice', 'sale.listPrice']) {
      final raw = metadata['$prefix.amount']?.trim();
      final currency = metadata['$prefix.currencyCode']?.trim().toUpperCase();
      final amount = raw == null ? null : num.tryParse(raw);
      if (raw != null &&
          RegExp(r'^\d+(\.\d+)?$').hasMatch(raw) &&
          amount != null &&
          amount.isFinite &&
          amount > 0 &&
          currency != null &&
          RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
        return AppStrings.bookPrice(raw, currency);
      }
    }
    return null;
  }
}
