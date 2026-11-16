import 'dart:io';

import 'package:bibliolife/features/catalog_sources/data/foreground_remote_book_downloader.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_book_download.dart';
import 'package:bibliolife/features/connectivity/application/network_access_policy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

final remoteEpubDownloadTransportProvider =
    Provider<RemoteEpubDownloadTransport>(
      (ref) => IoRemoteEpubDownloadTransport(),
    );

final remoteDownloadTemporaryDirectoryProvider =
    Provider<Future<Directory> Function()>((ref) => getTemporaryDirectory);

final remoteBookDownloaderProvider = Provider<RemoteBookDownloader>(
  (ref) => ForegroundRemoteBookDownloader(
    ref.watch(networkAccessPolicyProvider),
    ref.watch(remoteEpubDownloadTransportProvider),
    ref.watch(remoteDownloadTemporaryDirectoryProvider),
  ),
);
