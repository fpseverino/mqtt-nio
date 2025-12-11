//===----------------------------------------------------------------------===//
//
// This source file is part of the MQTTNIO project
//
// Copyright (c) 2020-2025 Adam Fowler
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Logging
import Synchronization

struct MQTTSubscriptions {
    var subscriptionIDMap: [Int: SubscriptionRef]
    private var subscriptionMap: [String: MQTTTopicStateMachine<SubscriptionRef>]
    let logger: Logger

    static let globalSubscriptionID = Atomic<Int>(0)

    init(logger: Logger) {
        self.subscriptionIDMap = [:]
        self.logger = logger
        self.subscriptionMap = [:]
    }

    /// We received a message
    mutating func notify(_ message: MQTTPublishInfo) {
        self.logger.trace("Received PUBLISH packet", metadata: ["subscription": "\(message.topicName)"])

        switch self.subscriptionMap[message.topicName]?.receivedMessage() {
        case .forwardMessage(let subscriptions):
            for subscription in subscriptions {
                subscription.sendMessage(message)
            }
        case .doNothing, .none:
            self.logger.trace("Received message for inactive subscription", metadata: ["subscription": "\(message.topicName)"])
        }
    }

    /// Connection is closing, let's inform all the subscriptions
    mutating func close(error: any Error) {
        for subscription in subscriptionIDMap.values {
            subscription.sendError(error)
        }
        self.subscriptionIDMap = [:]
        self.subscriptionMap = [:]
    }

    static func getSubscriptionID() -> Int {
        Self.globalSubscriptionID.wrappingAdd(1, ordering: .relaxed).newValue
    }

    enum SubscribeAction {
        case doNothing(Int)
        case subscribe(SubscriptionRef, String)
    }

    /// Add subscription to topic.
    mutating func addSubscription(
        continuation: MQTTSubscription.Continuation,
        filters: [MQTTSubscribeInfoV5]
    ) -> SubscribeAction {
        let id = Self.getSubscriptionID()
        let subscription = SubscriptionRef(
            id: id,
            continuation: continuation,
            filters: filters,
            logger: self.logger
        )
        subscriptionIDMap[id] = subscription
        var action = SubscribeAction.doNothing(id)
        for info in filters {
            switch subscriptionMap[info.topicFilter, default: .init()].add(subscription: subscription) {
            case .subscribe:
                action = .subscribe(subscription, info.topicFilter)
            case .doNothing:
                break
            }
        }
        return action
    }

    enum UnsubscribeAction {
        case doNothing
        case unsubscribe([String])
    }

    /// Add unsubscribe
    ///
    /// Remove subscription from all the message topics.
    /// If a message topic ends up with no subscriptions, then add it to the list of topics to unsubscribe from.
    mutating func unsubscribe(id: Int) -> UnsubscribeAction {
        var action: UnsubscribeAction = .doNothing
        guard let subscription = subscriptionIDMap[id] else { return .doNothing }
        for info in subscription.filters {
            switch self.subscriptionMap[info.topicFilter]?.close(subscription: subscription) {
            case .unsubscribe:
                switch action {
                case .doNothing:
                    action = .unsubscribe([info.topicFilter])
                case .unsubscribe(var topics):
                    topics.append(info.topicFilter)
                    action = .unsubscribe(topics)
                }
            case .doNothing, .none:
                break
            }
        }
        self.subscriptionIDMap[id] = nil
        return action
    }

    /// Remove subscription
    mutating func removeSubscription(id: Int) {
        guard let subscription = subscriptionIDMap[id] else { return }
        for info in subscription.filters {
            switch self.subscriptionMap[info.topicFilter]?.close(subscription: subscription) {
            case .doNothing, .none:
                break
            case .unsubscribe:
                self.subscriptionMap[info.topicFilter] = nil
            }
        }
        subscriptionIDMap[id] = nil
    }
}

/// Individual subscription associated with one subscribe
final class SubscriptionRef: Identifiable {
    let id: Int
    let filters: [MQTTSubscribeInfoV5]
    let continuation: MQTTSubscription.Continuation
    let logger: Logger

    init(id: Int, continuation: MQTTSubscription.Continuation, filters: [MQTTSubscribeInfoV5], logger: Logger) {
        self.id = id
        self.filters = filters
        self.continuation = continuation
        self.logger = logger
    }

    func sendMessage(_ message: MQTTPublishInfo) {
        self.continuation.yield(message)
    }

    func sendError(_ error: any Error) {
        self.continuation.finish(throwing: error)
    }

    func finish() {
        self.continuation.finish()
    }
}
