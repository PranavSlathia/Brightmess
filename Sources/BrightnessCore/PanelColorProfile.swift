// Adapted from SaintD1smas/TrueTone (MIT). See NOTICE.
import Foundation

/// The external panel's actual colour primaries, read from its EDID.
///
/// The first version computed channel gains with a hardcoded sRGB matrix. The Mi
/// is wide-gamut (green sits at 0.257/0.675, nowhere near sRGB's 0.300/0.600), so
/// those gains cut green and blue harder than the target white point actually
/// needs — the screen came out warmer than asked, by ~2 % at a 6000 K target and
/// ~9 % at 4500 K. Using the panel's own matrix removes that bias.
public struct PanelColorProfile: Sendable {
    /// XYZ → linear RGB for this panel.
    public let xyzToRGB: [[Double]]
    /// The panel's native white point, in Kelvin (from EDID).
    public let nativeCCT: Double

    public static let sRGB = PanelColorProfile(
        xyzToRGB: [[ 3.2406, -1.5372, -0.4986],
                   [-0.9689,  1.8758,  0.0415],
                   [ 0.0557, -0.2040,  1.0570]],
        nativeCCT: 6504)

    // MARK: build from primaries

    private init(xyzToRGB: [[Double]], nativeCCT: Double) {
        self.xyzToRGB = xyzToRGB
        self.nativeCCT = nativeCCT
    }

    public init?(rx: Double, ry: Double, gx: Double, gy: Double,
          bx: Double, by: Double, wx: Double, wy: Double) {
        guard [rx,ry,gx,gy,bx,by,wx,wy].allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              ry > 0, gy > 0, by > 0, wy > 0 else { return nil }
        let m = [[rx / ry, gx / gy, bx / by],
                 [1.0, 1.0, 1.0],
                 [(1 - rx - ry) / ry, (1 - gx - gy) / gy, (1 - bx - by) / by]]
        guard let mInv = Self.invert(m) else { return nil }
        let w = [wx / wy, 1.0, (1 - wx - wy) / wy]
        let s = (0..<3).map { i in (0..<3).map { j in mInv[i][j] * w[j] }.reduce(0, +) }
        let rgbToXYZ = (0..<3).map { r in (0..<3).map { c in m[r][c] * s[c] } }
        guard let inv = Self.invert(rgbToXYZ), inv.flatMap({ $0 }).allSatisfy(\.isFinite) else { return nil }

        // McCamy's approximation for the white point's CCT
        let n = (wx - 0.3320) / (0.1858 - wy)
        let cct = 449 * n * n * n + 3525 * n * n + 6823.3 * n + 5520.33

        self.xyzToRGB = inv
        self.nativeCCT = (4000...9000).contains(cct) ? cct : 6504
    }

    private static func invert(_ m: [[Double]]) -> [[Double]]? {
        let det = m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
                - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
                + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0])
        guard abs(det) > 1e-9 else { return nil }
        func cofactor(_ r: Int, _ c: Int) -> Double {
            let rs = [0, 1, 2].filter { $0 != r }, cs = [0, 1, 2].filter { $0 != c }
            let s = m[rs[0]][cs[0]] * m[rs[1]][cs[1]] - m[rs[0]][cs[1]] * m[rs[1]][cs[0]]
            return (r + c) % 2 == 0 ? s : -s
        }
        return (0..<3).map { r in (0..<3).map { c in cofactor(c, r) / det } }
    }

}
