import Combine
import Dispatch

/// Wait for a specified amout of time. If no new value has been received in that timeframe publish the value, otherwise discard it.
/// This prevents flickering if one value gets published just to be updated a few milliseconds later
struct DelayedLatest<Upstream: Publisher>: Publisher {
  class DelayedLatestSubscription<SubscriberType: Subscriber>: Subscription where SubscriberType.Input == Upstream.Output, SubscriberType.Failure == Upstream.Failure {
    private var subscriber: SubscriberType?
    private var cancellable: AnyCancellable?
    private var latestValueId = 0
    
    init(upstream: Upstream, subscriber: SubscriberType, queue: DispatchQueue, waitTime: DispatchTimeInterval) {
      self.subscriber = subscriber
      cancellable = upstream.sink(receiveCompletion: { [unowned self] in
        self.subscriber?.receive(completion: $0)
      }, receiveValue: { [unowned self] (value) in
        self.latestValueId += 1
        let thisValueId = self.latestValueId
        queue.asyncAfter(deadline: .now() + waitTime) {
          if thisValueId == self.latestValueId {
            _ = self.subscriber?.receive(value)
          }
        }
      })
    }
    
    func request(_ demand: Subscribers.Demand) {}

    func cancel() {
      self.subscriber = nil
    }
  }

  typealias Output = Upstream.Output
  typealias Failure = Upstream.Failure
  
  /// The publisher that provides the values
  private let upstream: Upstream
  
  /// The time to wait for new values
  private let waitTime: DispatchTimeInterval
  
  /// The queue on which the delayed value should be published
  private let queue: DispatchQueue
  
  init(upstream: Upstream, wait: DispatchTimeInterval, queue: DispatchQueue) {
    self.upstream = upstream
    self.waitTime = wait
    self.queue = queue
  }

  func receive<S>(subscriber: S) where S : Subscriber, Self.Failure == S.Failure, Self.Output == S.Input {
    subscriber.receive(subscription: DelayedLatestSubscription(upstream: upstream, subscriber: subscriber, queue: queue, waitTime: waitTime))
  }
}
