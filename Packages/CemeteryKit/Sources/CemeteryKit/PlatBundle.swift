//
//  PlatBundle.swift
//  City Cemetery
//
//  The plat shipped with the app: boundary, plats, blocks, lots and the
//  furniture for each mapped cemetery, fetched by Tools/gen_plats.py and
//  stored as raw-DEFLATE JSON. It draws the map before the network answers
//  and keeps drawing it with no signal. Graves are never bundled; they
//  change weekly and stay live.
//

import Foundation
import CoreLocation

enum PlatBundle {
    struct File: Decodable {
        struct Poly: Decodable {
            let id: Int
            let l: String?
            let r: [Double]
        }
        let generated: String
        let layers: [String: [Poly]]
    }

    /// Decoded off the main thread; a few hundred milliseconds for the city.
    nonisolated static func load(cemeteryID: String) -> (generated: String, layers: [PlatLayer: [MapPoly]])? {
        guard let url = Bundle.module.url(forResource: cemeteryID, withExtension: "plat"),
              let packed = try? Data(contentsOf: url),
              let data = try? (packed as NSData).decompressed(using: .zlib) as Data,
              let file = try? JSONDecoder().decode(File.self, from: data) else { return nil }
        var out: [PlatLayer: [MapPoly]] = [:]
        for (name, polys) in file.layers {
            guard let layer = PlatLayer(rawValue: name) else { continue }
            out[layer] = polys.compactMap { p in
                guard p.r.count >= 6 else { return nil }
                var ring: [CLLocationCoordinate2D] = []
                ring.reserveCapacity(p.r.count / 2)
                var i = 0
                while i + 1 < p.r.count {
                    ring.append(CLLocationCoordinate2D(latitude: p.r[i], longitude: p.r[i + 1]))
                    i += 2
                }
                return MapPoly(id: p.id, layer: layer, label: p.l, ring: ring, bbox: BBox(ring), record: nil)
            }
        }
        return (file.generated, out)
    }
}
