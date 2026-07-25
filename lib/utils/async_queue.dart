/// A sequential task queue that ensures async operations execute one at a time
/// in FIFO order, with each operation awaiting the previous one.
///
/// Unlike chaining futures with `.then()`, this correctly serializes concurrent
/// enqueue calls without interleaving or race conditions.
class AsyncQueue {
  Future<void> _previous = Future<void>.value();

  /// Enqueues [task] to run after all previously enqueued tasks have completed.
  Future<T> enqueue<T>(Future<T> Function() task) async {
    final completer = Completer<T>();
    _previous = _previous.then((_) async {
      try {
        completer.complete(await task());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }
}
