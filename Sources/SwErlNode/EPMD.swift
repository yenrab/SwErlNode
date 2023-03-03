//
//  EPMD.swift
//  
//
//  Created by Lee Barney on 3/1/23.
//

import Foundation
import Network
import Logging
import SwErl

struct PeerInfo {
    let port:UInt16
    let nodeType:UInt8
    let msgProtocol:UInt8
    let highestVersion:UInt16
    let lowestVersion:UInt16
    let nodeName:String
    let extras:Data
}

func startPeerPortsDictionary() throws{
    _ = try spawn(name: "peerPorts", initialState: Dictionary<String,PeerInfo>()){(pid,state,message)in
        let (peerName,port) = message as! (String,UInt16)
        var updateState = state as! Dictionary<String,UInt16>
        updateState[peerName] = port
        return updateState
    }
}


public enum EPMDRequest{
    static let register_node = "register"
    static let port_please = "port_please"
    static let names = "names"
    //static let dump = "dump"//this is for debugging purposes only, therefore it is not implemented in SwErl at this time.
    static let kill = "kill"
    static let stop = "stop"//this is not used in practice, therefore it is not implemented in SwErl
}
@available(macOS 10.14, *)
public typealias EPMD = (EPMDPort:NWEndpoint.Port,
                  EPMD_Host:NWEndpoint.Host,
                  connection:NWConnection,
                         nodeName:String)

@available(macOS 10.14, *)
func spawnProcessesFor(EPMD:EPMD) throws{
    let (_,host,connection,nodeName) = EPMD
    //this process is used to consume responses that
    //contain no needed data
    
    //
    // register this node, by name, with the EPMD
    //
    _ = try spawn(name:"clear_buffer"){(senderPID,trackerId) in
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _context, isDone, error in
            //this code is here for debugging
            //replace it with logging later
            if let data = data, !data.isEmpty {
                NSLog("\(trackerId): ignoring data for request ")
            }
            if let error = error {
                NSLog("\(trackerId): error \(error)")
                return
            }
            if isDone {
                NSLog("\(trackerId): EOF")//EPMD terminated
                stop(client: EPMD)
                return
            }
        }
    }
    _ = try
    spawn(name:EPMDRequest.register_node){(senderPID,message) in
        
        let protocolData = buildRegistrationMessageUsing(name: nodeName, extras: [])
        let tracker = UUID()
        NSLog("\(tracker): sending register_node request ")
        connection.send(content: protocolData, completion: NWConnection.SendCompletion.contentProcessed { error in
            guard let error = error else{
                NSLog("\(tracker): sent successfully")
                
                "clear_buffer" ! tracker//sending to next process
                
                return
            }
            NSLog("\(tracker): error \(error) send error")
            stop(client:EPMD)
        })
    }
    
    //
    //store the port and node information for a named remote node
    //
    _ = try spawn(name:"store_port"){(senderPID,message) in
        let (trackerID,remoteNodeName) = message as! (UUID,String)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _context, isDone, error in
            //this code is here for debugging
            //replace it with logging later
            if let data = data, !data.isEmpty {
                
                //convert the data to a port number UInt16
                let responseID = data[0]
                NSLog("\(trackerID): response identifier is \(responseID) ?? 119")
                if data.count == 2{//error happened
                    let NPMDError = data[1]
                    NSLog("\(trackerID): NPMD error \(NPMDError) for \(remoteNodeName)")
                    return
                }
                
                let port = data[2...3].toUInt16.toMachineByteOrder
                let nodeType = data[4]
                let msgProtocol = data[5]
                let highestVersion = data[6...7].toUInt16.toMachineByteOrder
                let lowestVersion = data[8...9].toUInt16.toMachineByteOrder
                let nameLength = Int(data[10...11].toUInt16.toMachineByteOrder)
                let nodeName = String(bytes: data[12...12+nameLength], encoding: .utf8)
                let extrasLength = Int(data[12+nameLength+1...12+nameLength+1+2].toUInt16.toMachineByteOrder)
                let extras = data[12+nameLength+1+2+1...12+nameLength+1+2+1+extrasLength]
                NSLog("\(trackerID): peer info converted")
                "peerPorts" ! PeerInfo(port: port,nodeType: nodeType,
                                       msgProtocol:msgProtocol,
                                       highestVersion: highestVersion,
                                       lowestVersion: lowestVersion,
                                       nodeName: nodeName ?? "not_parsable",
                                       extras: extras)
            }
            if let error = error {
                NSLog("\(trackerID): error \(error) for \(remoteNodeName)")
                return
            }
            if isDone {
                NSLog("\(trackerID): EOF")//EPMD terminated
                stop(client: EPMD)
                return
            }
        }
    }
    _ = try
    spawn(name:EPMDRequest.port_please){(senderPID,remoteNodeName) in
        
        let protocolData = buildPortPleaseMessageUsing(nodePid: remoteNodeName as! String)
        let tracker = UUID()
        NSLog("\(tracker): sending port_please request for \(remoteNodeName)")
        connection.send(content: protocolData, completion: NWConnection.SendCompletion.contentProcessed { error in
            guard let error = error else{
                NSLog("\(tracker): sent successfully")
                
                "store_port" ! (tracker,remoteNodeName)//sending to next process
                
                return
            }
            NSLog("\(tracker): send error \(error) for \(remoteNodeName)")
            stop(client:EPMD)
        })
    }
    
    //
    //Get all the registered names
    //
    _ = try spawn(name:"read_names"){(senderPID,message) in
        let (trackerID,recieverPid) = message as! (UUID,Any)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _context, isDone, error in
            
            if let data = data, !data.isEmpty {
                
                //convert the data to a port number UInt16
                let dataPort = data[0...3].toUInt32
                NSLog("\(trackerID): read port is \(dataPort)")
                guard let endPort = NWEndpoint.Port("\(dataPort)") else{
                    NSLog("\(trackerID): error \(dataPort) can not be converted to NWEndpoint")
                    return
                }
                let readConnection = NWConnection(host: host, port: endPort, using: .tcp)
                readConnection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { namesData, _context, namesAreDone, error in
                    if let namesData = namesData{
                        if let usablePid = recieverPid as? UUID{
                            usablePid ! String(data: namesData, encoding: .utf8) as Any
                        }
                        else if let usableName = recieverPid as? String{
                            usableName ! String(data: namesData, encoding: .utf8) as Any
                        }
                        else{
                            NSLog("\(trackerID): recieverPid  \(recieverPid) is must be either a string or a UUID")
                        }
                    }
                    if let error = error {
                        NSLog("\(trackerID): error \(error) reading names")
                        return
                    }
                    if isDone {
                        NSLog("\(trackerID): EOF")//EPMD terminated
                        stop(client: EPMD)
                        return
                    }
                }
                
            }
            if let error = error {
                NSLog("\(trackerID): error \(error) reading names port")
                return
            }
            if isDone {
                NSLog("\(trackerID): EOF")//EPMD terminated
                stop(client: EPMD)
                return
            }
        }
    }
    
    //the reciever pid is the process to which the read names
    //are to be sent as data
    _ = try
    spawn(name:EPMDRequest.names){(senderPID,recieverPid) in
        
        let protocolData = buildNamesMessage()
        let tracker = UUID()
        NSLog("\(tracker): sending names request")
        connection.send(content: protocolData, completion: NWConnection.SendCompletion.contentProcessed { error in
            guard let error = error else{
                NSLog("\(tracker): sent successfully")
                
                "read_names" ! (tracker,recieverPid)//sending to next process
                
                return
            }
            NSLog("\(tracker): send error \(error)")
            stop(client:EPMD)
        })
    }
    
    //
    // Kill abruptly the EPMD Server. This is almost never used in practice.
    //
    _ = try
    spawn(name:EPMDRequest.kill){(senderPID,message) in
        
        let protocolData = buildKillMessage()
        let tracker = UUID()
        NSLog("\(tracker): sending kill request ")
        connection.send(content: protocolData, completion: NWConnection.SendCompletion.contentProcessed { error in
            guard let error = error else{
                NSLog("\(tracker): sent successfully")
                
                "clear_buffer" ! tracker//sending to next process
                
                return
            }
            NSLog("\(tracker): error \(error) send error")
            stop(client:EPMD)
        })
    }
}




func buildRegistrationMessageUsing(name:String,extras:[Byte]) -> Data {
    let extrasLength = UInt16(extras.count)
    let nameBytes = [Byte](name.utf8)
    let nameLength = UInt16(nameBytes.count)
    let messageLength = extrasLength + nameLength + 13//13 is the size of all the other components of the message. The 'fixed size' components.
    let protcolBytes:[EPMDMessageComponent] = [messageLength.toMessageByteOrder.toByteArray,.EPMD_ALIVE2_REQ,.NODE_PORT,.NODE_TYPE,.TCP_IPv4,.HIGHEST_OTP_VERSION,.LOWEST_OTP_VERSION,nameLength.toMessageByteOrder.toByteArray,nameBytes,extrasLength.toMessageByteOrder.toByteArray,extras]
    var protocolData = Data(capacity: Int(messageLength))
    protocolData.writeAll(in: protcolBytes)
    return protocolData
}

func buildPortPleaseMessageUsing(nodePid:String)->Data{
    let nodePidBytes = [Byte](nodePid.utf8)
    let nodePidLength = UInt16(nodePidBytes.count)
    let messageLength = nodePidLength + UInt16(EPMDMessageComponent.PORT_PLEASE_REQ.count)
        
    let protcolBytes:[EPMDMessageComponent] = [messageLength.toMessageByteOrder.toByteArray,
        .PORT_PLEASE_REQ,nodePidBytes]
    var protocolData = Data(capacity: Int(messageLength+2))//the length of the message plus the two bytes for the length(2 bytes) that gets prepended to every request to the EPMD server.
    protocolData.writeAll(in: protcolBytes)
    return protocolData
}

func buildNamesMessage()->Data{
    let messageLength = UInt16(1).toMessageByteOrder.toByteArray
    let messageID:[Byte] = [110]
    let protocolBytes:[EPMDMessageComponent] = [messageLength,messageID]
    var protocolData = Data(capacity: 1+2)//the length(2 bytes) of the message plus the two bytes for the length that gets prepended to every request to the EPMD server.
    protocolData.writeAll(in: protocolBytes)
    return protocolData
}


func buildKillMessage()->Data{
    let messageLength = UInt16(1).toMessageByteOrder.toByteArray
    let messageID:[Byte] = [107]
    let protocolBytes:[EPMDMessageComponent] = [messageLength,messageID]
    var protocolData = Data(capacity: 1+2)//the length(2 bytes) of the message plus the two bytes for the length that gets prepended to every request to the EPMD server.
    protocolData.writeAll(in: protocolBytes)
    return protocolData
}


@available(macOS 10.14, *)
func send(client:EPMD, data:Data, trackingID:UUID) {
    NSLog("Sending request \(trackingID)")
    client.connection.send(content: data, completion: NWConnection.SendCompletion.contentProcessed { error in
        guard let error = error else{
            NSLog("request \(trackingID) sent successfully")
            return
        }
        NSLog("request \(trackingID) got error \(error) when sending request")
        stop(client:client)
    })
}

///
///This function kills the client connection to the EPMD
///server. This causes the EPMD server to unregister the node.
@available(macOS 10.14, *)
func stop(client:EPMD) {
    client.connection.cancel()
    NSLog("did stop")
}
