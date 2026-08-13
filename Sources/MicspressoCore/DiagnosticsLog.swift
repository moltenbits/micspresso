import Foundation
import os

/// Unified logging front for the app (subsystem com.moltenbits.micspresso).
///
/// notice/warning/error always land in the persisted system log, so
/// `log show --predicate 'subsystem == "com.moltenbits.micspresso"'` can
/// reconstruct what happened after the fact. debug() messages are promoted
/// to the persisted log only while the user has verbose logging enabled;
/// otherwise they're emitted at debug level (visible to a live
/// `log stream --debug`, never stored).
///
/// Messages are logged with public visibility on purpose — device names and
/// engine states are the diagnostic content. No audio is ever logged; the
/// app never reads any.
public struct DiagnosticsLog {
  private let logger: Logger
  private let isVerbose: () -> Bool

  public init(category: String, isVerbose: @escaping () -> Bool = { false }) {
    self.logger = Logger(subsystem: "com.moltenbits.micspresso", category: category)
    self.isVerbose = isVerbose
  }

  public func notice(_ message: String) {
    logger.notice("\(message, privacy: .public)")
  }

  public func warning(_ message: String) {
    logger.warning("\(message, privacy: .public)")
  }

  public func error(_ message: String) {
    logger.error("\(message, privacy: .public)")
  }

  public func debug(_ message: String) {
    if isVerbose() {
      logger.notice("\(message, privacy: .public)")
    } else {
      logger.debug("\(message, privacy: .public)")
    }
  }
}
