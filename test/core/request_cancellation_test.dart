import 'package:bibliolife/core/network/request_cancellation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cancellation is idempotent and listeners run once', () {
    final source = CancellationTokenSource();
    final reasons = <RequestCancellationReason>[];
    source.token.addListener(reasons.add);

    expect(source.cancel(RequestCancellationReason.queryReplaced), isTrue);
    expect(source.cancel(RequestCancellationReason.screenClosed), isFalse);

    expect(source.token.isCancelled, isTrue);
    expect(source.token.reason, RequestCancellationReason.queryReplaced);
    expect(reasons, [RequestCancellationReason.queryReplaced]);
  });

  test('late listener observes cancellation and removed listener does not', () {
    final source = CancellationTokenSource();
    var removedListenerCalls = 0;
    final remove = source.token.addListener((_) => removedListenerCalls++);
    remove();
    source.cancel(RequestCancellationReason.screenClosed);
    var lateReason = RequestCancellationReason.queryReplaced;
    source.token.addListener((reason) => lateReason = reason);

    expect(removedListenerCalls, 0);
    expect(lateReason, RequestCancellationReason.screenClosed);
  });

  test(
    'parent cancellation reaches children without cancelling siblings first',
    () {
      final parent = CancellationTokenSource();
      final firstChild = CancellationTokenSource(parent: parent.token);
      final secondChild = CancellationTokenSource(parent: parent.token);

      firstChild.cancel(RequestCancellationReason.explicitUserRetry);

      expect(parent.token.isCancelled, isFalse);
      expect(secondChild.token.isCancelled, isFalse);
      parent.cancel(RequestCancellationReason.queryReplaced);

      expect(
        firstChild.token.reason,
        RequestCancellationReason.explicitUserRetry,
      );
      expect(
        secondChild.token.reason,
        RequestCancellationReason.parentCancelled,
      );
    },
  );
}
