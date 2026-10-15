//
//  Cemeteries.swift
//  City Cemetery
//
//  Every burial ground inside Salt Lake City, and where its records live.
//  Two have parcel-level maps (the city's and Mount Olivet's ArcGIS layers),
//  five report to the state burials database, Fort Douglas is in the VA
//  locator, and seven private grounds keep their books to themselves.
//

import Foundation
import CoreLocation

/// Where a cemetery's names come from.
enum RecordSource: Hashable, Codable {
    /// A Spatial Generations ArcGIS layer set — polygons for every grave.
    case arcgis(ArcGISConfig)
    /// The Utah state burials database, filtered by this cemetery-name substring.
    case state(String)
    /// The VA Nationwide Gravesite Locator, by cemetery code.
    case va(String)
    /// No public records; directory entry only.
    case none

    var isMapped: Bool { if case .arcgis = self { return true } else { return false } }
    var hasRecords: Bool { if case .none = self { return false } else { return true } }
}

struct Entrance: Hashable, Codable {
    let name: String
    let coordinate: Coordinate
}

struct Cemetery: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let shortName: String
    let address: String
    let phone: String?
    let website: URL?
    let coordinate: Coordinate
    let established: Int?
    let acres: Int?
    /// Burials on record, rounded the way it will be printed.
    let burials: String?
    let owner: String
    let blurb: String
    let source: RecordSource
    /// Names for each `_`-separated level of the plot string.
    let plotLevels: [String]
    let entrances: [Entrance]
    /// The state database spells it this way.
    let stateName: String?

    var findAGraveURL: URL {
        var c = URLComponents(string: "https://www.findagrave.com/cemetery-browse")!
        c.queryItems = [URLQueryItem(name: "cemetery-name", value: name),
                        URLQueryItem(name: "location", value: "Salt Lake City, Salt Lake County, Utah, United States of America")]
        return c.url!
    }

    func findAGraveSearch(_ q: NameQuery) -> URL {
        var c = URLComponents(string: "https://www.findagrave.com/memorial/search")!
        c.queryItems = [URLQueryItem(name: "firstname", value: q.first),
                        URLQueryItem(name: "lastname", value: q.last),
                        URLQueryItem(name: "location", value: "Salt Lake City, Salt Lake County, Utah, United States of America"),
                        URLQueryItem(name: "locationId", value: "city_22713")]
        return c.url!
    }

    func nearestEntrance(to c: CLLocationCoordinate2D) -> Entrance? {
        let here = CLLocation(latitude: c.latitude, longitude: c.longitude)
        return entrances.min { a, b in
            CLLocation(latitude: a.coordinate.lat, longitude: a.coordinate.lon).distance(from: here) <
            CLLocation(latitude: b.coordinate.lat, longitude: b.coordinate.lon).distance(from: here)
        }
    }
}

enum Cemeteries {
    static let slc = "slc"
    static let mountOlivet = "mtolivet"

    static let all: [Cemetery] = [
        Cemetery(
            id: slc,
            name: "Salt Lake City Cemetery",
            shortName: "City Cemetery",
            address: "200 N Street, Salt Lake City, UT 84103",
            phone: "(801) 596-5020",
            website: URL(string: "https://www.slc.gov/cemetery/"),
            coordinate: Coordinate(40.77718, -111.85981),
            established: 1847,
            acres: 120,
            burials: "124,000",
            owner: "Salt Lake City Corporation",
            blurb: "Brigham Young's burying ground for the valley, and still the largest city-run cemetery in the country: 120 acres and nine and a half miles of road in the Avenues. Every grave is mapped to the foot.",
            source: .arcgis(.saltLakeCity),
            plotLevels: ["Plat", "Block", "Lot", "Grave"],
            entrances: [
                Entrance(name: "Main gate, N Street & 4th Avenue", coordinate: Coordinate(40.77400, -111.86389)),
                Entrance(name: "240 N Street", coordinate: Coordinate(40.77479, -111.86408)),
                Entrance(name: "270 N Street / Grand Avenue", coordinate: Coordinate(40.77562, -111.86407)),
                Entrance(name: "280 N Street", coordinate: Coordinate(40.77600, -111.86408)),
                Entrance(name: "350 N Street / 7th Avenue", coordinate: Coordinate(40.77734, -111.86411)),
                Entrance(name: "Center Street / 11th Avenue", coordinate: Coordinate(40.78046, -111.85980)),
                Entrance(name: "275 N / U Street", coordinate: Coordinate(40.77574, -111.85365)),
                Entrance(name: "925 E / 11th Avenue", coordinate: Coordinate(40.78086, -111.86215)),
            ],
            stateName: "Salt Lake City Cemetery"),

        Cemetery(
            id: mountOlivet,
            name: "Mount Olivet Cemetery",
            shortName: "Mount Olivet",
            address: "1342 E 500 South, Salt Lake City, UT 84102",
            phone: "(801) 582-2552",
            website: URL(string: "https://www.mountolivetcemetery.org/"),
            coordinate: Coordinate(40.75586, -111.85009),
            established: 1874,
            acres: 80,
            burials: "36,000",
            owner: "Independent, chartered by Congress",
            blurb: "The only cemetery in the country created by an act of Congress, on land carved from Camp Douglas in 1874 and open to all faiths. Across from Rice-Eccles Stadium; every grave is mapped.",
            source: .arcgis(.mountOlivet),
            plotLevels: ["Section", "Lot", "Grave"],
            entrances: [
                Entrance(name: "Main gate, 500 South", coordinate: Coordinate(40.75852, -111.85008)),
            ],
            stateName: "Mount Olivet Cemetery"),

        Cemetery(
            id: "fortdouglas",
            name: "Fort Douglas Post Cemetery",
            shortName: "Fort Douglas",
            address: "405 Chipeta Way, Salt Lake City, UT 84108",
            phone: "(202) 632-8035",
            website: URL(string: "https://www.cem.va.gov/cems/lots/FortDouglas.asp"),
            coordinate: Coordinate(40.76030, -111.82412),
            established: 1863,
            acres: nil,
            burials: "1,350",
            owner: "U.S. Department of Veterans Affairs",
            blurb: "The post cemetery of Camp Douglas, laid out in 1863 for the California Volunteers and holding soldiers of every war since, plus German prisoners of the First World War. Closed to new burials; records in the VA's national locator.",
            source: .va("N957"),
            plotLevels: ["Section", "Site"],
            entrances: [],
            stateName: "Fort Douglas"),

        Cemetery(
            id: "mtcalvary",
            name: "Mount Calvary Catholic Cemetery",
            shortName: "Mount Calvary",
            address: "275 N U Street, Salt Lake City, UT 84103",
            phone: "(801) 355-2476",
            website: URL(string: "https://dioslc.org/mount-calvary-cemetery"),
            coordinate: Coordinate(40.77572, -111.85507),
            established: 1897,
            acres: nil,
            burials: "9,000",
            owner: "Catholic Diocese of Salt Lake City",
            blurb: "The diocese's cemetery and mausoleum on the east edge of the Avenues, consecrated in 1897. Burial records are in the state database; the office places the grave.",
            source: .state("Mount Calvary"),
            plotLevels: ["Plot"],
            entrances: [],
            stateName: "Mount Calvary Catholic Cemetery"),

        Cemetery(
            id: "elysian",
            name: "Elysian Burial Gardens",
            shortName: "Elysian Gardens",
            address: "1075 E 4580 South, Salt Lake City, UT 84117",
            phone: nil,
            website: nil,
            coordinate: Coordinate(40.67178, -111.85879),
            established: 1870,
            acres: nil,
            burials: "1,250",
            owner: "Elysian Burial Gardens Association",
            blurb: "A small association cemetery on 4580 South with a Salt Lake City mailing address, in use since 1870. Its burial register is in the state database.",
            source: .state("Elysian"),
            plotLevels: ["Plot"],
            entrances: [],
            stateName: "Elysian Burial Gardens"),

        Cemetery(
            id: "brighamyoung",
            name: "Brigham Young Family Cemetery",
            shortName: "Brigham Young Cemetery",
            address: "140 E 1st Avenue, Salt Lake City, UT 84103",
            phone: nil,
            website: nil,
            coordinate: Coordinate(40.77126, -111.88774),
            established: 1877,
            acres: nil,
            burials: "11",
            owner: "The Church of Jesus Christ of Latter-day Saints",
            blurb: "The Mormon Pioneer Memorial: Brigham Young's grave and a handful of his family, in a walled garden a block east of the temple.",
            source: .state("Brigham Young"),
            plotLevels: ["Plot"],
            entrances: [],
            stateName: "Brigham Young Cemetery"),

        Cemetery(
            id: "kimballwhitney",
            name: "Kimball-Whitney Cemetery",
            shortName: "Kimball-Whitney",
            address: "180 N Main Street, Salt Lake City, UT 84103",
            phone: nil,
            website: nil,
            coordinate: Coordinate(40.77282, -111.88949),
            established: 1848,
            acres: nil,
            burials: "56",
            owner: "The Church of Jesus Christ of Latter-day Saints",
            blurb: "Heber C. Kimball's family plot, the first burials in the valley after the pioneers arrived, tucked behind the buildings on North Main.",
            source: .state("Kimball"),
            plotLevels: ["Plot"],
            entrances: [],
            stateName: "Kimball-Whitney Cemetery"),

        Cemetery(
            id: "bnai",
            name: "B'nai Israel Cemetery",
            shortName: "B'nai Israel",
            address: "4th Avenue at Cypress Avenue, Salt Lake City, UT 84103",
            phone: nil,
            website: nil,
            coordinate: Coordinate(40.77458, -111.85908),
            established: 1869,
            acres: nil,
            burials: nil,
            owner: "Congregation Kol Ami",
            blurb: "The Reform congregation's ground inside the city cemetery's south edge, the oldest of the three Jewish cemeteries on the Avenues.",
            source: .none,
            plotLevels: ["Plot"],
            entrances: [],
            stateName: nil),

        Cemetery(
            id: "montefiore",
            name: "Montefiore Cemetery",
            shortName: "Montefiore",
            address: "1081 E 4th Avenue, Salt Lake City, UT 84103",
            phone: nil,
            website: nil,
            coordinate: Coordinate(40.77422, -111.85721),
            established: 1899,
            acres: nil,
            burials: nil,
            owner: "Congregation Kol Ami",
            blurb: "Congregation Montefiore's cemetery beside B'nai Israel on 4th Avenue, the Orthodox counterpart until the congregations merged.",
            source: .none,
            plotLevels: ["Plot"],
            entrances: [],
            stateName: nil),

        Cemetery(
            id: "shaare",
            name: "Shaare Tzedek Cemetery",
            shortName: "Shaare Tzedek",
            address: "915 E 11th Avenue, Salt Lake City, UT 84103",
            phone: nil,
            website: nil,
            coordinate: Coordinate(40.78140, -111.86132),
            established: 1915,
            acres: nil,
            burials: nil,
            owner: "Congregation Shaarey Tzedek",
            blurb: "The Orthodox congregation's cemetery on the north edge of the city cemetery, along 11th Avenue.",
            source: .none,
            plotLevels: ["Plot"],
            entrances: [],
            stateName: nil),

        Cemetery(
            id: "larkin",
            name: "Larkin Sunset Lawn",
            shortName: "Larkin Sunset Lawn",
            address: "2350 E 1300 South, Salt Lake City, UT 84108",
            phone: nil,
            website: URL(string: "https://www.larkinmortuary.com/"),
            coordinate: Coordinate(40.74134, -111.82361),
            established: 1920,
            acres: nil,
            burials: nil,
            owner: "Larkin Mortuary",
            blurb: "Larkin's memorial park on 1300 South below the foothills, opened in 1920. Its records are private; the mortuary office places graves.",
            source: .none,
            plotLevels: ["Plot"],
            entrances: [],
            stateName: nil),

        Cemetery(
            id: "wasatchlawn",
            name: "Wasatch Lawn Memorial Park",
            shortName: "Wasatch Lawn",
            address: "3401 S Highland Drive, Salt Lake City, UT 84106",
            phone: nil,
            website: URL(string: "https://www.dignitymemorial.com/"),
            coordinate: Coordinate(40.69756, -111.84243),
            established: 1912,
            acres: nil,
            burials: "30,000",
            owner: "Service Corporation International",
            blurb: "The big lawn-plan park on Highland Drive, in use since 1912 and run by Dignity Memorial. Its records are private.",
            source: .none,
            plotLevels: ["Plot"],
            entrances: [],
            stateName: nil),

        Cemetery(
            id: "cityview",
            name: "City View Memoriam",
            shortName: "City View",
            address: "1001 11th Avenue, Salt Lake City, UT 84103",
            phone: nil,
            website: nil,
            coordinate: Coordinate(40.78071, -111.85937),
            established: nil,
            acres: nil,
            burials: nil,
            owner: "Private",
            blurb: "The mausoleum and mortuary on 11th Avenue at the top of the city cemetery. Crypt records are private.",
            source: .none,
            plotLevels: ["Plot"],
            entrances: [],
            stateName: nil),

        Cemetery(
            id: "stmarks",
            name: "St. Mark's Cathedral Columbarium",
            shortName: "St. Mark's",
            address: "231 E 100 South, Salt Lake City, UT 84111",
            phone: nil,
            website: URL(string: "https://www.stmarkscathedral-slc.org/"),
            coordinate: Coordinate(40.76774, -111.88424),
            established: nil,
            acres: nil,
            burials: nil,
            owner: "Episcopal Diocese of Utah",
            blurb: "The Episcopal cathedral's columbarium downtown. Records are kept by the parish.",
            source: .none,
            plotLevels: ["Plot"],
            entrances: [],
            stateName: nil),
    ]

    static let byID: [String: Cemetery] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static var mapped: [Cemetery] { all.filter { $0.source.isMapped } }
    static var withRecords: [Cemetery] { all.filter { $0.source.hasRecords } }
}
