# ChiakiStoreAdapters

The C++ store adapters that let chiaki-ng-core read and write its persistent state through the app's Swift
repositories.

## Overview

The core declares its persistence as abstract C++ store interfaces. Swift cannot subclass a C++ class, so
this C++ target implements those interfaces and forwards every call to Swift types from `ChiakiPersistence`,
which it reaches through the generated `ChiakiPersistence-Swift.h` header. SQLite stays the single source of
truth, and the core never opens the database itself.

- `ConsoleStoreAdapter` stores consoles and their pairings.
- `CredentialStoreAdapter` stores account credentials, carried as the core's wiping secret strings.
- `DatacenterStoreAdapter` stores cloud datacenter measurements.
- `DeviceStoreAdapter` stores remembered Kakusan devices.

`StoreAdapters.hpp` is the public header. `ChiakiCoreBridge` creates all four adapters over one Swift store
gateway when it opens the core.

The target holds no Swift, so it has no symbol documentation. Its headers follow the project's no-comment
rule, and this article is its only documentation.
