part of './command_it.dart';

/// Provides bidirectional communication for commands with progress tracking,
/// status messages, and cooperative cancellation.
///
/// ProgressHandle enables:
/// - **Progress tracking**: Report operation progress (0.0-1.0)
/// - **Status messages**: Provide human-readable operation status
/// - **Cooperative cancellation**: Allow external cancellation requests
///
/// All properties are observable via [ValueListenable] for reactive UI updates.
///
/// Example:
/// ```dart
/// final uploadCommand = Command.createAsyncWithProgress<File, String>(
///   (file, handle) async {
///     for (int i = 0; i <= 100; i += 10) {
///       if (handle.isCanceled.value) return 'Canceled';
///
///       await uploadChunk(file, i);
///       handle.updateProgress(i / 100.0);
///       handle.updateStatusMessage('Uploading: $i%');
///     }
///     return 'Complete';
///   },
///   initialValue: '',
/// );
/// ```
class ProgressHandle {
  final CustomValueNotifier<double> _progress = CustomValueNotifier(0.0);
  final CustomValueNotifier<String?> _statusMessage = CustomValueNotifier(null);
  final CustomValueNotifier<bool> _isCanceled = CustomValueNotifier(false);

  /// Observable progress value between 0.0 (0%) and 1.0 (100%).
  ///
  /// Updated by calling [updateProgress]. UI can observe this to show
  /// progress bars or percentage indicators.
  ValueListenable<double> get progress => _progress;

  /// Observable status message providing human-readable operation status.
  ///
  /// Updated by calling [updateStatusMessage]. Can be null when no status
  /// is available. UI can observe this to show operation details to users.
  ValueListenable<String?> get statusMessage => _statusMessage;

  /// Observable cancellation flag.
  ///
  /// Set to true when [cancel] is called. The wrapped command function
  /// should check `isCanceled.value` periodically and handle cancellation
  /// cooperatively (e.g., return early, throw exception, clean up resources).
  ///
  /// Can also be observed via `.listen()` to forward cancellation to external
  /// tokens (e.g., Dio's CancelToken).
  ValueListenable<bool> get isCanceled => _isCanceled;

  /// Updates the progress value.
  ///
  /// [value] must be between 0.0 and 1.0 (inclusive).
  /// Notifies observers of [progress].
  ///
  /// Throws [AssertionError] in debug mode if value is out of range.
  void updateProgress(double value) {
    assert(
      value >= 0.0 && value <= 1.0,
      'Progress must be between 0.0 and 1.0, but was $value',
    );
    _progress.value = value;
  }

  /// Updates the status message.
  ///
  /// Pass null to clear the status message.
  /// Notifies observers of [statusMessage].
  void updateStatusMessage(String? message) {
    _statusMessage.value = message;
  }

  /// Requests cooperative cancellation of the operation.
  ///
  /// Sets the [isCanceled] flag to true. The wrapped command function
  /// is responsible for checking this flag and responding appropriately.
  ///
  /// This does NOT forcibly stop execution - cancellation is cooperative.
  /// The function must check `isCanceled.value` and decide how to handle it.
  void cancel() {
    _isCanceled.value = true;
  }

  /// Disposes all internal notifiers.
  ///
  /// Called automatically when the owning Command is disposed.
  void dispose() {
    _progress.dispose();
    _statusMessage.dispose();
    _isCanceled.dispose();
  }
}
