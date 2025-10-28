//===----------------------------------------------------------------------===//
//
// This source file is part of the MQTTNIO project
//
// Copyright (c) 2020-2021 Adam Fowler
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

extension MQTTChannelHandler {
    @usableFromInline
    struct StateMachine<Context>: ~Copyable {
        @usableFromInline
        enum State: ~Copyable {
            case uninitialised
            case connected(ConnectedState)
            case disconnected

            @usableFromInline
            var description: String {
                borrowing get {
                    switch self {
                    case .uninitialised: "uninitialised"
                    case .connected: "connected"
                    case .disconnected: "disconnected"
                    }
                }
            }
        }
        @usableFromInline
        var state: State

        @usableFromInline
        struct ConnectedState {
            let context: Context
            var tasks: [MQTTTask]
        }

        init() {
            self.state = .uninitialised
        }

        private init(_ state: consuming State) {
            self.state = state
        }

        /// handler has become active
        @usableFromInline
        mutating func setConnected(context: Context) {
            switch consume self.state {
            case .uninitialised:
                self = .connected(.init(context: context, tasks: []))
            case .connected:
                preconditionFailure("Cannot set connected state when state is connected")
            case .disconnected:
                preconditionFailure("Cannot set connected state when state is disconnected")
            }
        }

        @usableFromInline
        enum SendPacketAction {
            case sendPacket(Context)
            case throwError(any Error)
        }

        /// handler wants to send a packet
        @usableFromInline
        mutating func sendPacket(_ task: MQTTTask) -> SendPacketAction {
            switch consume self.state {
            case .uninitialised:
                preconditionFailure("Cannot send packet when uninitialised")
            case .connected(var state):
                state.tasks.append(task)
                self = .connected(state)
                return .sendPacket(state.context)
            case .disconnected:
                self = .disconnected
                return .throwError(MQTTError.noConnection)
            }
        }

        @usableFromInline
        enum ReceivedPacketAction {
            /// .PUBLISH
            case respondAndReturn
            /// .CONNACK, .PUBACK, .PUBREC, .PUBCOMP, .SUBACK, .UNSUBACK, .PINGRESP, .AUTH
            /// .PUBREL
            case ignore(MQTTTask)
            /// checkInbound threw error
            case fail(MQTTTask, any Error)
            /// process packets where no equivalent task was found
            case unhandled
            /// .DISCONNECT
            /// .CONNECT, .SUBSCRIBE, .UNSUBSCRIBE, .PINGREQ
            case closeConnection(any Error)
        }

        /// handler has received a packet
        @usableFromInline
        mutating func receivedPacket(_ packet: MQTTPacket) -> ReceivedPacketAction {
            switch consume self.state {
            case .uninitialised:
                preconditionFailure("Cannot receive packet when uninitialised")
            case .connected(var state):
                switch packet.type {
                case .PUBLISH:
                    self = .connected(state)
                    return .respondAndReturn
                case .CONNACK, .PUBACK, .PUBREC, .PUBCOMP, .SUBACK, .UNSUBACK, .PINGRESP, .AUTH, .PUBREL:
                    for task in state.tasks {
                        do {
                            // should this task respond to inbound packet
                            if try task.checkInbound(packet) {
                                state.tasks.removeAll { $0 === task }
                                self = .connected(state)
                                return .ignore(task)
                            }
                        } catch {
                            state.tasks.removeAll { $0 === task }
                            self = .connected(state)
                            return .fail(task, error)
                        }    
                    }
                    self = .connected(state)
                    return .unhandled
                case .DISCONNECT:
                    let disconnectMessage = packet as! MQTTDisconnectPacket
                    let ack = MQTTAckV5(reason: disconnectMessage.reason, properties: disconnectMessage.properties)
                    self = .connected(state)
                    return .closeConnection(MQTTError.serverDisconnection(ack))
                case .CONNECT, .SUBSCRIBE, .UNSUBSCRIBE, .PINGREQ:
                    self = .connected(state)
                    return .closeConnection(MQTTError.unexpectedMessage)
                }
            case .disconnected:
                preconditionFailure("Cannot receive packet when disconnected")
            }
        }

        @usableFromInline
        enum CloseAction {
            case failTasksAndClose([MQTTTask])
            case doNothing
        }
        /// Want to close the connection
        @usableFromInline
        mutating func close() -> CloseAction {
            switch consume self.state {
            case .uninitialised:
                self = .disconnected
                return .doNothing
            case .connected(let state):
                self = .disconnected
                return .failTasksAndClose(state.tasks)
            case .disconnected:
                self = .disconnected
                return .doNothing
            }
        }

        private static var uninitialised: Self {
            StateMachine(.uninitialised)
        }

        private static func connected(_ state: ConnectedState) -> Self {
            StateMachine(.connected(state))
        }

        private static var disconnected: Self {
            StateMachine(.disconnected)
        }
    }
}
