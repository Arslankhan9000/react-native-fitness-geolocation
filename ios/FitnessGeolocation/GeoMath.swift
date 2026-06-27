import Foundation

/// Shared geo primitives — O(n) ray-cast, O(1) bbox reject. Used by polygon geofences.
enum GeoMath {
  struct Point { let lat: Double; let lng: Double }

  /// Ray-casting point-in-polygon. Vertices as (lat, lng) pairs, closed or open ring.
  static func pointInPolygon(lat: Double, lng: Double, vertices: [Point]) -> Bool {
    let n = vertices.count
    guard n >= 3 else { return false }
    var inside = false
    var j = n - 1
    for i in 0..<n {
      let yi = vertices[i].lat, xi = vertices[i].lng
      let yj = vertices[j].lat, xj = vertices[j].lng
      if ((yi > lat) != (yj > lat)) &&
          (lng < (xj - xi) * (lat - yi) / (yj - yi + 1e-12) + xi) {
        inside.toggle()
      }
      j = i
    }
    return inside
  }

  static func boundingBox(_ vertices: [Point]) -> (minLat: Double, maxLat: Double, minLng: Double, maxLng: Double)? {
    guard !vertices.isEmpty else { return nil }
    var minLat = vertices[0].lat, maxLat = minLat
    var minLng = vertices[0].lng, maxLng = minLng
    for v in vertices.dropFirst() {
      minLat = min(minLat, v.lat); maxLat = max(maxLat, v.lat)
      minLng = min(minLng, v.lng); maxLng = max(maxLng, v.lng)
    }
    return (minLat, maxLat, minLng, maxLng)
  }

  static func inBoundingBox(lat: Double, lng: Double, box: (minLat: Double, maxLat: Double, minLng: Double, maxLng: Double)) -> Bool {
    lat >= box.minLat && lat <= box.maxLat && lng >= box.minLng && lng <= box.maxLng
  }

  static func parseVertices(_ raw: [[String: Any]]) -> [Point] {
    raw.compactMap { v in
      guard let lat = v["latitude"] as? Double, let lng = v["longitude"] as? Double else { return nil }
      return Point(lat: lat, lng: lng)
    }
  }
}
