/// Where this installation's Kakusan identity and remembered devices are persisted.
public protocol DeviceStoring: Sendable {
    /// Loads the identity.
    ///
    /// - Returns: The identity, or `nil` when none was created yet.
    /// - Throws: ``DeviceStoreFailure/unavailable`` when the store cannot be read or the seed does not decrypt.
    func identity() throws(DeviceStoreFailure) -> StoredDeviceIdentity?

    /// Saves the identity, replacing any earlier one.
    ///
    /// - Parameter identity: The identity.
    /// - Throws: ``DeviceStoreFailure/unavailable`` when the write failed.
    func save(_ identity: StoredDeviceIdentity) throws(DeviceStoreFailure)

    /// Loads every remembered device.
    ///
    /// - Returns: The devices in the order they were first saved.
    /// - Throws: ``DeviceStoreFailure/unavailable`` when the store cannot be read.
    func rememberedDevices() throws(DeviceStoreFailure) -> [RememberedDevice]

    /// Saves a device, updating the one with the same key.
    ///
    /// - Parameter device: The device.
    /// - Throws: ``DeviceStoreFailure/unavailable`` when the write failed.
    func save(_ device: RememberedDevice) throws(DeviceStoreFailure)

    /// Forgets a device.
    ///
    /// - Parameter key: The device's key.
    /// - Throws: ``DeviceStoreFailure/unavailable`` when the delete failed.
    func forget(_ key: DeviceIdentityKey) throws(DeviceStoreFailure)
}

/// Why the Kakusan device store could not do what was asked.
public enum DeviceStoreFailure: Error, Hashable, Sendable {
    /// The store could not be read or written.
    case unavailable
}
