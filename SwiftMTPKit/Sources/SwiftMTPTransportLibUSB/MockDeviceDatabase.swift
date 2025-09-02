import Foundation
import SwiftMTPCore

/// Database of predefined mock devices for testing
public extension MockDeviceData {

    // MARK: - Android Devices

    @preconcurrency
    static let androidPixel7 = MockDeviceData(
        deviceSummary: MTPDeviceSummary(
            id: MTPDeviceID(raw: "18d1:4ee1@1:2"),
            manufacturer: "Google",
            model: "Pixel 7"
        ),
        deviceInfo: MTPDeviceInfo(
            manufacturer: "Google",
            model: "Pixel 7",
            version: "TQ3A.230605.010",
            serialNumber: "HT1A12345678",
            operationsSupported: [
                0x1001, // GetDeviceInfo
                0x1002, // OpenSession
                0x1003, // CloseSession
                0x1004, // GetStorageIDs
                0x1005, // GetStorageInfo
                0x1006, // GetNumObjects
                0x1007, // GetObjectHandles
                0x1008, // GetObjectInfo
                0x1009, // GetObject
                0x100A, // GetThumb
                0x100B, // DeleteObject
                0x100C, // SendObjectInfo
                0x100D, // SendObject
                0x1014, // GetDevicePropDesc
                0x1015, // GetDevicePropValue
                0x1016, // SetDevicePropValue
                0x1017, // ResetDevicePropValue
            ],
            eventsSupported: [
                0x4002, // ObjectAdded
                0x4003, // ObjectRemoved
                0x4004, // StoreAdded
                0x4005, // StoreRemoved
                0x4006, // DevicePropChanged
                0x4007, // ObjectInfoChanged
            ]
        ),
        storages: [
            MTPStorageInfo(
                id: MTPStorageID(raw: 0x00010001),
                description: "Internal Storage",
                capacityBytes: 128_000_000_000, // 128GB
                freeBytes: 80_000_000_000,       // 80GB free
                isReadOnly: false
            ),
            MTPStorageInfo(
                id: MTPStorageID(raw: 0x00020001),
                description: "SD Card",
                capacityBytes: 256_000_000_000, // 256GB
                freeBytes: 200_000_000_000,     // 200GB free
                isReadOnly: false
            )
        ],
        objects: [
            MockObjectData(
                handle: 1,
                storage: MTPStorageID(raw: 0x00010001),
                parent: nil,
                name: "DCIM",
                formatCode: 0x3001 // Association/Directory
            ),
            MockObjectData(
                handle: 2,
                storage: MTPStorageID(raw: 0x00010001),
                parent: 1,
                name: "Camera",
                formatCode: 0x3001
            ),
            MockObjectData(
                handle: 3,
                storage: MTPStorageID(raw: 0x00010001),
                parent: 2,
                name: "IMG_20240101_120000.jpg",
                size: 2_500_000,
                formatCode: 0x3801, // EXIF/JPEG
                data: Data(repeating: 0xFF, count: 2_500_000)
            ),
            MockObjectData(
                handle: 4,
                storage: MTPStorageID(raw: 0x00010001),
                parent: 2,
                name: "VID_20240101_120100.mp4",
                size: 50_000_000,
                formatCode: 0x3009, // MP4
                data: Data(repeating: 0x00, count: 50_000_000)
            ),
            MockObjectData(
                handle: 5,
                storage: MTPStorageID(raw: 0x00010001),
                parent: nil,
                name: "Download",
                formatCode: 0x3001
            ),
            MockObjectData(
                handle: 6,
                storage: MTPStorageID(raw: 0x00010001),
                parent: 5,
                name: "document.pdf",
                size: 1_200_000,
                formatCode: 0x3008, // PDF
                data: Data(repeating: 0xAA, count: 1_200_000)
            )
        ],
        operationsSupported: [
            0x1001, 0x1002, 0x1003, 0x1004, 0x1005, 0x1006,
            0x1007, 0x1008, 0x1009, 0x100A, 0x100B, 0x100C,
            0x100D, 0x1014, 0x1015, 0x1016, 0x1017
        ],
        eventsSupported: [
            0x4002, 0x4003, 0x4004, 0x4005, 0x4006, 0x4007
        ],
        failureMode: nil
    )

    static let androidGalaxyS21 = MockDeviceData(
        deviceSummary: MTPDeviceSummary(
            id: MTPDeviceID(raw: "04e8:6860@1:3"),
            manufacturer: "Samsung",
            model: "Galaxy S21"
        ),
        deviceInfo: MTPDeviceInfo(
            manufacturer: "Samsung Electronics Co., Ltd.",
            model: "SM-G991B",
            version: "TP1A.220624.014",
            serialNumber: "R58N123ABCD",
            operationsSupported: [
                0x1001, 0x1002, 0x1003, 0x1004, 0x1005, 0x1006,
                0x1007, 0x1008, 0x1009, 0x100A, 0x100B, 0x100C,
                0x100D, 0x1014, 0x1015, 0x1016, 0x1017, 0x1019,
                0x101A, 0x101B
            ],
            eventsSupported: [
                0x4002, 0x4003, 0x4004, 0x4005, 0x4006, 0x4007,
                0x4008, 0x4009, 0x400A
            ]
        ),
        storages: [
            MTPStorageInfo(
                id: MTPStorageID(raw: 0x00010001),
                description: "Internal Storage",
                capacityBytes: 256_000_000_000, // 256GB
                freeBytes: 180_000_000_000,     // 180GB free
                isReadOnly: false
            )
        ],
        objects: [
            MockObjectData(
                handle: 1,
                storage: MTPStorageID(raw: 0x00010001),
                parent: nil,
                name: "DCIM",
                formatCode: 0x3001
            ),
            MockObjectData(
                handle: 2,
                storage: MTPStorageID(raw: 0x00010001),
                parent: 1,
                name: "Camera",
                formatCode: 0x3001
            ),
            MockObjectData(
                handle: 3,
                storage: MTPStorageID(raw: 0x00010001),
                parent: 2,
                name: "20240101_120000.jpg",
                size: 3_200_000,
                formatCode: 0x3801,
                data: Data(repeating: 0x88, count: 3_200_000)
            )
        ],
        operationsSupported: [
            0x1001, 0x1002, 0x1003, 0x1004, 0x1005, 0x1006,
            0x1007, 0x1008, 0x1009, 0x100A, 0x100B, 0x100C,
            0x100D, 0x1014, 0x1015, 0x1016, 0x1017, 0x1019,
            0x101A, 0x101B
        ],
        eventsSupported: [
            0x4002, 0x4003, 0x4004, 0x4005, 0x4006, 0x4007,
            0x4008, 0x4009, 0x400A
        ],
        failureMode: nil
    )

    // MARK: - iOS Devices

    static let iosDevice = MockDeviceData(
        deviceSummary: MTPDeviceSummary(
            id: MTPDeviceID(raw: "05ac:12a8@1:4"),
            manufacturer: "Apple",
            model: "iPhone"
        ),
        deviceInfo: MTPDeviceInfo(
            manufacturer: "Apple Inc.",
            model: "iPhone15,2",
            version: "17.2.1",
            serialNumber: "F2LV12345678",
            operationsSupported: [
                0x1001, 0x1002, 0x1003, 0x1004, 0x1005, 0x1006,
                0x1007, 0x1008, 0x1009, 0x100A, 0x100B, 0x100C,
                0x100D, 0x1014, 0x1015, 0x1016, 0x1017
            ],
            eventsSupported: [
                0x4002, 0x4003, 0x4004, 0x4005, 0x4006, 0x4007
            ]
        ),
        storages: [
            MTPStorageInfo(
                id: MTPStorageID(raw: 0x00010001),
                description: "iPhone Storage",
                capacityBytes: 128_000_000_000, // 128GB
                freeBytes: 50_000_000_000,      // 50GB free
                isReadOnly: false
            )
        ],
        objects: [
            MockObjectData(
                handle: 1,
                storage: MTPStorageID(raw: 0x00010001),
                parent: nil,
                name: "DCIM",
                formatCode: 0x3001
            ),
            MockObjectData(
                handle: 2,
                storage: MTPStorageID(raw: 0x00010001),
                parent: 1,
                name: "100APPLE",
                formatCode: 0x3001
            ),
            MockObjectData(
                handle: 3,
                storage: MTPStorageID(raw: 0x00010001),
                parent: 2,
                name: "IMG_2024.JPG",
                size: 2_800_000,
                formatCode: 0x3801,
                data: Data(repeating: 0x99, count: 2_800_000)
            )
        ],
        operationsSupported: [
            0x1001, 0x1002, 0x1003, 0x1004, 0x1005, 0x1006,
            0x1007, 0x1008, 0x1009, 0x100A, 0x100B, 0x100C,
            0x100D, 0x1014, 0x1015, 0x1016, 0x1017
        ],
        eventsSupported: [
            0x4002, 0x4003, 0x4004, 0x4005, 0x4006, 0x4007
        ],
        failureMode: nil
    )

    // MARK: - Camera Devices

    static let canonCamera = MockDeviceData(
        deviceSummary: MTPDeviceSummary(
            id: MTPDeviceID(raw: "04a9:317a@1:5"),
            manufacturer: "Canon",
            model: "EOS R5"
        ),
        deviceInfo: MTPDeviceInfo(
            manufacturer: "Canon Inc.",
            model: "Canon EOS R5",
            version: "1.0.0",
            serialNumber: "1234567890",
            operationsSupported: [
                0x1001, 0x1002, 0x1003, 0x1004, 0x1005, 0x1006,
                0x1007, 0x1008, 0x1009, 0x100A, 0x100B, 0x100C,
                0x100D, 0x1014, 0x1015, 0x1016, 0x1017, 0x1018,
                0x1019, 0x101A, 0x101B, 0x9001, 0x9002, 0x9003
            ],
            eventsSupported: [
                0x4002, 0x4003, 0x4004, 0x4005, 0x4006, 0x4007,
                0x4008, 0x4009, 0x400A, 0xC001, 0xC002, 0xC003
            ]
        ),
        storages: [
            MTPStorageInfo(
                id: MTPStorageID(raw: 0x00010001),
                description: "CFexpress Card",
                capacityBytes: 512_000_000_000, // 512GB
                freeBytes: 400_000_000_000,     // 400GB free
                isReadOnly: false
            ),
            MTPStorageInfo(
                id: MTPStorageID(raw: 0x00020001),
                description: "SD Card",
                capacityBytes: 128_000_000_000, // 128GB
                freeBytes: 100_000_000_000,     // 100GB free
                isReadOnly: false
            )
        ],
        objects: [
            MockObjectData(
                handle: 1,
                storage: MTPStorageID(raw: 0x00010001),
                parent: nil,
                name: "DCIM",
                formatCode: 0x3001
            ),
            MockObjectData(
                handle: 2,
                storage: MTPStorageID(raw: 0x00010001),
                parent: 1,
                name: "100CANON",
                formatCode: 0x3001
            ),
            MockObjectData(
                handle: 3,
                storage: MTPStorageID(raw: 0x00010001),
                parent: 2,
                name: "IMG_0001.CR3",
                size: 80_000_000,
                formatCode: 0xB101, // Canon CR3
                data: Data(repeating: 0x77, count: 80_000_000)
            ),
            MockObjectData(
                handle: 4,
                storage: MTPStorageID(raw: 0x00010001),
                parent: 2,
                name: "IMG_0002.JPG",
                size: 15_000_000,
                formatCode: 0x3801,
                data: Data(repeating: 0x66, count: 15_000_000)
            )
        ],
        operationsSupported: [
            0x1001, 0x1002, 0x1003, 0x1004, 0x1005, 0x1006,
            0x1007, 0x1008, 0x1009, 0x100A, 0x100B, 0x100C,
            0x100D, 0x1014, 0x1015, 0x1016, 0x1017, 0x1018,
            0x1019, 0x101A, 0x101B, 0x9001, 0x9002, 0x9003
        ],
        eventsSupported: [
            0x4002, 0x4003, 0x4004, 0x4005, 0x4006, 0x4007,
            0x4008, 0x4009, 0x400A, 0xC001, 0xC002, 0xC003
        ],
        failureMode: nil
    )

    // MARK: - Error Scenarios

    static let failureTimeout = MockDeviceData(
        deviceSummary: MTPDeviceSummary(
            id: MTPDeviceID(raw: "18d1:4ee1@1:2"),
            manufacturer: "Google",
            model: "Pixel 7"
        ),
        deviceInfo: MTPDeviceInfo(
            manufacturer: "Google",
            model: "Pixel 7",
            version: "TQ3A.230605.010",
            serialNumber: "HT1A12345678",
            operationsSupported: [],
            eventsSupported: []
        ),
        storages: [],
        objects: [],
        operationsSupported: [],
        eventsSupported: [],
        failureMode: .timeout
    )

    static let failureBusy = MockDeviceData(
        deviceSummary: MTPDeviceSummary(
            id: MTPDeviceID(raw: "18d1:4ee1@1:2"),
            manufacturer: "Google",
            model: "Pixel 7"
        ),
        deviceInfo: MTPDeviceInfo(
            manufacturer: "Google",
            model: "Pixel 7",
            version: "TQ3A.230605.010",
            serialNumber: "HT1A12345678",
            operationsSupported: [],
            eventsSupported: []
        ),
        storages: [],
        objects: [],
        operationsSupported: [],
        eventsSupported: [],
        failureMode: .busy
    )

    static let failureDisconnected = MockDeviceData(
        deviceSummary: MTPDeviceSummary(
            id: MTPDeviceID(raw: "18d1:4ee1@1:2"),
            manufacturer: "Google",
            model: "Pixel 7"
        ),
        deviceInfo: MTPDeviceInfo(
            manufacturer: "Google",
            model: "Pixel 7",
            version: "TQ3A.230605.010",
            serialNumber: "HT1A12345678",
            operationsSupported: [],
            eventsSupported: []
        ),
        storages: [],
        objects: [],
        operationsSupported: [],
        eventsSupported: [],
        failureMode: .deviceDisconnected
    )
}
