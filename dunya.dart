import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

// ── Gerçek gökbilimi (düşük hassasiyetli Meeus/NOAA formülleri) ──────────────
const double kTrBoylam = 35.0; // kamera çoğu zaman burayı (Türkiye) ortalar
const double kTrEnlem = 37.5;
const double kGeziPeriyot = 600.0; // her 10 dk'da bir...
const double kGeziSure = 45.0; // ...45 sn'lik bir tam tur (0 yaparsan hep Türkiye)
const double _rad = math.pi / 180.0;

double _jd(double ts) => ts / 86400.0 + 2440587.5;

double gmstRad(double ts) =>
    ((280.46061837 + 360.98564736629 * (_jd(ts) - 2451545.0)) % 360.0) * _rad;

class Cift {
  final double a;
  final double b;
  const Cift(this.a, this.b);
}

/// Güneşin ekvatoral konumu: (sağ açıklık, sapma) radyan.
Cift gunesKonum(double ts) {
  final n = _jd(ts) - 2451545.0;
  final l = (280.460 + 0.9856474 * n) % 360.0;
  final g = ((357.528 + 0.9856003 * n) % 360.0) * _rad;
  final lam = (l + 1.915 * math.sin(g) + 0.020 * math.sin(2 * g)) * _rad;
  final eps = (23.439 - 0.0000004 * n) * _rad;
  return Cift(math.atan2(math.cos(eps) * math.sin(lam), math.cos(lam)),
      math.asin(math.sin(eps) * math.sin(lam)));
}

/// Ayın ekvatoral konumu: (sağ açıklık, sapma) radyan.
Cift ayKonum(double ts) {
  final d = _jd(ts) - 2451545.0;
  final lm = 218.316 + 13.176396 * d;
  final m = (134.963 + 13.064993 * d) * _rad;
  final f = (93.272 + 13.229350 * d) * _rad;
  final lam = (lm + 6.289 * math.sin(m)) * _rad;
  final beta = 5.128 * math.sin(f) * _rad;
  final eps = 23.439 * _rad;
  final ra = math.atan2(math.sin(lam) * math.cos(eps) - math.tan(beta) * math.sin(eps), math.cos(lam));
  final dec = math.asin(math.sin(beta) * math.cos(eps) + math.cos(beta) * math.sin(eps) * math.sin(lam));
  return Cift(ra, dec);
}

/// Yer sabit (boylam, enlem) -> ekran çerçevesi (x sağ, y yukarı, z izleyiciye); merkez (lon0, lat0).
List<double> ekranVektor(double lon, double lat, double lon0, double lat0) {
  final cl = math.cos(lat);
  final dl = lon - lon0;
  return <double>[
    cl * math.sin(dl),
    math.cos(lat0) * math.sin(lat) - math.sin(lat0) * cl * math.cos(dl),
    math.sin(lat0) * math.sin(lat) + math.cos(lat0) * cl * math.cos(dl),
  ];
}

/// Kamera merkezi (boylam, enlem) radyan: çoğu zaman Türkiye (hafif salınımla), periyodik olarak bir tam tur.
Cift dunyaKamera(double ts) {
  var lon = kTrBoylam + 7.0 * math.sin(ts / 41.0) + 3.0 * math.sin(ts / 17.0 + 1.0);
  var lat = kTrEnlem + 2.5 * math.sin(ts / 53.0 + 0.5);
  if (kGeziPeriyot > 0 && kGeziSure > 0) {
    final p = ts % kGeziPeriyot;
    final bas = kGeziPeriyot - kGeziSure;
    if (p > bas) {
      final x = (p - bas) / kGeziSure;
      lon += 360.0 * (x * x * (3 - 2 * x));
      lat = lat + (8.0 - lat) * math.sin(math.pi * x) * 0.7;
    }
  }
  return Cift(lon * _rad, lat * _rad);
}

bool geziAninda(double ts) {
  if (kGeziPeriyot <= 0 || kGeziSure <= 0) return false;
  return (ts % kGeziPeriyot) > (kGeziPeriyot - kGeziSure) - 1.0;
}

// ── Doku ─────────────────────────────────────────────────────────────────────
class Doku {
  final int w;
  final int h;
  final Uint8List px; // RGBA
  Doku(this.w, this.h, this.px);
}

Future<Doku> dokuYukle(String yol) async {
  final data = await rootBundle.load(yol);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  final fr = await codec.getNextFrame();
  final bd = await fr.image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final d = Doku(fr.image.width, fr.image.height, bd!.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes));
  fr.image.dispose();
  return d;
}

double _kes(double x, double a, double b) => x < a ? a : (x > b ? b : x);

double _sm(double a, double b, double x) {
  final t = _kes((x - a) / (b - a), 0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// Çift doğrusal örnekleme: RGB (0..255) -> o[0..2]
void _bilRgb(Doku t, double u, double v, Float64List o) {
  final x = u * t.w - 0.5;
  final y = _kes(v * t.h - 0.5, 0.0, t.h - 1.001);
  final x0 = x.floor();
  final fx = x - x0;
  final y0 = y.floor();
  final fy = y - y0;
  final xa = x0 % t.w;
  final xb = (x0 + 1) % t.w;
  final yb = math.min(y0 + 1, t.h - 1);
  final i00 = (y0 * t.w + xa) * 4;
  final i10 = (y0 * t.w + xb) * 4;
  final i01 = (yb * t.w + xa) * 4;
  final i11 = (yb * t.w + xb) * 4;
  final p = t.px;
  for (var c = 0; c < 3; c++) {
    final a = p[i00 + c] * (1 - fx) + p[i10 + c] * fx;
    final b = p[i01 + c] * (1 - fx) + p[i11 + c] * fx;
    o[c] = a * (1 - fy) + b * fy;
  }
}

/// Tek kanal (gri) örnekleme, 0..255
double _bil1(Doku t, double u, double v) {
  final x = u * t.w - 0.5;
  final y = _kes(v * t.h - 0.5, 0.0, t.h - 1.001);
  final x0 = x.floor();
  final fx = x - x0;
  final y0 = y.floor();
  final fy = y - y0;
  final xa = x0 % t.w;
  final xb = (x0 + 1) % t.w;
  final yb = math.min(y0 + 1, t.h - 1);
  final p = t.px;
  final a = p[(y0 * t.w + xa) * 4] * (1 - fx) + p[(y0 * t.w + xb) * 4] * fx;
  final b = p[(yb * t.w + xa) * 4] * (1 - fx) + p[(yb * t.w + xb) * 4] * fx;
  return a * (1 - fy) + b * fy;
}

// ── Motor ────────────────────────────────────────────────────────────────────
class DunyaMotoru {
  final int r;
  final Doku gun;
  final Doku isik;
  final Doku su;
  final Doku bulut;
  final Doku ay;

  late final int sahne; // çıktı karesinin kenarı
  late final int cs;
  late final Uint8List _arka;
  late final Uint8List _buf;
  final Float64List _c = Float64List(3);

  // Dünya
  late final int _n;
  late final Int32List _eIdx; // sahne tamponundaki bayt konumu
  late final Float32List _nx, _ny, _nz, _cov, _rim;

  // Ay
  late final int _mr;
  late final int _msz;
  late final int _mn;
  late final Int32List _mI, _mJ;
  late final Float32List _mnx, _mny, _mnz, _mcov, _malb;

  // Hale
  late final Int32List _hIdx;
  late final Float32List _hA;

  DunyaMotoru(this.r, this.gun, this.isik, this.su, this.bulut, this.ay) {
    sahne = (3.2 * r).toInt() ~/ 2 * 2;
    cs = sahne ~/ 2;
    _arka = Uint8List(sahne * sahne * 4);
    for (var i = 0; i < sahne * sahne; i++) {
      _arka[i * 4] = 2;
      _arka[i * 4 + 1] = 4;
      _arka[i * 4 + 2] = 11;
      _arka[i * 4 + 3] = 255;
    }
    _buf = Uint8List(sahne * sahne * 4);
    _dunyaGeo();
    _ayGeo();
    _haleGeo();
  }

  void _dunyaGeo() {
    final sz = 2 * r + 8;
    final e = sz / 2.0;
    final off = cs - sz ~/ 2;
    final idx = <int>[];
    final fx = <double>[], fy = <double>[], fz = <double>[], fc = <double>[], fr = <double>[];
    for (var j = 0; j < sz; j++) {
      for (var i = 0; i < sz; i++) {
        final nx = (i + 0.5 - e) / r;
        final ny = -(j + 0.5 - e) / r;
        final r2 = nx * nx + ny * ny;
        final rr = math.sqrt(r2);
        if (rr > 1.03) continue;
        final nz = r2 < 1 ? math.sqrt(1 - r2) : 0.0;
        idx.add(((off + j) * sahne + (off + i)) * 4);
        fx.add(nx);
        fy.add(ny);
        fz.add(nz);
        fc.add(_kes((1.0 - rr) * r * 0.9 + 0.5, 0.0, 1.0));
        fr.add(math.pow(1 - nz, 2.4).toDouble());
      }
    }
    _n = idx.length;
    _eIdx = Int32List.fromList(idx);
    _nx = Float32List.fromList(fx);
    _ny = Float32List.fromList(fy);
    _nz = Float32List.fromList(fz);
    _cov = Float32List.fromList(fc);
    _rim = Float32List.fromList(fr);
  }

  void _ayGeo() {
    _mr = math.max(9, (r * 0.13).toInt());
    _msz = 2 * _mr + 6;
    final e = _msz / 2.0;
    final ii = <int>[], jj = <int>[];
    final fx = <double>[], fy = <double>[], fz = <double>[], fc = <double>[], fa = <double>[];
    final o = Float64List(3);
    for (var j = 0; j < _msz; j++) {
      for (var i = 0; i < _msz; i++) {
        final nx = (i + 0.5 - e) / _mr;
        final ny = -(j + 0.5 - e) / _mr;
        final r2 = nx * nx + ny * ny;
        final rr = math.sqrt(r2);
        if (rr > 1.05) continue;
        final nz = math.sqrt(math.max(0.0, 1 - r2));
        ii.add(i);
        jj.add(j);
        fx.add(nx);
        fy.add(ny);
        fz.add(nz);
        fc.add(_kes((1.0 - rr) * _mr + 0.5, 0.0, 1.0));
        final lon = math.atan2(nx, nz);
        final lat = math.asin(_kes(ny, -1.0, 1.0));
        var u = lon / (2 * math.pi) + 0.5;
        u = u - u.floorToDouble();
        _bilRgb(ay, u, 0.5 - lat / math.pi, o);
        fa
          ..add(o[0] / 255.0)
          ..add(o[1] / 255.0)
          ..add(o[2] / 255.0);
      }
    }
    _mn = ii.length;
    _mI = Int32List.fromList(ii);
    _mJ = Int32List.fromList(jj);
    _mnx = Float32List.fromList(fx);
    _mny = Float32List.fromList(fy);
    _mnz = Float32List.fromList(fz);
    _mcov = Float32List.fromList(fc);
    _malb = Float32List.fromList(fa);
  }

  void _haleGeo() {
    final idx = <int>[];
    final al = <double>[];
    final c = sahne / 2.0;
    for (var j = 0; j < sahne; j++) {
      for (var i = 0; i < sahne; i++) {
        final dx = i + 0.5 - c;
        final dy = j + 0.5 - c;
        final rr = math.sqrt(dx * dx + dy * dy) / r;
        if (rr < 0.97 || rr > 1.3) continue;
        final a = math.exp(-((rr - 0.97) / 0.07)) * 0.55 * _kes((1.30 - rr) / 0.3, 0.0, 1.0);
        if (a < 0.003) continue;
        idx.add((j * sahne + i) * 4);
        al.add(a);
      }
    }
    _hIdx = Int32List.fromList(idx);
    _hA = Float32List.fromList(al);
  }

  void _karis(int k, double cr, double cg, double cb, double a) {
    final b = _buf;
    b[k] = (b[k] * (1 - a) + cr * a).round();
    b[k + 1] = (b[k + 1] * (1 - a) + cg * a).round();
    b[k + 2] = (b[k + 2] * (1 - a) + cb * a).round();
  }

  void _ayCiz(double px, double py, List<double> m, List<double> l) {
    // Ay, Dünya'dan bakılan yönde çizilir (w = aydan Dünya'ya); evre gerçek güneş-ay açısından çıkar.
    var wx = -m[0], wy = -m[1], wz = -m[2];
    // u = up x w, up = (0,1,0)
    var ux = 1.0 * wz - 0.0 * wy;
    var uy = 0.0 * wx - 0.0 * wz;
    var uz = 0.0 * wy - 1.0 * wx;
    var un = math.sqrt(ux * ux + uy * uy + uz * uz);
    if (un < 1e-3) {
      ux = 1.0;
      uy = 0.0;
      uz = 0.0;
      un = 1.0;
    }
    ux /= un;
    uy /= un;
    uz /= un;
    final vx = wy * uz - wz * uy;
    final vy = wz * ux - wx * uz;
    final vz = wx * uy - wy * ux;
    final ld0 = l[0] * ux + l[1] * uy + l[2] * uz;
    final ld1 = l[0] * vx + l[1] * vy + l[2] * vz;
    final ld2 = l[0] * wx + l[1] * wy + l[2] * wz;
    final ox = (px - _msz / 2).toInt();
    final oy = (py - _msz / 2).toInt();
    for (var k = 0; k < _mn; k++) {
      final d = _kes(_mnx[k] * ld0 + _mny[k] * ld1 + _mnz[k] * ld2, 0.0, 1.0);
      final s = (0.07 + 0.93 * math.pow(d, 0.8).toDouble()) * 255.0 * 1.25;
      final x = ox + _mI[k];
      final y = oy + _mJ[k];
      if (x < 0 || y < 0 || x >= sahne || y >= sahne) continue;
      _karis((y * sahne + x) * 4, _kes(_malb[k * 3] * s, 0.0, 255.0), _kes(_malb[k * 3 + 1] * s, 0.0, 255.0),
          _kes(_malb[k * 3 + 2] * s, 0.0, 255.0), _mcov[k]);
    }
  }

  /// ts: unix zamanı (sn). Dönen: sahne x sahne RGBA (opak) tampon kopyası.
  Uint8List kare(double ts) {
    _buf.setAll(0, _arka);
    final kam = dunyaKamera(ts);
    final lon0 = kam.a, lat0 = kam.b;
    final g = gmstRad(ts);
    final gs = gunesKonum(ts);
    final l = ekranVektor(gs.a - g, gs.b, lon0, lat0);
    final am = ayKonum(ts);
    final m = ekranVektor(am.a - g, am.b, lon0, lat0);
    final rho = math.sqrt(m[0] * m[0] + m[1] * m[1]);
    final yx = rho > 1e-3 ? m[0] / rho : 1.0;
    final yy = rho > 1e-3 ? m[1] / rho : 0.0;
    final rm = r * (1.22 + 0.36 * rho);
    final mpx = cs + rm * yx;
    final mpy = cs - rm * yy;
    final arkada = m[2] < 0 && rho * rm < r * 1.02;

    if (arkada) _ayCiz(mpx, mpy, m, l);

    // hale
    for (var k = 0; k < _hIdx.length; k++) {
      _karis(_hIdx[k], 90, 160, 255, _hA[k]);
    }

    // Dünya
    final sp0 = math.sin(lat0), cp0 = math.cos(lat0);
    final l0 = l[0], l1 = l[1], l2 = l[2];
    final hx = l0, hy = l1, hz = l2 + 1.0;
    final hl = math.sqrt(hx * hx + hy * hy + hz * hz);
    final c = _c;
    for (var k = 0; k < _n; k++) {
      final nx = _nx[k], ny = _ny[k], nz = _nz[k];
      final lat = math.asin(_kes(nz * sp0 + ny * cp0, -1.0, 1.0));
      final lon = lon0 + math.atan2(nx, nz * cp0 - ny * sp0);
      var u = lon / (2 * math.pi) + 0.5;
      u = u - u.floorToDouble();
      final v = 0.5 - lat / math.pi;
      _bilRgb(gun, u, v, c);
      final li = _bil1(isik, u, v); // 0..255
      var uc = u + ts * 2.0e-6; // bulutlar çok yavaş sürüklenir
      uc = uc - uc.floorToDouble();
      final cl = _bil1(bulut, uc, v) / 255.0;
      final wt = _bil1(su, u, v) / 255.0;
      final oc = _sm(0.35, 0.65, wt);
      final d = nx * l0 + ny * l1 + nz * l2;
      final lam = _kes(d, 0.0, 1.0);
      final dm = _sm(-0.10, 0.24, d);
      final shade = 0.16 + 1.0 * math.pow(lam, 0.8).toDouble();
      var dr = c[0] * shade, dg = c[1] * shade, db = c[2] * shade;
      final cc = _kes(cl * 0.92, 0.0, 1.0);
      final cb = (0.17 + 0.9 * lam) * 238.0;
      dr = dr * (1 - cc) + cb * cc;
      dg = dg * (1 - cc) + cb * 1.02 * cc;
      db = db * (1 - cc) + cb * 1.06 * cc;
      if (dm > 0.01 && oc > 0.01) {
        final nh = _kes((nx * hx + ny * hy + nz * hz) / hl, 0.0, 1.0);
        final sp = math.pow(nh, 140).toDouble() * 0.6 * oc * (1 - cc) * dm;
        dr += 215 * sp;
        dg += 228 * sp;
        db += 240 * sp;
      }
      final q = (d - 0.03) / 0.1;
      final tw = math.exp(-q * q) * 0.2;
      dr += 255 * tw;
      dg += 120 * tw;
      db += 45 * tw;
      final lt = (1 - dm) * (1 - cc * 0.7) * 1.35;
      final nr = c[0] * 0.035 + 3 + li * lt * 1.0 * 1.25;
      final ng = c[1] * 0.035 + 7 + li * lt * 0.80 * 1.25;
      final nb = c[2] * 0.035 + 16 + li * lt * 0.46 * 1.25;
      var fr = nr * (1 - dm) + dr * dm;
      var fg = ng * (1 - dm) + dg * dm;
      var fb = nb * (1 - dm) + db * dm;
      final aw = 0.22 + 0.78 * _sm(-0.35, 0.45, d);
      final rim = _rim[k] * aw * 1.15;
      fr += 62 * rim;
      fg += 128 * rim;
      fb += 255 * rim;
      _karis(_eIdx[k], _kes(fr, 0.0, 255.0), _kes(fg, 0.0, 255.0), _kes(fb, 0.0, 255.0), _cov[k]);
    }

    if (!arkada) _ayCiz(mpx, mpy, m, l);
    return Uint8List.fromList(_buf);
  }
}

// ── Gösterim ─────────────────────────────────────────────────────────────────
class DunyaGorunum extends StatefulWidget {
  const DunyaGorunum({super.key});
  @override
  State<DunyaGorunum> createState() => _DunyaGorunumState();
}

class _DunyaGorunumState extends State<DunyaGorunum> with WidgetsBindingObserver {
  DunyaMotoru? _motor;
  ui.Image? _img;
  bool _calis = true;
  bool _hata = false;
  bool _kapali = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _baslat();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    _calis = s == AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    _kapali = true;
    WidgetsBinding.instance.removeObserver(this);
    _img?.dispose();
    super.dispose();
  }

  Future<void> _baslat() async {
    try {
      final gun = await dokuYukle('assets/dunya/gun.jpg');
      final isik = await dokuYukle('assets/dunya/isik.png');
      final su = await dokuYukle('assets/dunya/su.png');
      final bulut = await dokuYukle('assets/dunya/bulut.png');
      final ay = await dokuYukle('assets/dunya/ay.jpg');
      _motor = DunyaMotoru(105, gun, isik, su, bulut, ay);
    } catch (_) {
      if (mounted) setState(() => _hata = true);
      return;
    }
    while (mounted && !_kapali) {
      final ts = DateTime.now().millisecondsSinceEpoch / 1000.0;
      if (_calis) {
        final m = _motor!;
        final px = m.kare(ts);
        final tam = Completer<ui.Image>();
        ui.decodeImageFromPixels(px, m.sahne, m.sahne, ui.PixelFormat.rgba8888, tam.complete);
        final im = await tam.future;
        if (!mounted || _kapali) {
          im.dispose();
          return;
        }
        final eski = _img;
        setState(() => _img = im);
        eski?.dispose();
      }
      // gökyüzü yavaş hareket eder: tur sırasında akıcı, diğer zamanlarda tasarruflu
      await Future<void>.delayed(Duration(milliseconds: geziAninda(ts) ? 90 : 450));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hata) {
      return const Center(child: Icon(Icons.public, size: 96, color: Color(0xFF00D4FF)));
    }
    if (_img == null) {
      return const Center(child: Text('Dünya hazırlanıyor...', style: TextStyle(color: Colors.white38)));
    }
    return RawImage(image: _img, fit: BoxFit.contain, filterQuality: FilterQuality.medium);
  }
}
