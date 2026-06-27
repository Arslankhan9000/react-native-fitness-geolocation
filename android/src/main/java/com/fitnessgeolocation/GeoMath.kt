package com.fitnessgeolocation

/** Shared geo primitives — ray-cast O(n), bbox reject O(1). */
object GeoMath {
  data class Point(val lat: Double, val lng: Double)

  /** Ray-casting point-in-polygon (lat/lng vertices). */
  fun pointInPolygon(lat: Double, lng: Double, vertices: List<Point>): Boolean {
    val n = vertices.size
    if (n < 3) return false
    var inside = false
    var j = n - 1
    for (i in 0 until n) {
      val yi = vertices[i].lat; val xi = vertices[i].lng
      val yj = vertices[j].lat; val xj = vertices[j].lng
      if ((yi > lat) != (yj > lat) &&
        lng < (xj - xi) * (lat - yi) / (yj - yi + 1e-12) + xi
      ) inside = !inside
      j = i
    }
    return inside
  }

  fun boundingBox(vertices: List<Point>): DoubleArray? {
    if (vertices.isEmpty()) return null
    var minLat = vertices[0].lat; var maxLat = minLat
    var minLng = vertices[0].lng; var maxLng = minLng
    for (v in vertices.drop(1)) {
      minLat = minOf(minLat, v.lat); maxLat = maxOf(maxLat, v.lat)
      minLng = minOf(minLng, v.lng); maxLng = maxOf(maxLng, v.lng)
    }
    return doubleArrayOf(minLat, maxLat, minLng, maxLng)
  }

  fun inBoundingBox(lat: Double, lng: Double, box: DoubleArray): Boolean =
    lat in box[0]..box[1] && lng in box[2]..box[3]

  fun parseVertices(raw: List<Map<String, Any?>>): List<Point> =
    raw.mapNotNull { v ->
      val lat = (v["latitude"] as? Number)?.toDouble() ?: return@mapNotNull null
      val lng = (v["longitude"] as? Number)?.toDouble() ?: return@mapNotNull null
      Point(lat, lng)
    }

  /**
   * Haversine distance in meters.
   * Complexity: O(1)
   */
  fun haversineMeters(lat1: Double, lng1: Double, lat2: Double, lng2: Double): Double {
    val R = 6371000.0
    val dLat = Math.toRadians(lat2 - lat1)
    val dLon = Math.toRadians(lng2 - lng1)
    val a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) *
      Math.sin(dLon / 2) * Math.sin(dLon / 2)
    val c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
    return R * c
  }
}
