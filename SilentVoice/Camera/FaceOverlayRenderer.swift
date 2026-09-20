import ARKit
import SceneKit
import UIKit

/// SceneKit callbacks can run off the main actor. The lock serializes callback
/// state with SwiftUI visibility changes; the tracker keeps the session delegate.
nonisolated final class FaceOverlayRenderer: NSObject, ARSCNViewDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = true
    private var isTracking = false
    private var invalidated = false
    private var overlays: [UUID: FaceOverlayGeometry] = [:]

    func setVisibility(enabled: Bool, isTracking: Bool) {
        lock.withLock {
            self.enabled = enabled
            self.isTracking = isTracking
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        lock.withLock {
            guard !invalidated, let face = anchor as? ARFaceAnchor,
                  let device = renderer.device,
                  let overlay = FaceOverlayGeometry(device: device) else { return nil }
            overlays.removeValue(forKey: face.identifier)?.node.removeFromParentNode()
            overlay.update(from: face)
            overlay.node.isHidden = !enabled || !isTracking || !face.isTracked
            overlays[face.identifier] = overlay
            return overlay.node
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        lock.withLock {
            guard !invalidated, let face = anchor as? ARFaceAnchor,
                  let overlay = overlays[face.identifier] else { return }
            overlay.update(from: face)
            overlay.node.isHidden = !enabled || !isTracking || !face.isTracked
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        lock.withLock {
            guard !invalidated else { return }
            // Also runs when no anchor update arrives, so a stop/interruption
            // or toggle cannot leave the last mesh visible indefinitely.
            for overlay in overlays.values {
                overlay.node.isHidden = !enabled || !isTracking || !overlay.isTracked
            }
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        lock.withLock {
            overlays.removeValue(forKey: anchor.identifier)?.node.removeFromParentNode()
        }
    }

    func invalidate() {
        lock.withLock {
            invalidated = true
            for overlay in overlays.values { overlay.node.removeFromParentNode() }
            overlays.removeAll()
        }
    }
}

/// Owned and accessed only under FaceOverlayRenderer's lock. Face-local geometry
/// inherits the anchor node's transform and ARSCNView's camera projection.
nonisolated private final class FaceOverlayGeometry {
    let node = SCNNode()
    private(set) var isTracked = false
    private let wireframe: ARSCNFaceGeometry
    private let occluder: ARSCNFaceGeometry
    private let points = SCNNode()
    private let pointMaterial = SCNMaterial()
    private var pointElement: SCNGeometryElement?
    private var vertexCount = 0

    init?(device: any MTLDevice) {
        guard let wireframe = ARSCNFaceGeometry(device: device),
              let occluder = ARSCNFaceGeometry(device: device) else { return nil }
        self.wireframe = wireframe
        self.occluder = occluder

        let occlusionMaterial = SCNMaterial()
        occlusionMaterial.colorBufferWriteMask = []
        occlusionMaterial.writesToDepthBuffer = true
        occlusionMaterial.readsFromDepthBuffer = true
        occluder.materials = [occlusionMaterial]
        // Recess the depth-only surface by half a millimetre to avoid fighting
        // with the visible lines/points while still hiding the far side.
        occluder.shaderModifiers = [.geometry: """
            #pragma body
            _geometry.position.xyz -= _geometry.normal * 0.0005;
            """]
        let occlusionNode = SCNNode(geometry: occluder)
        occlusionNode.renderingOrder = -1
        node.addChildNode(occlusionNode)

        let wireMaterial = SCNMaterial()
        wireMaterial.lightingModel = .constant
        wireMaterial.diffuse.contents = UIColor.cyan
        wireMaterial.transparency = 0.35
        wireMaterial.fillMode = .lines
        wireMaterial.readsFromDepthBuffer = true
        wireMaterial.writesToDepthBuffer = false
        wireframe.materials = [wireMaterial]
        let wireNode = SCNNode(geometry: wireframe)
        wireNode.renderingOrder = 1
        node.addChildNode(wireNode)

        pointMaterial.lightingModel = .constant
        pointMaterial.diffuse.contents = UIColor.cyan
        pointMaterial.transparency = 0.9
        pointMaterial.readsFromDepthBuffer = true
        pointMaterial.writesToDepthBuffer = false
        points.renderingOrder = 2
        node.addChildNode(points)
        node.isHidden = true
    }

    func update(from face: ARFaceAnchor) {
        isTracked = face.isTracked
        guard isTracked else { return }
        wireframe.update(from: face.geometry)
        occluder.update(from: face.geometry)

        let vertices = face.geometry.vertices
        if pointElement == nil || vertexCount != vertices.count {
            vertexCount = vertices.count
            let element = SCNGeometryElement(indices: vertices.indices.map { UInt32($0) },
                                             primitiveType: .point)
            element.pointSize = 0.001
            element.minimumPointScreenSpaceRadius = 1
            element.maximumPointScreenSpaceRadius = 1.5
            pointElement = element
        }
        guard let pointElement else { return }
        // Copy only vertex values, never retain the AR anchor or camera buffers.
        // Reuse indices, materials and nodes; all points use one draw geometry.
        let source = SCNGeometrySource(vertices: vertices.map { SCNVector3($0.x, $0.y, $0.z) })
        let geometry = SCNGeometry(sources: [source], elements: [pointElement])
        geometry.materials = [pointMaterial]
        points.geometry = geometry
    }
}
