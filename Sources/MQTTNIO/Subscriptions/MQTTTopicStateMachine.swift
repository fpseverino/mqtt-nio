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

struct MQTTTopicStateMachine<Value: Identifiable> where Value: AnyObject {
    enum State {
        case uninitialized
        case active([Value])
        case closing
        case closed
    }
    var state: State

    init() {
        self.state = .uninitialized
    }

    enum AddAction {
        case doNothing
        case subscribe
    }
    // Add subscription to topic
    mutating func add(subscription: Value) -> AddAction {
        switch state {
        case .uninitialized:
            self.state = .active([subscription])
            return .subscribe
        case .active(var subscriptions):
            subscriptions.append(subscription)
            self.state = .active(subscriptions)
            return .doNothing
        case .closing:
            self.state = .active([subscription])
            return .subscribe
        case .closed:
            preconditionFailure("Closed topics should not be interacted with")
        }
    }

    enum ReceivedMessageAction {
        case forwardMessage([Value])
        case doNothing
    }
    /// We received a message should we pass it on
    func receivedMessage() -> ReceivedMessageAction {
        switch state {
        case .active(let subscriptions):
            return .forwardMessage(subscriptions)
        case .uninitialized, .closing, .closed:
            return .doNothing
        }
    }

    enum CloseAction {
        case doNothing
        case unsubscribe
    }
    /// Subscription is being removed from Topic
    mutating func close(subscription: Value) -> CloseAction {
        switch self.state {
        case .uninitialized:
            self.state = .closing
            return .doNothing
        case .active(var subscriptions):
            if subscriptions.count == 1 {
                precondition(subscriptions[0].id == subscription.id, "Cannot be closing a subscription without adding it")
                self.state = .closing
                return .unsubscribe
            } else {
                guard let index = subscriptions.firstIndex(where: { $0.id == subscription.id }) else {
                    preconditionFailure("Cannot have added a subscription without adding it")
                }
                subscriptions.remove(at: index)
                self.state = .active(subscriptions)
                return .doNothing
            }
        case .closing, .closed:
            preconditionFailure("Removing a subscription from a closing topic is not allowed")
        }
    }
}
