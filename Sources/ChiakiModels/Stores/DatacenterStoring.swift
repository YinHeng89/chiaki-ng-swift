/// Where the cloud datacenter measurements are persisted; the only writer of them.
public protocol DatacenterStoring: Sendable {
    /// Loads a service's measurements.
    ///
    /// - Parameter service: The cloud service.
    /// - Returns: The measurements, fastest first.
    /// - Throws: ``DatacenterStoreFailure/unavailable`` when the store cannot be read.
    func measurements(for service: CloudService) throws(DatacenterStoreFailure) -> [DatacenterMeasurement]

    /// Replaces a service's measurements with the ones it keeps, in one transaction.
    ///
    /// - Parameters:
    ///   - measurements: The new measurements; invalid names are dropped and at most
    ///     ``DatacenterMeasurement/maximumPerService`` are kept.
    ///   - service: The cloud service.
    /// - Throws: ``DatacenterStoreFailure/unavailable`` when the write failed.
    func save(_ measurements: [DatacenterMeasurement],
              for service: CloudService) throws(DatacenterStoreFailure)
}

/// Why the datacenter store could not do what was asked.
public enum DatacenterStoreFailure: Error, Hashable, Sendable {
    /// The store could not be read or written.
    case unavailable
}
