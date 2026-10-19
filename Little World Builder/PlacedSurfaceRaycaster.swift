import RealityKit
import simd

/// Refines the existing collision hit against visible triangles. Convex collision shapes are
/// suitable for selection, but can bridge a beach, valley, or slope in a multilevel island.
/// Geometry is cached in the placed root's coordinates, so root edits require no mesh rebuild.
final class PlacedSurfaceRaycaster {
    struct Hit {
        let position: SIMD3<Float>
        let normal: SIMD3<Float>
    }

    private struct Entry {
        weak var root: Entity?
        let mesh: SurfaceTriangleMesh
    }
    private var entries: [ObjectIdentifier: Entry] = [:]

    func prepare(_ root: Entity) {
        entries = entries.filter { $0.value.root?.parent != nil }
        let id = ObjectIdentifier(root)
        guard entries[id]?.root === root else {
            entries[id] = Entry(root: root, mesh: SurfaceTriangleMesh(root: root))
            return
        }
    }

    func hit(root: Entity, origin: SIMD3<Float>, direction: SIMD3<Float>) -> Hit? {
        prepare(root)
        let worldFromRoot = root.transformMatrix(relativeTo: nil)
        let determinant = simd_determinant(worldFromRoot)
        guard determinant.isFinite, determinant != 0 else { return nil }
        let rootFromWorld = simd_inverse(worldFromRoot)
        let localOrigin = rootFromWorld * SIMD4<Float>(origin, 1)
        let localDirection = rootFromWorld * SIMD4<Float>(direction, 0)
        guard let hit = entries[ObjectIdentifier(root)]?.mesh.hit(
            origin: SIMD3(localOrigin.x, localOrigin.y, localOrigin.z),
            direction: SIMD3(localDirection.x, localDirection.y, localDirection.z)) else { return nil }
        let position = worldFromRoot * SIMD4<Float>(hit.position, 1)
        let transformedNormal = simd_transpose(rootFromWorld) * SIMD4<Float>(hit.normal, 0)
        let normal = SIMD3(transformedNormal.x, transformedNormal.y, transformedNormal.z)
        let length = simd_length(normal)
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite,
              length.isFinite, length > 0 else { return nil }
        return Hit(position: SIMD3(position.x, position.y, position.z), normal: normal / length)
    }
}

/// A small bounding-volume tree avoids walking every triangle on each camera frame.
/// Neither support bounds nor convex-hit height participates in the returned surface point.
private final class SurfaceTriangleMesh {
    private struct Triangle {
        let a, b, c: SIMD3<Float>
        var minimum: SIMD3<Float> { simd_min(a, simd_min(b, c)) }
        var maximum: SIMD3<Float> { simd_max(a, simd_max(b, c)) }
        var center: SIMD3<Float> { (minimum + maximum) / 2 }

        func hit(origin: SIMD3<Float>, direction: SIMD3<Float>) -> (distance: Float, normal: SIMD3<Float>)? {
            let edge1 = b - a, edge2 = c - a
            let cross = simd_cross(direction, edge2)
            let determinant = simd_dot(edge1, cross)
            let magnitude = simd_length(edge1) * simd_length(edge2) * simd_length(direction)
            guard magnitude.isFinite, magnitude > 0,
                  abs(determinant) > magnitude * Float.ulpOfOne * 8 else { return nil }
            let inverse = 1 / determinant
            let offset = origin - a
            let u = simd_dot(offset, cross) * inverse
            let q = simd_cross(offset, edge1)
            let v = simd_dot(direction, q) * inverse
            guard u >= -0.00001, v >= -0.00001, u + v <= 1.00001 else { return nil }
            let distance = simd_dot(edge2, q) * inverse
            guard distance.isFinite, distance >= 0 else { return nil }
            var normal = simd_normalize(simd_cross(edge1, edge2))
            // Match a two-sided visible surface; the existing upward-normal policy still applies.
            if simd_dot(normal, direction) > 0 { normal = -normal }
            return (distance, normal)
        }
    }

    private final class Node {
        let minimum, maximum: SIMD3<Float>
        let triangles: [Triangle]
        let left, right: Node?

        init(_ triangles: [Triangle]) {
            let lower = triangles.reduce(SIMD3<Float>(repeating: .infinity)) { simd_min($0, $1.minimum) }
            let upper = triangles.reduce(SIMD3<Float>(repeating: -.infinity)) { simd_max($0, $1.maximum) }
            minimum = lower; maximum = upper
            if triangles.count <= 16 {
                self.triangles = triangles; left = nil; right = nil
            } else {
                let size = upper - lower
                let axis = size.x >= size.y && size.x >= size.z ? 0 : (size.y >= size.z ? 1 : 2)
                let sorted = triangles.sorted { $0.center[axis] < $1.center[axis] }
                let middle = sorted.count / 2
                self.triangles = []
                left = Node(Array(sorted[..<middle])); right = Node(Array(sorted[middle...]))
            }
        }

        func intersects(origin: SIMD3<Float>, direction: SIMD3<Float>, limit: Float) -> Bool {
            var near: Float = 0, far = limit
            for axis in 0..<3 {
                if direction[axis] == 0 {
                    if origin[axis] < minimum[axis] || origin[axis] > maximum[axis] { return false }
                } else {
                    let a = (minimum[axis] - origin[axis]) / direction[axis]
                    let b = (maximum[axis] - origin[axis]) / direction[axis]
                    near = max(near, min(a, b)); far = min(far, max(a, b))
                    if far < near { return false }
                }
            }
            return true
        }

        func hit(origin: SIMD3<Float>, direction: SIMD3<Float>, best: inout Float, normal: inout SIMD3<Float>?) {
            guard intersects(origin: origin, direction: direction, limit: best) else { return }
            for triangle in triangles {
                if let hit = triangle.hit(origin: origin, direction: direction), hit.distance < best {
                    best = hit.distance; normal = hit.normal
                }
            }
            left?.hit(origin: origin, direction: direction, best: &best, normal: &normal)
            right?.hit(origin: origin, direction: direction, best: &best, normal: &normal)
        }
    }

    private let tree: Node

    init(root: Entity) {
        var triangles: [Triangle] = []
        func appendGeometry(_ entity: Entity) {
            guard entity.isEnabled, entity.components[NonSelectableComponent.self] == nil else { return }
            if let component = entity.components[ModelComponent.self] as? ModelComponent {
                let contents = component.mesh.contents
                let rootFromEntity = entity.transformMatrix(relativeTo: root)
                for instance in contents.instances {
                    guard let model = contents.models.first(where: { $0.id == instance.model }) else { continue }
                    let matrix = rootFromEntity * instance.transform
                    for part in model.parts {
                        guard let indices = part.triangleIndices?.elements else { continue }
                        let positions = part.positions.elements.map { position -> SIMD3<Float> in
                            let point = matrix * SIMD4<Float>(position, 1)
                            return SIMD3(point.x, point.y, point.z)
                        }
                        for start in stride(from: 0, to: indices.count - indices.count % 3, by: 3) {
                            let a = Int(indices[start]), b = Int(indices[start + 1]), c = Int(indices[start + 2])
                            guard a < positions.count, b < positions.count, c < positions.count else { continue }
                            let triangle = Triangle(a: positions[a], b: positions[b], c: positions[c])
                            guard [triangle.a, triangle.b, triangle.c].allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else { continue }
                            triangles.append(triangle)
                        }
                    }
                }
            }
            for child in entity.children { appendGeometry(child) }
        }
        appendGeometry(root)
        tree = Node(triangles)
    }

    func hit(origin: SIMD3<Float>, direction: SIMD3<Float>) -> PlacedSurfaceRaycaster.Hit? {
        guard [origin, direction].allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }),
              simd_length_squared(direction) > 0 else { return nil }
        var distance = Float.infinity
        var normal: SIMD3<Float>?
        tree.hit(origin: origin, direction: direction, best: &distance, normal: &normal)
        guard let normal else { return nil }
        return .init(position: origin + direction * distance, normal: normal)
    }
}
