import Foundation

/// EngineScheduling backed by GCD timers on the main queue.
public final class MainQueueScheduler: EngineScheduling {
  private final class GCDTimer: EngineTimer {
    private let source: DispatchSourceTimer

    init(delay: TimeInterval, repeating: TimeInterval?, block: @escaping () -> Void) {
      source = DispatchSource.makeTimerSource(queue: .main)
      if let repeating {
        source.schedule(deadline: .now() + delay, repeating: repeating)
      } else {
        source.schedule(deadline: .now() + delay)
      }
      source.setEventHandler(handler: block)
      source.resume()
    }

    func cancel() {
      source.cancel()
    }

    deinit {
      source.cancel()
    }
  }

  public init() {}

  public func schedule(after seconds: TimeInterval, _ block: @escaping () -> Void) -> EngineTimer {
    var timer: GCDTimer!
    timer = GCDTimer(delay: seconds, repeating: nil) {
      block()
      timer.cancel()
    }
    return timer
  }

  public func scheduleRepeating(
    every seconds: TimeInterval, _ block: @escaping () -> Void
  ) -> EngineTimer {
    GCDTimer(delay: seconds, repeating: seconds, block: block)
  }
}
