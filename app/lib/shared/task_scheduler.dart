// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:collection';

import 'package:logging/logging.dart';

final Logger _logger = new Logger('pub.scheduler');

/// Interface for task execution.
typedef Future TaskRunner(Task task);

// ignore: one_member_abstracts
abstract class TaskSource {
  /// Returns a stream of currently available tasks at the time of the call.
  Stream<Task> startStreaming();
}

/// Tasks coming from through the isolate's receivePort, originating from a
/// HTTP handler that received a ping after a new upload.
class ManualTriggerTaskSource implements TaskSource {
  final Stream _taskReceivePort;
  ManualTriggerTaskSource(this._taskReceivePort);

  @override
  Stream<Task> startStreaming() => _taskReceivePort;
}

/// Schedules and executes package analysis.
class TaskScheduler {
  final TaskRunner taskRunner;
  final List<TaskSource> sources;

  TaskScheduler(this.taskRunner, this.sources);

  Future run() async {
    final StreamIterator<Task> taskIterator = new PrioritizedStreamIterator(
        sources.map((TaskSource ts) => ts.startStreaming()).toList());
    while (await taskIterator.moveNext()) {
      final Task task = taskIterator.current;
      try {
        await taskRunner(task);
      } catch (e, st) {
        _logger.severe('Error processing task: $task', e, st);
      }
    }
  }
}

/// A task for a given package and version.
class Task {
  final String package;
  final String version;

  Task(this.package, this.version);

  @override
  String toString() => '$package $version';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Task &&
          runtimeType == other.runtimeType &&
          version == other.version;

  @override
  int get hashCode => version.hashCode;
}

/// A pull-based interface for accessing events from multiple streams, in the
/// priority order of the streams provided.
class PrioritizedStreamIterator<T> implements StreamIterator<T> {
  List<Queue<T>> _priorityQueues;
  List<StreamSubscription> _subscriptions;
  bool _hasMoved = false;
  bool _isClosed = false;
  T _current;
  Completer<bool> _hasNextCompleter;

  PrioritizedStreamIterator(List<Stream<T>> sources) {
    _priorityQueues = new List.generate(sources.length, (_) => new Queue());
    _subscriptions = new List(sources.length);

    // Listen on the streams and put items into their own queues.
    for (int i = 0; i < sources.length; i++) {
      final Stream source = sources[i];
      final Queue<T> queue = _priorityQueues[i];
      _subscriptions[i] = source.listen(
        (T item) {
          queue.add(item);
          _triggerComplete();
        },
        onDone: () {
          _subscriptions[i] = null;
          _cancelWhenAllDone();
        },
        cancelOnError: true,
      );
    }
  }

  /// Moves to the next element.
  /// Returns whether the iterator has another item.
  @override
  Future<bool> moveNext() async {
    if (_hasNextCompleter != null) {
      throw new StateError('Another moveNext() is underway.');
    }
    if (_isClosed) return false;
    final Queue<T> queue = _firstQueue();
    if (queue != null) {
      _current = queue.removeFirst();
      _hasMoved = true;
      return true;
    } else {
      _hasNextCompleter ??= new Completer();
      _cancelWhenAllDone();
      return _hasNextCompleter.future;
    }
  }

  // The current element in the iterator.
  @override
  T get current {
    if (_isClosed) throw new StateError('StreamIterator closed.');
    if (!_hasMoved) throw new StateError('moveNext() has not been called.');
    return _current;
  }

  /// Close the source streams and don't accept new requests.
  @override
  Future cancel() async {
    if (_hasNextCompleter != null) {
      _hasNextCompleter.complete(false);
      _hasNextCompleter = null;
    }
    for (int i = 0; i < _subscriptions.length; i++) {
      final StreamSubscription s = _subscriptions[i];
      if (s != null) {
        s.cancel();
        _subscriptions[i] = null;
      }
    }
    _isClosed = true;
  }

  Queue<T> _firstQueue() {
    if (_isClosed) {
      throw new StateError('StreamIterator closed');
    }
    return _priorityQueues.firstWhere((q) => q.isNotEmpty, orElse: () => null);
  }

  void _triggerComplete() {
    if (_hasNextCompleter != null) {
      final Queue<T> queue = _firstQueue();
      _current = queue.removeFirst();
      _hasMoved = true;
      _hasNextCompleter.complete(true);
      _hasNextCompleter = null;
    }
    _cancelWhenAllDone();
  }

  void _cancelWhenAllDone() {
    if (_isClosed) return;
    if (_subscriptions.any((s) => s != null)) return;
    if (_firstQueue() != null) return;
    cancel();
  }
}
