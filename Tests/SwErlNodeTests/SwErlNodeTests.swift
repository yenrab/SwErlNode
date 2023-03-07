import XCTest
import Network
import Logging
@testable import SwErl
@testable import SwErlNode

final class SwErlNodeTests: XCTestCase {
    override func setUp() {
        
        // This is the setUp() instance method.
        // XCTest calls it before each test method.
        // Set up any synchronous per-test state here.
        Registrar.instance.processesRegisteredByPid = [:]
        Registrar.instance.processesRegisteredByName = [:]
    }
    
    override func tearDown() {
        // This is the tearDown() instance method.
        // XCTest calls it after each test method.
        // Perform any synchronous per-test cleanup here.
        Registrar.instance.processesRegisteredByPid = [:]
        Registrar.instance.processesRegisteredByName = [:]
    }
    func testKillMessageBuilding() throws {
        let message = buildKillMessage()
        XCTAssertEqual(message[0], 1)//first byte of message length
        XCTAssertEqual(message[1], 0)//second byte of message length
        XCTAssertEqual(message[2], 107)//message content
    }
    
    func testNamesMessageBuilding() throws {
        let message = buildNamesMessage()
        XCTAssertEqual(message[0], 1)//first byte of message length
        XCTAssertEqual(message[1], 0)//second byte of message length
        XCTAssertEqual(message[2], 110)
    }
    
    func testPortPleaseMessageBuilding() throws {
        let message = buildPortPleaseMessageUsing(nodeName: "testing@silly")
        XCTAssertEqual(message[0], 14)//first byte of message length
        XCTAssertEqual(message[1], 0)//second byte of message length
        XCTAssertEqual(message[2], 122)
        XCTAssertEqual(message[3...15], Data("testing@silly".utf8))//message portion starts at position 1 and is 13 long
    }
    func testRegistrationMessageBuilding() throws {
        let message = buildRegistrationMessageUsing(nodeName: "testing@silly",port: 9090,extras:[])
        XCTAssertEqual(message[0], 26)//first byte of message length
        XCTAssertEqual(message[1], 0)//second byte of message length
        XCTAssertEqual(message[2], 120)
        XCTAssertEqual(message[3...4], Data(UInt16(9090).toMessageByteOrder.toByteArray))//port is two bytes long
        XCTAssertEqual(message[5], 72)//native (hidden) node type
        XCTAssertEqual(message[6], 0)//tcp protocol type
        XCTAssertEqual(message[7...8], Data(UInt16(6).toMessageByteOrder.toByteArray))//highest Erlang version is two bytes long
        XCTAssertEqual(message[9...10], Data(UInt16(6).toMessageByteOrder.toByteArray))//lowest Erlang version is two bytes long
        XCTAssertEqual(message[11...12], Data(UInt16(13).toMessageByteOrder.toByteArray))//name length is two bytes long)
        XCTAssertEqual(message[13...25], Data("testing@silly".utf8))//message portion starts at position 13 and is 13 long
        XCTAssertEqual(message[26], 0)
    }
    
    
    func testRegistrationMessageBuildingWithExtras() throws {
        let message = buildRegistrationMessageUsing(nodeName: "testing@silly",port: 9090,extras:[UInt8(1),UInt8(2),UInt8(3)])
        XCTAssertEqual(message[0], 29)//first byte of message length
        XCTAssertEqual(message[1], 0)//second byte of message length
        XCTAssertEqual(message[2], 120)
        XCTAssertEqual(message[3...4], Data(UInt16(9090).toMessageByteOrder.toByteArray))//port is two bytes long
        XCTAssertEqual(message[5], 72)//native (hidden) node type
        XCTAssertEqual(message[6], 0)//tcp protocol type
        XCTAssertEqual(message[7...8], Data(UInt16(6).toMessageByteOrder.toByteArray))//highest Erlang version is two bytes long
        XCTAssertEqual(message[9...10], Data(UInt16(6).toMessageByteOrder.toByteArray))//lowest Erlang version is two bytes long
        XCTAssertEqual(message[11...12], Data(UInt16(13).toMessageByteOrder.toByteArray))//name length is two bytes long)
        XCTAssertEqual(message[13...25], Data("testing@silly".utf8))//message portion starts at position 13 and is 13 long
        XCTAssertEqual(message[26], 3)//first byte of extras length
        XCTAssertEqual(message[27], 0)//second byte of extras length
        XCTAssertEqual(message[28], 1)
        XCTAssertEqual(message[29], 2)
        XCTAssertEqual(message[30], 3)
    }
    
    func testStartPeerPortsDictionary(){
        XCTAssertNoThrow(try startPeerPortsDictionary())
        //the process storing the peer information by peer name
        let pid = Registrar.instance.processesRegisteredByName["peerPorts"]
        XCTAssertNotNil(pid)
        XCTAssertNotNil(Registrar.instance.processesRegisteredByPid[pid!])
    }
    func testSpawnProcessesFor() throws{
        let port = NWEndpoint.Port(9090)
        let host = NWEndpoint.Host("test@silly")
        let connection = NWConnection(host: host, port: port, using: .tcp)
        XCTAssertNoThrow(try spawnProcessesFor(EPMD: (port,host,connection,"test@silly")))
        
        //examine if pids and closures were stored
        var pid = Registrar.instance.processesRegisteredByName["clear_buffer"]
        XCTAssertNotNil(pid)//pid was stored
        XCTAssertNotNil(Registrar.instance.processesRegisteredByPid[pid!])//closure was stored
        
        pid = Registrar.instance.processesRegisteredByName[EPMDRequest.register_node]
        XCTAssertNotNil(pid)
        XCTAssertNotNil(Registrar.instance.processesRegisteredByPid[pid!])
        
        
        pid = Registrar.instance.processesRegisteredByName[EPMDRequest.port_please]
        XCTAssertNotNil(pid)
        XCTAssertNotNil(Registrar.instance.processesRegisteredByPid[pid!])
        
        pid = Registrar.instance.processesRegisteredByName[EPMDRequest.names]
        XCTAssertNotNil(pid)
        XCTAssertNotNil(Registrar.instance.processesRegisteredByPid[pid!])
        
        pid = Registrar.instance.processesRegisteredByName[EPMDRequest.kill]
        XCTAssertNotNil(pid)
        XCTAssertNotNil(Registrar.instance.processesRegisteredByPid[pid!])
        
    }
    
    
    ////////////////////////////////////////////
    //Component level tests
    ////////////////////////////////////////////
    public typealias MockServer = (listener:NWListener,
                                   queue:DispatchQueue)
    func testRegister() throws{
    
        //this stateful process stores the server's incomming connection
        //from the client so it doesn't go out of scope and terminate
        let _ = try spawn(name: "connections",initialState: Dictionary<Int,NWConnection>()) {(pid,state,message)  in
            guard var updatedState = state as? Dictionary<Int,NWConnection> else{
                return Dictionary<Int,NWConnection>()
            }
            guard let message = message as? NWConnection else{
                return state
            }
            updatedState[updatedState.count+1] = message
            return updatedState
        }
        //get the hostname for the testing device
        let hostName = ProcessInfo.processInfo.hostName
        
        //set up a mock server
        let mock:MockServer = (try NWListener(using: .tcp, on: 4369),
                               DispatchQueue.global())
        let serverReadyExpectation = XCTestExpectation()
        mock.listener.stateUpdateHandler = {newState in
            switch newState {
            case .setup:
                break
            case .waiting:
                break
            case .ready:
                serverReadyExpectation.fulfill()
            case .failed(let error):
                print("got failed state with error \(error)")
                mock.listener.cancel()
                XCTAssertTrue(false)
            case .cancelled:
                XCTAssertTrue(false)
            default:
                mock.listener.cancel()
                XCTAssertTrue(false)
            }
        }
        mock.listener.newConnectionHandler = { newConnection in
            //store the connection so it doesn't go out of scope
            "connections" ! newConnection
            //
            //start up the mock server listening as if it was an EPMD service
            //
            newConnection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _context, isDone, error in
                
                if let data = data, !data.isEmpty {
                    let messageLength = data[0...1].toUInt32.toMachineByteOrder
                    XCTAssertEqual(data[0], 26)//first byte of message length
                    XCTAssertEqual(data[1], 0)//second byte of message length
                    XCTAssertEqual(data[2], 120)//got node registration request
                    XCTAssertEqual(data[3...4].toUInt16.toMachineByteOrder, 9090)//port is two bytes long and correct
                    XCTAssertEqual(data[5], 72)//native (hidden) node type
                    XCTAssertEqual(data[6], 0)//tcp protocol type
                    XCTAssertEqual(data[7...8], Data(UInt16(6).toMessageByteOrder.toByteArray))//highest Erlang version is two bytes long
                    XCTAssertEqual(data[9...10], Data(UInt16(6).toMessageByteOrder.toByteArray))//lowest Erlang version is two bytes long
                    let nameLength = data[11...12].toUInt16.toMachineByteOrder
                    
                    let actualNameLength = UInt16(5+hostName.count)
                    XCTAssertEqual(nameLength,actualNameLength)//name length is two bytes long)
                    XCTAssertEqual(data[13...(actualNameLength - 1)], Data("test@\(hostName)".utf8))//message portion starts at position 13 and is 13 long
                    XCTAssertEqual(data[26], 0)
                    //send response back
                    let responseArray:[[Byte]] = [[121],//response indicator
                                                  [0],//registration success indicator
                                                  UInt32(313).toMessageByteOrder.toByteArray//creation data
                    ]
                    var responseData = Data(capacity: 4)
                    responseData.writeAll(in: responseArray)
                    newConnection.send(content: responseData, completion: NWConnection.SendCompletion.contentProcessed { error in
                        XCTAssertNil(error)
                    })
                    return
                }
                XCTAssertNil(error)//read error did not happen
                XCTAssertFalse(isDone)//client did not terminate connection
                return
            }
        }
        
        //start the mock server
        mock.listener.start(queue: mock.queue)
        wait(for: [serverReadyExpectation], timeout: 11.0)
        
        let allDone = expectation(description: "completed receive")
        //spawn the ultimate processes
        let ultimateAssertProcess = try spawn{(tracker,message) in
            allDone.fulfill()
            XCTAssertEqual("ok", message as! String)
        }
        
        //Start up the EPMD client
        let port = NWEndpoint.Port(4369)
        let host = NWEndpoint.Host(hostName)
        let connection = NWConnection(host: host, port: port, using: .tcp)
        let client:EPMD = (port,host,connection,
                                 nodeName:"test")
        try spawnProcessesFor(EPMD: client)
        //make the registration request
        EPMDRequest.register_node ! ultimateAssertProcess//replace the ultimate process. The ultimate process must have an expectation that it fulfills when everything works correctly.
        wait(for: [allDone], timeout: 9.0)
        //clean up
        mock.listener.stateUpdateHandler = nil
        mock.listener.newConnectionHandler = nil
        mock.listener.cancel()
    }
    
    ////////////////////////////////////////////
    //System level tests
    ////////////////////////////////////////////
    func testStartStopEPMDClient() throws {
        let epmdServiceStarted = XCTestExpectation(description: "send completed.")
        let EPMDService = try spawn{(EPMDPid,message) in
            do{
                let (erlPath,nodeName) = message as! (String,String)
                let epmdTask = Process()
                epmdTask.launchPath = erlPath
                epmdTask.arguments = ["-name \(nodeName)", "-setcookie mysecretcookie"]
                try epmdTask.run()
                epmdServiceStarted.fulfill()
                epmdTask.waitUntilExit()
            }
            catch{
                print(error)
            }
        }
        //change the path to be the path of the erl executable on your machine. Tried using the 'which' helper function below, it
        //always came back with an empty string.
        //It may not traverse the links homebrew uses.
        EPMDService ! ("/opt/homebrew/bin/erl","epmd")
        
        wait(for: [epmdServiceStarted], timeout: 20.0)
        let hostName = ProcessInfo.processInfo.hostName
        
        let port = NWEndpoint.Port(4369)//default EPMD service port
        let host = NWEndpoint.Host(hostName)
        let connection = NWConnection(host: host, port: port, using: .tcp)
        XCTAssertEqual(connection.state, NWConnection.State.setup)
        
        let readyExpectation = XCTestExpectation(description: "started.")
        let cancelationExpectation = XCTestExpectation(description: "canceled")
        start(client: (port,host,connection,"epmd@\(hostName)")){ newState in
            switch newState {
            case .ready:
                logger?.trace("\(connection) established")
                readyExpectation.fulfill()
                
                // Notify the delegate that the connection is ready.
                //if let delegate = self?.delegate {
                //    delegate.connectionReady()
                //}
            case .cancelled:
                cancelationExpectation.fulfill()
            case .failed(let error):
                logger?.error("\(connection) EPMD client failed with \(error)")
                
                // Cancel the connection upon a failure.
                connection.cancel()
            default:
                logger?.error("Unhandled NWConnection state \(newState)")
                break
            }
        }
        
        wait(for: [readyExpectation], timeout: 60.0)
        
        stop(client: (port,host,connection,"epmd@\(hostName)"), trackerID: UUID())
        wait(for: [cancelationExpectation], timeout: 60.0)
    
    }
}

//    func testTempWhatHappens() throws{
//        let hostName = ProcessInfo.processInfo.hostName
//
//        let port = NWEndpoint.Port(4369)
//        let host = NWEndpoint.Host(hostName)
//        let connection = NWConnection(host: host, port: port, using: .tcp)
//        XCTAssertEqual(connection.state, NWConnection.State.setup)
//
//        let setupExpectation = XCTestExpectation(description: "in setup state.")
//        XCTAssertNoThrow(try spawnProcessesFor(EPMD: (port,host,connection,"test@\(hostName)")))
//
//        //send a message,without starting, hangs.
//        EPMDRequest.register_node ! "noMessage"
//        //what happens if you start the client after you send a message?
//        start(client: (port,host,connection,"epmd@\(hostName)")){ newState in
//            switch newState {
//            case .ready:
//                logger?.trace("\(connection) established")
//
//
//                // Notify the delegate that the connection is ready.
//                //if let delegate = self?.delegate {
//                //    delegate.connectionReady()
//                //}
//            case .cancelled:
//                logger?.trace("\(connection) connection canceled")
//            case .failed(let error):
//                logger?.error("\(connection) EPMD client failed with \(error)")
//
//                // Cancel the connection upon a failure.
//                connection.cancel()
//            default:
//                logger?.error("Unhandled NWConnection state \(newState)")
//                break
//            }
//        }
//        wait(for: [setupExpectation], timeout: 10.0)
//
//    }
//}

////////////////////////////////////////////
//These helpers are for component level testing
////////////////////////////////////////////
func which(_ command: String) -> (String,String) {
    let task = Process()
    
    let outpipe = Pipe()
    let errpipe = Pipe()
    
    task.standardOutput = outpipe
    task.standardError = errpipe
    
    task.launchPath = "/usr/bin/which"
    task.arguments = [command]
    task.launch()
    
    let pathData = outpipe.fileHandleForReading.readDataToEndOfFile()
    let errData = errpipe.fileHandleForReading.readDataToEndOfFile()
    
    
    return (String(data: pathData, encoding: .utf8)!,String(data: errData, encoding: .utf8)!)
}



//store all connections in a stateful SwErl process where the state is the mock server

//eventually break this out into its own process so we can
//use an expectation to wait until the server is ready to
//receive a request before one is sent.
//    func startMock() throws {
//        let mock:MockServer = (try NWListener(using: .tcp, on: 4369),
//                               DispatchQueue.global())
//        let _ = try spawn(name: "connections",initialState: Dictionary<Int,NWConnection>()) {(pid,state,message)  in
//            guard var updatedState = state as? Dictionary<Int,NWConnection> else{
//                return Dictionary<Int,NWConnection>()
//            }
//            guard let message = message as? NWConnection else{
//                return state
//            }
//            updatedState[updatedState.count+1] = message
//            return updatedState
//        }
//        let readyExpectation = XCTestExpectation()
//        mock.listener.stateUpdateHandler = {newState in
//            switch newState {
//            case .setup:
//                break
//            case .waiting:
//                break
//            case .ready:
//                //put expectation fullfilment code here
//                break
//            case .failed(let error):
//                print("server failed, error: \(error)")
//                mock.listener.stateUpdateHandler = nil
//                mock.listener.newConnectionHandler = nil
//                mock.listener.cancel()
//                Registrar.instance.processesRegisteredByName = [:]
//                Registrar.instance.processesRegisteredByPid = [:]
//            case .cancelled:
//                break
//            default:
//                break
//            }
//        }
//
//        mock.listener.newConnectionHandler = {newConnection in
//            "connections" ! newConnection
//            print("accepted connection: \(newConnection)")
//            //
//            //start up the mock listening as if it was an EPMD service
//            //
//            newConnection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _context, isDone, error in
//
//                if let data = data, !data.isEmpty {
//                    let messageLength = data[0...1].toUInt32.toMachineByteOrder
//                    if messageLength == 1{//is a data request
//                        let requestType = data[2]
//                        switch requestType{
//                        case 110://respond with list of names as strings
//                            let responseArray:[[Byte]] = [UInt32(8080).toMessageByteOrder.toByteArray,"bob".data(using: .utf8)!.bytes,UInt32(4567).toMessageByteOrder.toByteArray,"sue".data(using: .utf8)!.bytes,UInt32(9087).toMessageByteOrder.toByteArray]
//                            var responseData = Data(capacity: 30)
//                            responseData.writeAll(in: responseArray)
//                            newConnection.send(content: responseData, completion: NWConnection.SendCompletion.contentProcessed { error in
//                                guard let error = error else{
//                                    print("sent successfully")
//                                    return
//                                }
//                                print("sending error \(error)")
//                            })
//                        case 107://terminate the service
//                            mock.listener.stateUpdateHandler = nil
//                            mock.listener.newConnectionHandler = nil
//                            mock.listener.cancel()
//                            Registrar.instance.processesRegisteredByName = [:]
//                            Registrar.instance.processesRegisteredByPid = [:]
//                        default:
//                            print("unknown request type \(requestType)")
//                        }
//                    }
//                    else{//long message
//
//                    }
//
//                }
//                if let error = error {
//                    print("!!!!!!\nError \(error) receiving\n!!!!!!")
//                    return
//                }
//                if isDone {
//                    print("receive got EOF")//client terminated connection
//                    return
//                }
//            }
//
//
//
//
//            mock.listener.start(queue: mock.queue)
//        }


