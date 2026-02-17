# Quirks JSON Schema Reference

Complete reference for the device quirks JSON schema used to configure device-specific behaviors in SwiftMTP.

## Overview

Device quirks allow SwiftMTP to handle manufacturer-specific behaviors and limitations. The schema is defined in JSON Schema format and validates quirk configuration files.

```
┌─────────────────────────────────────────────────────────────┐
│                  Quirks System                                 │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────┐    ┌─────────────────┐                │
│  │  quirks.json    │───▶│  DeviceActor   │                │
│  │  (Configuration) │    │  (Runtime)     │                │
│  └─────────────────┘    └─────────────────┘                │
│           │                       │                         │
│           ▼                       ▼                         │
│  ┌─────────────────────────────────────────────┐            │
│  │         Device-Specific Behavior             │            │
│  │  - Transfer optimizations                   │            │
│  │  - Operation workarounds                     │            │
│  │  - Capability overrides                      │            │
│  └─────────────────────────────────────────────┘            │
└─────────────────────────────────────────────────────────────┘
```

## Schema Location

The schema is available at:

- Source: `Specs/quirks.schema.json`
- Full quirks database: `Specs/quirks.json`

## Root Schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "https://swiftmtp.org/quirks.schema.json",
  "title": "SwiftMTP Device Quirks",
  "description": "Configuration for device-specific MTP behavior",
  "type": "object",
  "required": ["version", "quirks"],
  "properties": {
    "version": {
      "type": "string",
      "description": "Schema version"
    },
    "quirks": {
      "type": "array",
      "description": "Array of device quirk configurations",
      "items": { "$ref": "#/definitions/quirk" }
    }
  }
}
```

## Quirks Definition

### Quirk Object

```json
{
  "$defs": {
    "quirk": {
      "type": "object",
      "required": ["vendorId", "productId", "name"],
      "properties": {
        "vendorId": {
          "$ref": "#/definitions/vendorId"
        },
        "productId": {
          "$ref": "#/definitions/productId"
        },
        "name": {
          "type": "string",
          "description": "Human-readable device name"
        },
        "description": {
          "type": "string",
          "description": "Detailed description"
        },
        "enabled": {
          "type": "boolean",
          "default": true,
          "description": "Whether quirk is active"
        },
        "transfer": {
          "$ref": "#/definitions/transferQuirks"
        },
        "operations": {
          "$ref": "#/definitions/operationQuirks"
        },
        "timeouts": {
          "$ref": "#/definitions/timeoutQuirks"
        },
        "workarounds": {
          "$ref": "#/definitions/workarounds"
        }
      }
    }
  }
}
```

## Field Reference

### vendorId

USB Vendor ID (decimal or hex).

```json
{
  "vendorId": {
    "type": ["integer", "string"],
    "description": "USB Vendor ID (decimal or 0xhex)",
    "examples": [
      18d1,
      "0x18d1",
      "Google"
    ],
    "pattern": "^((0x[0-9a-fA-F]+)|([0-9]+)|[A-Za-z]+)$"
  }
}
```

**Examples:**

```json
// Decimal
"vendorId": 18d1

// Hex string
"vendorId": "0x18d1"

// Named vendor
"vendorId": "Google"
```

---

### productId

USB Product ID (decimal or hex).

```json
{
  "productId": {
    "type": ["integer", "string"],
    "description": "USB Product ID (decimal or 0xhex)",
    "examples": [
      4ee1,
      "0x4ee1"
    ]
  }
}
```

**Examples:**

```json
// Specific product
"productId": 4ee1

// Any product from vendor
"productId": "*"
```

---

### transferQuirks

Transfer-specific configuration.

```json
{
  "$defs": {
    "transferQuirks": {
      "type": "object",
      "description": "Transfer behavior settings",
      "properties": {
        "useSendObject": {
          "type": "boolean",
          "default": true,
          "description": "Use SendObject instead of SendObjectInfo+SendObject"
        },
        "sendObjectAlign32": {
          "type": "boolean",
          "default": false,
          "description": "Align SendObject data to 32-byte boundary"
        },
        "chunkSize": {
          "type": "integer",
          "default": 65536,
          "description": "Transfer chunk size in bytes",
          "minimum": 4096,
          "maximum": 16777216
        },
        "maxParallel": {
          "type": "integer",
          "default": 3,
          "description": "Maximum parallel transfers",
          "minimum": 1,
          "maximum": 16
        },
        "bufferCount": {
          "type": "integer",
          "default": 16,
          "description": "Number of I/O buffers",
          "minimum": 1,
          "maximum": 64
        },
        "skipIntegrityCheck": {
          "type": "boolean",
          "default": false,
          "description": "Skip post-transfer verification"
        },
        "usePartialObject": {
          "type": "boolean",
          "default": true,
          "description": "Use GetPartialObject for resume"
        },
        "usePartialObject64": {
          "type": "boolean",
          "default": true,
          "description": "Prefer 64-bit partial object (large files)"
        }
      }
    }
  }
}
```

**Example:**

```json
{
  "vendorId": "Google",
  "productId": 4ee1,
  "name": "Google Pixel 7",
  "transfer": {
    "chunkSize": 262144,
    "maxParallel": 4,
    "useSendObject": true,
    "usePartialObject64": true
  }
}
```

---

### operationQuirks

Operation-specific overrides.

```json
{
  "$defs": {
    "operationQuirks": {
      "type": "object",
      "description": "Operation behavior overrides",
      "properties": {
        "supportedOperations": {
          "type": "array",
          "items": { "type": "string" },
          "description": "Explicit list of supported operations"
        },
        "unsupportedOperations": {
          "type": "array",
          "items": { "type": "string" },
          "description": "Operations to disable"
        },
        "skipGetObjectHandles": {
          "type": "boolean",
          "default": false,
          "description": "Skip GetObjectHandles during listing"
        },
        "forceGetObjectInfo": {
          "type": "boolean",
          "default": false,
          "description": "Always fetch full object info"
        },
        "supportsDeleteObject": {
          "type": "boolean",
          "default": true,
          "description": "Device supports delete"
        },
        "supportsCreateFolder": {
          "type": "boolean",
          "default": true,
          "description": "Device supports folder creation"
        },
        "supportsRename": {
          "type": "boolean",
          "default": true,
          "description": "Device supports rename"
        }
      }
    }
  }
}
```

**Example:**

```json
{
  "vendorId": "Xiaomi",
  "productId": "*",
  "name": "Xiaomi Devices",
  "operations": {
    "unsupportedOperations": ["DeleteObject"],
    "skipGetObjectHandles": true,
    "forceGetObjectInfo": true
  }
}
```

---

### timeoutQuirks

Timeout configuration.

```json
{
  "$defs": {
    "timeoutQuirks": {
      "type": "object",
      "description": "Timeout settings",
      "properties": {
        "connectMs": {
          "type": "integer",
          "default": 10000,
          "description": "Connection timeout (ms)",
          "minimum": 1000,
          "maximum": 120000
        },
        "ioMs": {
          "type": "integer",
          "default": 30000,
          "description": "I/O operation timeout (ms)",
          "minimum": 5000,
          "maximum": 600000
        },
        "stabilizeMs": {
          "type": "integer",
          "default": 500,
          "description": "Post-operation stabilization (ms)",
          "minimum": 0,
          "maximum": 10000
        },
        "retryDelayMs": {
          "type": "integer",
          "default": 1000,
          "description": "Delay between retries (ms)",
          "minimum": 100,
          "maximum": 30000
        }
      }
    }
  }
}
```

**Example:**

```json
{
  "vendorId": "Samsung",
  "productId": "*",
  "name": "Samsung Devices",
  "timeouts": {
    "ioMs": 60000,
    "stabilizeMs": 1000,
    "retryDelayMs": 2000
  }
}
```

---

### workarounds

Special behavior workarounds.

```json
{
  "$defs": {
    "workarounds": {
      "type": "object",
      "description": "Device-specific workarounds",
      "properties": {
        "brokenGetObjectHandles": {
          "type": "boolean",
          "default": false,
          "description": "GetObjectHandles returns incomplete results"
        },
        "brokenObjectInfo": {
          "type": "boolean",
          "default": false,
          "description": "GetObjectInfo returns incorrect data"
        },
        "sendObjectNeedsPadding": {
          "type": "boolean",
          "default": false,
          "description": "SendObject data needs zero-padding"
        },
        "noEmptyTransferMode": {
          "type": "boolean",
          "default": false,
          "description": "Cannot send zero-length files"
        },
        "needsObjectIdRefresh": {
          "type": "boolean",
          "default": false,
          "description": "Must refresh object handles after write"
        },
        "lazyStorageDetection": {
          "type": "boolean",
          "default": false,
          "description": "Defer storage detection"
        },
        "crashOnEvent": {
          "type": "boolean",
          "default": false,
          "description": "Device crashes on event subscription"
        },
        "wontSyncTimestamp": {
          "type": "boolean",
          "default": false,
          "description": "Cannot set file timestamps"
        }
      }
    }
  }
}
```

**Example:**

```json
{
  "vendorId": "OnePlus",
  "productId": "0xf003",
  "name": "OnePlus 3T",
  "workarounds": {
    "brokenGetObjectHandles": true,
    "needsObjectIdRefresh": true,
    "lazyStorageDetection": true
  }
}
```

## Complete Example

Here's a complete quirks entry:

```json
{
  "version": "1.0.0",
  "quirks": [
    {
      "vendorId": "Google",
      "productId": 4ee1,
      "name": "Google Pixel 7",
      "description": "Google Pixel 7 and 7 Pro",
      "enabled": true,
      "transfer": {
        "useSendObject": true,
        "sendObjectAlign32": true,
        "chunkSize": 262144,
        "maxParallel": 4,
        "usePartialObject64": true
      },
      "operations": {
        "supportsDeleteObject": true,
        "supportsCreateFolder": true
      },
      "timeouts": {
        "ioMs": 30000,
        "stabilizeMs": 500
      },
      "workarounds": {}
    },
    {
      "vendorId": "Samsung",
      "productId": "*",
      "name": "Samsung Devices",
      "description": "Generic Samsung Android devices",
      "enabled": true,
      "transfer": {
        "useSendObject": true,
        "chunkSize": 131072,
        "maxParallel": 3,
        "usePartialObject": true
      },
      "operations": {
        "unsupportedOperations": ["DeleteObject"]
      },
      "timeouts": {
        "ioMs": 60000,
        "stabilizeMs": 1000,
        "retryDelayMs": 2000
      },
      "workarounds": {
        "needsObjectIdRefresh": true,
        "lazyStorageDetection": true
      }
    },
    {
      "vendorId": "Xiaomi",
      "productId": "0xff10",
      "name": "Xiaomi Mi Note 2",
      "description": "Xiaomi Mi Note 2 (Japan)",
      "enabled": true,
      "transfer": {
        "useSendObject": false,
        "chunkSize": 65536,
        "maxParallel": 2,
        "skipIntegrityCheck": false
      },
      "operations": {
        "skipGetObjectHandles": true,
        "forceGetObjectInfo": true,
        "supportsDeleteObject": false
      },
      "timeouts": {
        "ioMs": 45000,
        "stabilizeMs": 800
      },
      "workarounds": {
        "brokenGetObjectHandles": true,
        "noEmptyTransferMode": true
      }
    }
  ]
}
```

## Validation

### Validating Quirks Files

```bash
# Validate using JSON Schema
swift run swiftmtp validate-quirks --schema Specs/quirks.schema.json

# Validate quirks file
swift run swiftmtp validate-quirks Specs/quirks.json

# Output example:
# ✅ quirks.json is valid (12 quirks defined)
```

### Programmatic Validation

```swift
import Foundation
import SwiftyJSON

struct QuirksValidator {
    enum ValidationError: Error {
        case invalidJSON(String)
        case schemaViolation(String)
        case missingRequiredField(String)
    }
    
    static func validate(_ data: Data) throws {
        guard let json = try? JSON(data: data) else {
            throw ValidationError.invalidJSON("Invalid JSON format")
        }
        
        // Check required fields
        guard json["version"].exists() else {
            throw ValidationError.missingRequiredField("version")
        }
        
        guard json["quirks"].exists() else {
            throw ValidationError.missingRequiredField("quirks")
        }
        
        // Validate each quirk
        for (index, quirk) in json["quirks"].arrayValue.enumerated() {
            try validateQuirk(quirk, index: index)
        }
    }
    
    private static func validateQuirk(_ quirk: JSON, index: Int) throws {
        // Validate required fields
        guard quirk["vendorId"].exists() else {
            throw ValidationError.missingRequiredField("quirks[\(index)].vendorId")
        }
        
        guard quirk["productId"].exists() else {
            throw ValidationError.missingRequiredField("quirks[\(index)].productId")
        }
        
        guard quirk["name"].exists() else {
            throw ValidationError.missingRequiredField("quirks[\(index)].name")
        }
    }
}
```

## Related Documentation

- [Device Quirks Explained](../explanation/device-quirks.md) - How quirks work
- [Adding Device Support](../howto/add-device-support.md) - Creating new quirks
- [Device Quirks Configuration](../howto/device-quirks.md) - Managing quirks
- [Submission Schema](../reference/submission-schema.md) - Submitting quirks

## Summary

This reference covers:

- ✅ Root schema structure
- ✅ Vendor and product ID formats
- ✅ Transfer quirks (chunk size, parallelism)
- ✅ Operation quirks (capability overrides)
- ✅ Timeout configuration
- ✅ Workaround flags
- ✅ Complete examples
- ✅ Validation methods
