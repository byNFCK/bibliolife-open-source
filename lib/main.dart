// SPDX-License-Identifier: GPL-3.0-only
  import 'package:bibliolife/app/app.dart';
import 'package:bibliolife/core/performance/online_pipeline_performance.dart';
import 'package:bibliolife/core/performance/search_image_cache_policy.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  searchPerformanceHealth(
    'startup',
    fields: {
      'netPerf': biblioLifeNetPerfLogsEnabled,
      'frameMetrics': biblioLifeSearchFrameMetricsEnabled,
      'verbose': biblioLifeNetPerfVerboseLogsEnabled,
      'profile': kProfileMode,
      'debug': kDebugMode,
      'release': kReleaseMode,
    },
  );
  SearchImageCachePolicy.instance.configure();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const ProviderScope(child: App()));
}
