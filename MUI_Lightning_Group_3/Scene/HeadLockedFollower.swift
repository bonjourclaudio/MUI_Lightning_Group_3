//
//  HeadLockedFollower.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import ARKit
import Foundation
import QuartzCore
import RealityKit
import simd

/// ARKit tracking for the whole app:
/// - the visitor's head position (cloud sorting, billboards, room dimmer, placement),
/// - **object tracking** of the physical model (from the scan: `LandscapeModel.referenceobject`),
/// - fallback: a saved room position of the model (`WorldAnchor`, placed by hand once).
@MainActor
final class HeadLockedFollower {
    let entity = Entity()

    private var session: ARKitSession?
    private var worldTracking: WorldTrackingProvider?
    private var objectTracking: ObjectTrackingProvider?
    private var anchorTask: Task<Void, Never>?
    private var objectTask: Task<Void, Never>?

    /// Reference object trained in Create ML from the scan, added to the app folder.
    static let referenceObjectName = "LandscapeModel"
    static var hasReferenceObject: Bool {
        Bundle.main.url(forResource: referenceObjectName, withExtension: "referenceobject") != nil
    }
    /// Called with every tracked pose of the physical model (pose of the scan's origin).
    var onObjectAnchor: ((simd_float4x4) -> Void)?
    var usesObjectTracking: Bool { objectTracking != nil }

    /// World-space head position (fallback if tracking is unavailable, e.g. in the simulator).
    private(set) var headPosition: SIMD3<Float> = [0, 1.55, 0]
    private var hasPose = false

    /// Called whenever visionOS reports where the saved model anchor is.
    var onModelAnchor: ((simd_float4x4) -> Void)?

    static let anchorKey = "MUI.modelAnchorID"
    static var hasSavedModel: Bool { UserDefaults.standard.string(forKey: anchorKey) != nil }
    private var savedAnchorID: UUID? {
        UserDefaults.standard.string(forKey: Self.anchorKey).flatMap(UUID.init(uuidString:))
    }

    var isTracking: Bool { worldTracking?.state == .running }

    func start(objectTracking wantsObject: Bool = true) async {
        guard session == nil else { return }
        var providers: [any DataProvider] = []
        if WorldTrackingProvider.isSupported {
            let world = WorldTrackingProvider()
            worldTracking = world
            providers.append(world)
        }
        if wantsObject, ObjectTrackingProvider.isSupported,
           let url = Bundle.main.url(forResource: Self.referenceObjectName, withExtension: "referenceobject") {
            do {
                let reference = try await ReferenceObject(from: url)
                let objects = ObjectTrackingProvider(referenceObjects: [reference])
                objectTracking = objects
                providers.append(objects)
            } catch {
                print("[Tracking] Could not load the reference object: \(error)")
            }
        }
        guard !providers.isEmpty else { return }
        let session = ARKitSession()
        self.session = session
        do {
            try await session.run(providers)
            if worldTracking != nil {
                anchorTask = Task { [weak self] in await self?.observeAnchors() }
            }
            if objectTracking != nil {
                objectTask = Task { [weak self] in await self?.observeObject() }
            }
        } catch {
            print("[Tracking] Tracking unavailable: \(error)")
            objectTracking = nil
        }
    }

    private func observeObject() async {
        guard let provider = objectTracking else { return }
        for await update in provider.anchorUpdates {
            guard !Task.isCancelled else { return }
            switch update.event {
            case .added, .updated:
                if update.anchor.isTracked { onObjectAnchor?(update.anchor.originFromAnchorTransform) }
            default:
                break
            }
        }
    }

    func stop() {
        anchorTask?.cancel()
        anchorTask = nil
        objectTask?.cancel()
        objectTask = nil
        objectTracking = nil
        session?.stop()
        session = nil
        worldTracking = nil
    }

    /// Current device (head) transform in world space, if tracked.
    func deviceTransform() -> simd_float4x4? {
        guard let provider = worldTracking, provider.state == .running,
              let device = provider.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) else { return nil }
        return device.originFromAnchorTransform
    }

    func update(dt: Float) {
        guard let m = deviceTransform() else { return }
        let position = SIMD3<Float>(m.columns.3.x, m.columns.3.y, m.columns.3.z)
        if !hasPose { headPosition = position }
        headPosition += (position - headPosition) * approachFactor(rate: 10, dt: dt)
        hasPose = true
    }

    // MARK: - Model anchor

    private func observeAnchors() async {
        guard let provider = worldTracking else { return }
        for await update in provider.anchorUpdates {
            guard !Task.isCancelled else { return }
            guard let id = savedAnchorID, update.anchor.id == id else { continue }
            switch update.event {
            case .added, .updated:
                if update.anchor.isTracked { onModelAnchor?(update.anchor.originFromAnchorTransform) }
            default:
                break
            }
        }
    }

    /// Stores the model's position in the room (replaces an earlier one).
    /// Returns false where world anchors aren't available (simulator).
    @discardableResult
    func saveModelAnchor(_ transform: simd_float4x4) async -> Bool {
        guard let provider = worldTracking, provider.state == .running else { return false }
        if let old = savedAnchorID {
            try? await provider.removeAnchor(forID: old)
        }
        let anchor = WorldAnchor(originFromAnchorTransform: transform)
        do {
            try await provider.addAnchor(anchor)
            UserDefaults.standard.set(anchor.id.uuidString, forKey: Self.anchorKey)
            return true
        } catch {
            print("[Tracking] Could not save the model position: \(error)")
            return false
        }
    }
}
