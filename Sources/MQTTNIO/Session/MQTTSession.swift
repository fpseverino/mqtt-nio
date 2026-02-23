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

public import Logging
import NIOCore
public import Synchronization

/// Represents an MQTT session, holding session state such as inflight messages.
/// Used by ``MQTTConnection`` to manage session state across connections.
public final class MQTTSession: Sendable {
    private let _clientID: Mutex<String>

    /// Whether a ``MQTTConnection`` is currently connected using this session.
    let isConnected: Atomic<Bool>
    @usableFromInline
    let connection: Mutex<MQTTConnection?>

    /// Inflight messages
    let inflightPackets: Mutex<MQTTInflight>

    let subscriptions: Mutex<MQTTSubscriptions>

    /// Initialize a new ``MQTTSession`` with a unique client identifier.
    ///
    /// If you provide an empty string as the Client Identifier,
    /// the MQTT server should generate a unique Client Identifier for you on the first connection with this session.
    ///
    /// If that first connection was a MQTT v5 connection,
    /// you can retrieve the assigned Client Identifier from ``MQTTSession/clientID`` after the connection is established.
    /// If you reuse the same session for other connections,
    /// the following connections will use the new Client Identifier assigned by the server.
    ///
    /// - Parameters:
    ///   - clientID: Client identifier to use for this session. This must be unique.
    ///   - logger: Logger to use for this session.
    public init(clientID: String, logger: Logger) {
        self._clientID = .init(clientID)
        self.inflightPackets = .init(.init())
        self.subscriptions = .init(.init(logger: logger))
        self.isConnected = .init(false)
        self.connection = .init(nil)
    }
}

// MARK: - Client ID

extension MQTTSession {
    /// Client Identifier for this session.
    ///
    /// If you provided an empty string as the Client Identifier when initializing this session,
    /// the MQTT server should have generated a unique Client Identifier for you on the first connection with this session.
    /// If that first connection was a MQTT v5 connection,
    /// this property will contain the assigned Client Identifier.
    public var clientID: String {
        self._clientID.withLock { $0 }
    }

    func setClientID(_ clientID: String) {
        self._clientID.withLock { $0 = clientID }
    }
}

// MARK: - Inflight Messages

extension MQTTSession {
    /// Used for testing
    package var inflightPacketsCount: Int {
        self.inflightPackets.withLock { $0.packets.count }
    }
}
