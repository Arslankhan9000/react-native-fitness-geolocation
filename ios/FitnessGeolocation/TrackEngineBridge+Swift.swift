import Foundation

// Swift-friendly wrapper over ObjC selector names.
// Avoids exposing `ingestLat(_:lng:accuracy:unixTimeS:speedMps:)` call-sites everywhere.
extension TrackEngineBridge {
  func ingest(
    lat: Double,
    lng: Double,
    accuracy: Double,
    unixTimeS: TimeInterval,
    speedMps: Double
  ) -> TEFixResult {
    ingestLat(lat, lng: lng, accuracy: accuracy, unixTimeS: unixTimeS, speedMps: speedMps)
  }
}

