//
//  Codec.swift
//
//
//  Created by Lee Barney on 12/15/22.
//

import Foundation

typealias Byte = UInt8

extension UInt16 {
    var bigendian_bytes: [Byte] {
        var value:UInt16 = 0
        //either a mutable byte switched version is needed
        //or a mutable value without the bytes being switched
        if CFByteOrderGetCurrent() == CFByteOrderLittleEndian.rawValue{
            value = self.bigEndian
            }
            else{
                value = self*1
            }
        let count = MemoryLayout<UInt16>.size
        let bytePtr = withUnsafePointer(to: &value) {
            $0.withMemoryRebound(to: Byte.self, capacity: count) {
                UnsafeBufferPointer(start: $0, count: count)
            }
        }
        return Array(bytePtr)
    }
}

///
///All Erlang inter-node messages use the big-endian
///representation for numbers. This function
///switches the representation of those numbers to match
///the machine's number representation type.
///
extension UInt16{
    var toMessageByteOrder:UInt16{
        if CFByteOrderGetCurrent() == CFByteOrderLittleEndian.rawValue {
            return self
        }
        return self.bigEndian
    }
}


extension UInt32{
    var toMessageByteOrder:UInt32{
        if CFByteOrderGetCurrent() == CFByteOrderLittleEndian.rawValue {
            return self
        }
        return self.bigEndian
    }
}

///
///All Erlang inter-node messages use the big-endian
///representation for numbers. This function
///switches the representation of the machine's numbers to be big-endian.
///
extension UInt16{
    var toMachineByteOrder:UInt16{
        if CFByteOrderGetCurrent() == CFByteOrderBigEndian.rawValue {
            return self
        }
        return self.littleEndian
    }
}
extension UInt32{
    var toMachineByteOrder:UInt32{
        if CFByteOrderGetCurrent() == CFByteOrderBigEndian.rawValue {
            return self
        }
        return self.littleEndian
    }
}
///
///converts an UInt16 to an array of two bytes
///
extension UInt16{
    var toByteArray:[Byte]{
        return withUnsafeBytes(of: self) {
            Array($0)
        }
        /*
        let count = MemoryLayout<UInt16>.size
        var duplicate = self
        let bytePtr = withUnsafePointer(to: &duplicate) {
            $0.withMemoryRebound(to: Byte.self, capacity: count) {
                UnsafeBufferPointer(start: $0, count: count)
            }
        }
        return [Byte](bytePtr)
         */
    }
}

extension UInt32 {
    var toByteArray:[Byte]{
        return withUnsafeBytes(of: self) {
            Array($0)
        }
    }
}

///
///Converts an array of two bytes to a UInt16
///
extension Data {
    var toUInt16: UInt16 {
        let asBytes = self.bytes
        return
            (UInt16(asBytes[0]) << (0*8)) | // shift 0 bits
            (UInt16(asBytes[1]) << (1*8))   // shift 8 bits
    }
}
//this extension uses multiplication rather than bit-shifting
//to give the compiler every chance to maximize optimization.
extension Data {
    var toUInt32: UInt32 {
        return UInt32(self[0])            | //<< (0*8)) | // shift 0 bits
               UInt32(self[1]) * 256      | // << (1*8)) | // shift 8 bits
               UInt32(self[2]) * 65536    | // << (2*8)) | // shift 16 bits
               UInt32(self[3]) * 16777216   // << (3*8))   // shift 24 bits
        
    }
}

extension Data {
    var bytes: [Byte] {
        var byteArray = [UInt8](repeating: 0, count: self.count)
        self.copyBytes(to: &byteArray, count: self.count)
        return byteArray
    }
}

extension Data{
    /// Write an array of bytes to a Data instance
    /// - Parameter bytes: the array of bytes to write at Data's current write postion. The write postion is updated by each write.
    /// - Returns: the modified Data instance
    /// - Complexity: O(n), where n is the number of bytes
    mutating func write(_ bytes:[Byte]){
        self.append(contentsOf: bytes)
    }
}

extension Data{
    /// Writes an array of an array of bytes in order, from first to last. Writting begins at the Data instance's current write location. The write location is updated to the end of the last written byte array.
    /// - Parameter list: an array of an array of bytes, [Byte] to be written to the Data instance
    /// - Returns: the modified data instance
    /// - Complexity: O(n), where n is the sum of the number of bytes in each byte array.
    mutating func writeAll(in list:[[Byte]]){
        list.forEach{
            self.write($0)//write each byte array
        }
    }
}

///
///Converts a Swift string to a portable byte representation
///for an Erlang tuple. Any uppercase character is converted
///to lowercase to conform with the tuple-naming requirement
///in Erlang.
extension String{
    var asAtom:[Byte]{
        return Array(Data(self.lowercased().utf8))
    }
}
/// A group of defined values used to produce
/// byte array messages for EPMD. The default node port number is 9090. To set a new port number it must be in bigendian bytes. Ex. UInt16(8888).be\_bytes for port number 8888
///
/// Both the Highest and Lowest versions of OTP suppported are 23 and higher. By default, there are no extras included. You can change this by adding them.
///
/// Make all changes to the static variables ***BEFORE*** using the other elements of EPMDMessageComponents. Some elements are calculated variables. The byte arrays are all bigendian.
typealias EPMDMessageComponent = [Byte]
extension EPMDMessageComponent{
    static let STATUS_INDICATOR: [Byte] = [Byte(73)]
    static let NAME_MESSAGE_INDICATOR:[Byte] = [Byte(78)]
    static let EPMD_NON_VARIABLE_SIZE = [Byte(13)]//the size of the non-variable fields as defined at https://www.erlang.org/doc/apps/erts/erl_dist_protocol.html
    static let PORT_PLEASE_REQ = [Byte(122)]
    static let EPMD_ALIVE2_REQ = [Byte(120)]
    static let NODE_TYPE = [Byte(72)]//native type node
    static let TCP_IPv4 = [Byte(0)]
    static let TCP_IPv6 = [Byte(1)]
    static let HIGHEST_OTP_VERSION = UInt16(6).toMessageByteOrder.toByteArray
    static let LOWEST_OTP_VERSION = HIGHEST_OTP_VERSION
}


