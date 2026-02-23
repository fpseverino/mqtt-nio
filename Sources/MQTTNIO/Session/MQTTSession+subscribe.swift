//===----------------------------------------------------------------------===//
//
// This source file is part of the MQTTNIO project
//
// Copyright (c) 2020-2026 Adam Fowler
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

public import Synchronization

extension MQTTSession {
    @inlinable
    public nonisolated func subscribe<Value>(
        to subscriptions: [MQTTSubscribeInfoV5],
        subscribeProperties: MQTTProperties = .init(),
        unsubscribeProperties: MQTTProperties = .init(),
        process: (MQTTSubscription) async throws -> Value
    ) async throws -> Value {
        let (id, stream) = try self.subscribe(to: subscriptions, properties: subscribeProperties)
        let value: Value
        do {
            value = try await process(stream)
            try Task.checkCancellation()
        } catch {
            // call unsubscribe in unstructured Task to avoid it being cancelled
            _ = await Task {
                // TODO: fix this
                if let connection = self.connection.withLock({ $0 }) {
                    try await connection.unsubscribe(id: id, properties: unsubscribeProperties)
                }
            }.result
            throw error
        }
        // call unsubscribe in unstructured Task to avoid it being cancelled
        _ = try await Task {
            // TODO: fix this
            if let connection = self.connection.withLock({ $0 }) {
                try await connection.unsubscribe(id: id, properties: unsubscribeProperties)
            }
        }.value
        return value
    }

    @usableFromInline
    func subscribe(
        to subscriptions: [MQTTSubscribeInfoV5],
        properties: MQTTProperties = .init()
    ) throws -> (UInt32, MQTTSubscription) {
        let (stream, streamContinuation) = MQTTSubscription.makeStream()
        if Task.isCancelled {
            throw MQTTError.cancelledTask
        }
        let subscriptionID = MQTTSubscriptions.getSubscriptionID()
        self.subscriptions.withLock {
            $0.sessionSubscriptionsQueue.append(
                QueuedSessionSubscription(
                    id: subscriptionID,
                    continuation: streamContinuation,
                    subscriptions: subscriptions,
                    properties: properties
                )
            )
        }
        return (subscriptionID, stream)
    }
}
