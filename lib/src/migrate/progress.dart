// Public progress values for recoverable migration steps.

import 'backfill.dart' show BackfillProgress;

/// Durable status of one recoverable migration step.
enum MigrationStepState { running, complete, failed }

/// A recorded checkpoint that allows an interrupted migration to resume safely.
final class MigrationProgress {
  /// Identifier of the migration containing this step.
  final String id;

  /// Reviewed migration fingerprint stored with this checkpoint.
  final String checksum;

  /// Zero-based index in the reviewed migration's steps.
  final int step;

  /// Last durable status of this step, distinct from whole-migration completion.
  final MigrationStepState state;

  /// Last recorded execution stage, such as scanning, verification, or recording.
  final String phase;

  /// Recorded ORM error code or exception type name, or null when none is stored.
  final String? failure;

  /// Durable data cursor and counters for a backfill step, when present.
  final BackfillProgress? backfill;

  /// Records a step checkpoint for reporting and recovery inspection.
  const MigrationProgress(
    this.id,
    this.checksum,
    this.step,
    this.state,
    this.phase,
    this.failure, {
    this.backfill,
  });

  /// Structured status for CLI and application reports.
  Map<String, Object?> toJson() => {
    'id': id,
    'checksum': checksum,
    'step': step,
    'state': state.name,
    'phase': phase,
    if (failure != null) 'failure': failure,
    if (backfill != null) 'backfill': backfill!.toJson(),
  };
}
