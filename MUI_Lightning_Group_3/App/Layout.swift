//
//  Layout.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import RealityKit
import simd

/// Every placement in the room in one place. Units: metres.
///
/// Two coordinate spaces are used:
/// - **Immersive space** (world): origin on the floor below where the visitor stood when the
///   experience started; +y up, −z forward (away from the visitor).
/// - **Model space**: origin at the centre of the landscape's base plate, same axes.
///   Everything that belongs to the landscape (cloud, sun, labels, dashboard) is placed here,
///   so moving `modelPosition` moves the whole installation.
enum Layout {
    /// Fallback position of the model (only used without world tracking, e.g. in the simulator).
    /// On the device the physical model is placed once and found again via a room anchor,
    /// the virtual landscape appears in front of the viewer.
    static let modelPosition: SIMD3<Float> = [0, 0.9, -1.2]

    /// Virtual landscape / first guess when placing: distance in front of the viewer and how
    /// far below eye level the model's base is.
    static let viewerDistance: Float = 0.9
    static let baseBelowEyes: Float = 0.6

    /// Base of the main storm cloud (model space).
    static let cloudBase: SIMD3<Float> = [0.05, 0.45, -0.06]

    // MARK: - Physical model: how it is found and masked

    /// Object tracking from a trained `LandscapeModel.referenceobject`. Off: training takes
    /// ~8 h – the model is lined up by hand once (calibration box) and found again via a room anchor.
    static let useObjectTracking = false
    /// Invisible mask in the shape of the model that hides rain, clouds and the room darkening
    /// behind the real slices. Off: hand alignment is never millimetre-exact, and a mask that is
    /// a little off shows hard edges. The darkening uses a soft gradient instead (SkyDimmer).
    static let useOcclusionMask = false

    // MARK: - Scan / object tracking (only used when `useObjectTracking` is on)

    /// Where the model's origin (centre of the footprint, bottom of the slices, front = +z) sits
    /// in the scan's coordinates (the scan's origin = what object tracking reports).
    /// LandscapeScan.usdz was registered to the slice data, rescaled to the measured size (41 × 42.5 × 18 cm) and moved into
    /// model space, so its origin already is the model origin: identity.
    static let scanAlignment = Transform(scale: .one,
                                         rotation: simd_quatf(angle: 0, axis: [0, 1, 0]),
                                         translation: [0, 0, 0])
    /// How strongly new tracking poses correct the model (0…1 per update) – lower = steadier.
    static let trackingSmoothing: Float = 0.15

    // MARK: - The laser-cut model (see Tools/bake_terrain.py) – 41 × 42 × 18 cm

    /// Distance between two neighbouring slices, centre to centre (board + 5 mm gap).
    /// Measured from the scan: 7.0 mm (front slice to back slice ≈ 42 cm).
    static let slicePitch: Float = 0.0070
    /// true: slice 01 is the one nearest to the visitor. The scan shows slice 01 at the back.
    static let firstSliceAtFront = false
    /// true: the numbered end of each slice (the engraved number) points to the visitor's left.
    static let numberSideOnLeft = true

    /// The dashboard (model space). Placed in front of the plinth, below the model's base,
    /// so it never covers the landscape: storm-energy bar, sun instruction, after-strike choice
    /// and the control buttons below them. y < 0 = below the bottom of the slices; z = a few cm
    /// in front of the front slice (the model is 42 cm deep, so the front is at z ≈ 0.21).
    /// One spot for all UI – change it here.
    static let dashboard: SIMD3<Float> = [0, -0.22, 0.25]
}
