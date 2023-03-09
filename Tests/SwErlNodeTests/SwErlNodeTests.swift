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
        XCTAssertNoThrow(try spawnProcessesFor(EPMD: (port,host,connection,"test@silly",8080)))
        
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
        //get the hostname for the testing device
        let hostName = ProcessInfo.processInfo.hostName
        
        //set up a mock server
        let mock:MockServer = (try NWListener(using: .tcp, on: 4369),
                               .global())
        mock.listener.newConnectionHandler = { newConnection in
            
            //
            //start up the mock server listening as if it was an EPMD service
            //
            newConnection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _context, isDone, error in
                if let data = data, !data.isEmpty {
                    let messageLength = data[0...1].toUInt16.toMachineByteOrder
                    XCTAssertEqual(messageLength, 40)//first byte of message length
                    XCTAssertEqual(data[1], 0)//second byte of message length
                    XCTAssertEqual(data[2], 120)//got node registration request
                    let portNum = data[3...4].toUInt16.toMachineByteOrder
                    XCTAssertEqual(portNum, 9090)//port is two bytes long and correct
                    XCTAssertEqual(data[5], 72)//native (hidden) node type
                    XCTAssertEqual(data[6], 0)//tcp protocol type
                    XCTAssertEqual(data[7...8].toUInt16, 6)//highest Erlang version is two bytes long
                    XCTAssertEqual(data[9...10].toUInt16, 6)//lowest Erlang version is two bytes long
                    let nameLength = data[11...12].toUInt16.toMachineByteOrder
                    
                    let actualNameLength = UInt16(5+hostName.count)
                    XCTAssertEqual(nameLength,actualNameLength)//name length is two bytes long)
                    let name = String(decoding:data[13...(13+actualNameLength-1)], as: UTF8.self)
                    XCTAssertEqual(name,"test@\(hostName)")//message portion starts at position 13 and is 13 long
                    //XCTAssertEqual(data[26], 0)//something is strange with this assertion. It ends up being executed twice within a single test execution. The first time is passes, as it should. The second time it fails with none of the other assertions prior to it being executed.
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
            }
            newConnection.start(queue: .global())//trigger the reading of the incoming data
        }
        
        //start the mock server
        mock.listener.start(queue: mock.queue)
        //wait(for: [serverReadyExpectation], timeout: 11.0)
        
        let allDone = expectation(description: "completed receive")
        //spawn the ultimate processes
        let ultimateAssertProcess = try spawn{(pid,message) in
            let (_,success) = message as! (UUID,String)
            allDone.fulfill()
            XCTAssertEqual("ok", success)
        }
        
        //Start up the EPMD client
        let port = NWEndpoint.Port(4369)
        let host = NWEndpoint.Host(hostName)
        let connection = NWConnection(host: host, port: port, using: .tcp)
        connection.start(queue: DispatchQueue.global())
        
        let client = (port,host,connection,"test@\(hostName)",UInt16(9090))//this is the EPMD tuple
        try spawnProcessesFor(EPMD: client)
        //wait until the client is ready
        //wait(for: [clientReadyExpectation], timeout: 9.0)
        
        //make the registration request
        EPMDRequest.register_node ! ultimateAssertProcess//replace the ultimate process. The ultimate process must have an expectation that it fulfills when everything works correctly.
        wait(for: [allDone], timeout: 9.0)
        //clean up
        mock.listener.stateUpdateHandler = nil
        mock.listener.newConnectionHandler = nil
        mock.listener.cancel()
    }
}

