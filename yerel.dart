import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'gemini.dart';

String tt(String dil, String tr, String ar) => dil == 'ar' ? ar : tr;

class Etkinlik {
  String baslik;
  DateTime zaman;
  bool bildirildi;
  Etkinlik(this.baslik, this.zaman, [this.bildirildi = false]);

  Map<String, dynamic> toJson() => {'b': baslik, 'z': zaman.millisecondsSinceEpoch, 'n': bildirildi};
  static Etkinlik fromJson(Map<String, dynamic> j) =>
      Etkinlik(j['b'] as String, DateTime.fromMillisecondsSinceEpoch(j['z'] as int), (j['n'] as bool?) ?? false);

  String zamanMetni() {
    String i(int x) => x.toString().padLeft(2, '0');
    return '${i(zaman.day)}.${i(zaman.month)} ${i(zaman.hour)}:${i(zaman.minute)}';
  }
}

/// Yerel komutun sonucu: cevap (sohbete yazılır), url (açılır) ya da özel eylem.
class Sonuc {
  final String? cevap;
  final String? url;
  final String? ozel; // 'pc:<komut>' | 'kamera' | 'pcekran' | 'dil:ar' | 'dil:tr'
  const Sonuc({this.cevap, this.url, this.ozel});
}

class Yerel {
  final SharedPreferences p;
  Yerel(this.p);

  // ── Hafıza ──
  Map<String, String> get hafiza {
    final s = p.getString('hafiza');
    if (s == null) return {};
    try {
      return (jsonDecode(s) as Map<String, dynamic>).map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  Future<void> _hafizaYaz(Map<String, String> m) => p.setString('hafiza', jsonEncode(m));

  String hafizaMetni() => hafiza.entries.map((e) => '${e.key}: ${e.value}').join('; ');

  Future<void> hafizaIsle(GeminiYanit y) async {
    if (y.hafizaEkle.isEmpty && y.hafizaSil.isEmpty) return;
    final m = hafiza;
    m.addAll(y.hafizaEkle);
    for (final s in y.hafizaSil) {
      m.removeWhere((k, v) => kat(k).contains(kat(s)));
    }
    await _hafizaYaz(m);
  }

  // ── Kişiler ──
  Map<String, String> get kisiler {
    final s = p.getString('kisiler');
    if (s == null) return {};
    try {
      return (jsonDecode(s) as Map<String, dynamic>).map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  // ── Takvim ──
  List<Etkinlik> get etkinlikler {
    final s = p.getString('takvim');
    if (s == null) return [];
    try {
      return (jsonDecode(s) as List).map((e) => Etkinlik.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _takvimYaz(List<Etkinlik> l) => p.setString('takvim', jsonEncode(l.map((e) => e.toJson()).toList()));

  /// Vakti gelen hatırlatıcıları döndürür ve bildirildi diye işaretler.
  Future<List<Etkinlik>> vadesiGelenler() async {
    final l = etkinlikler;
    final simdi = DateTime.now();
    final gelen = <Etkinlik>[];
    for (final e in l) {
      if (!e.bildirildi && !e.zaman.isAfter(simdi)) {
        e.bildirildi = true;
        gelen.add(e);
      }
    }
    if (gelen.isNotEmpty) await _takvimYaz(l);
    return gelen;
  }

  Etkinlik? _etkinlikCoz(String ham) {
    final f = kat(ham);
    final simdi = DateTime.now();
    DateTime? z;
    var temiz = ham;
    final goreli = RegExp(r'(\d+)\s*(dakika|dk|saat)\s*sonra').firstMatch(f);
    if (goreli != null) {
      final n = int.parse(goreli.group(1)!);
      z = simdi.add(goreli.group(2) == 'saat' ? Duration(hours: n) : Duration(minutes: n));
      temiz = ham.replaceRange(goreli.start, goreli.end, '');
    } else {
      final sa = RegExp(r'(\d{1,2})[:.](\d{2})').firstMatch(f);
      if (sa == null) return null;
      final h = int.parse(sa.group(1)!);
      final m = int.parse(sa.group(2)!);
      if (h > 23 || m > 59) return null;
      var gun = DateTime(simdi.year, simdi.month, simdi.day);
      final yarin = f.contains('yarin');
      if (yarin) gun = gun.add(const Duration(days: 1));
      z = DateTime(gun.year, gun.month, gun.day, h, m);
      if (!yarin && z.isBefore(simdi)) z = z.add(const Duration(days: 1));
      temiz = ham.replaceRange(sa.start, sa.end, '');
    }
    temiz = temiz.replaceAll(RegExp(r'yarın|yarin|bugün|bugun', caseSensitive: false), ' ');
    temiz = temiz.replaceAll(RegExp(r'\s+'), ' ').trim();
    return Etkinlik(temiz.isEmpty ? 'Hatırlatıcı' : temiz, z);
  }

  static String? numaraDuzelt(String s) {
    var d = s.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.length == 11 && d.startsWith('0')) d = '90${d.substring(1)}';
    if (d.length == 10) d = '90$d';
    return d.length >= 11 ? d : null;
  }

  String? _numaraBul(String adNumara) {
    final dogrudan = numaraDuzelt(adNumara);
    if (dogrudan != null && RegExp(r'^[\d\s+()-]+$').hasMatch(adNumara.trim())) return dogrudan;
    final a = kat(adNumara).trim();
    for (final e in kisiler.entries) {
      if (kat(e.key).contains(a) || a.contains(kat(e.key))) return numaraDuzelt(e.value);
    }
    return null;
  }

  /// Yerel komut mu? Değilse null döner (yapay zekâya gider).
  Future<Sonuc?> komut(String ham, String dil) async {
    ham = ham.trim();
    final f = kat(ham);
    if (f.isEmpty) return null;

    if (RegExp(r'^(?:pc|bilgisayar) ekran').hasMatch(f)) return const Sonuc(ozel: 'pcekran');

    // PC'ye yönlendir: "bilgisayarda ..."
    final pc = RegExp(r"^(?:bilgisayar(?:da|dan|a|im(?:de|den|e))|pc(?:'de|de|'den|den|'ye|ye))\b[\s,:-]*").firstMatch(f);
    final pcAr = RegExp(r'^(?:على|في|ب)\s*(?:ال)?(?:كمبيوتر|حاسوب|كمبيوتري)\s*').firstMatch(ham);
    if (pc != null && pc.end < f.length) {
      return Sonuc(ozel: 'pc:${ham.substring(pc.end)}');
    }
    if (pcAr != null && pcAr.end < ham.length) {
      return Sonuc(ozel: 'pc:${ham.substring(pcAr.end)}');
    }
    if (RegExp(r'^dil\s*(?:arapca|عربي)|^(?:arapca|عربي)\s*(?:konus|ol)').hasMatch(f) || f == 'arapca') {
      return const Sonuc(ozel: 'dil:ar');
    }
    if (RegExp(r'^dil\s*turkce|^turkce\s*(?:konus|ol)').hasMatch(f) || f == 'turkce') return const Sonuc(ozel: 'dil:tr');

    if (RegExp(r'^(?:soru(?:yu)?\s*coz|kameradan\s*soru|fotograftan\s*soru|soru\s*fotograf)').hasMatch(f)) {
      return const Sonuc(ozel: 'kamera');
    }

    // Hafıza
    var m = RegExp(r'^(?:hatirla|aklinda tut|not al)\s*[:\-]?\s*(.+)$').firstMatch(f);
    if (m != null) {
      final govde = ham.substring(ham.length - m.group(1)!.length).trim();
      final ayr = govde.split('=');
      final mem = hafiza;
      if (ayr.length >= 2) {
        mem[ayr[0].trim()] = ayr.sublist(1).join('=').trim();
      } else {
        mem[govde.length > 24 ? govde.substring(0, 24) : govde] = govde;
      }
      await _hafizaYaz(mem);
      return Sonuc(cevap: tt(dil, 'Tamam efendim, hafızama aldım: $govde', 'حسناً يا سيدي، حفظتُه في ذاكرتي: $govde'));
    }
    m = RegExp(r'^unut\s*[:\-]?\s*(.+)$').firstMatch(f);
    if (m != null) {
      final q = m.group(1)!.trim();
      final mem = hafiza;
      final once = mem.length;
      mem.removeWhere((k, v) => kat(k).contains(q) || kat(v).contains(q));
      await _hafizaYaz(mem);
      return Sonuc(
          cevap: once == mem.length
              ? tt(dil, 'Hafızamda buna uyan bir kayıt bulamadım efendim.', 'لم أجد في ذاكرتي ما يطابق ذلك يا سيدي.')
              : tt(dil, 'Hafızamdan sildim efendim: $q', 'حذفتُه من ذاكرتي يا سيدي: $q'));
    }
    if (RegExp(r'^(?:hafizam|ne hatirliyorsun|hafizayi goster)$').hasMatch(f)) {
      final mem = hafiza;
      if (mem.isEmpty) {
        return Sonuc(
            cevap: tt(dil, 'Hafızam boş efendim. \'hatırla: <bilgi>\' diyebilirsin.', 'ذاكرتي فارغة يا سيدي. قل \'hatırla: <معلومة>\'.'));
      }
      return Sonuc(
          cevap: '${tt(dil, 'Hatırladıklarım:', 'ما أتذكره:')}\n${mem.entries.map((e) => '• ${e.key}: ${e.value}').join('\n')}');
    }
    if (RegExp(r'^(?:hafizayi temizle|hafizayi sil)$').hasMatch(f)) {
      await _hafizaYaz({});
      return Sonuc(cevap: tt(dil, 'Hafızamı tamamen temizledim efendim.', 'مسحتُ ذاكرتي بالكامل يا سيدي.'));
    }

    // Takvim / hatırlatıcı
    m = RegExp(r'^(?:takvim(?:e)?\s+ekle|hatirlat(?:ici)?(?:\s+ekle)?|bana hatirlat)\s*[:\-]?\s*(.+)$').firstMatch(f);
    if (m != null) {
      final govde = ham.substring(ham.length - m.group(1)!.length);
      final e = _etkinlikCoz(govde);
      if (e == null) {
        return Sonuc(
            cevap: tt(dil, 'Saati anlayamadım efendim. Örnek: \'hatırlat: toplantı yarın 14:00\' ya da \'hatırlat: çay 20 dakika sonra\'.',
                'لم أفهم الوقت يا سيدي. مثال: \'hatırlat: اجتماع yarın 14:00\' أو \'hatırlat: شاي 20 dakika sonra\'.'));
      }
      final l = etkinlikler..add(e);
      await _takvimYaz(l);
      return Sonuc(
          cevap: tt(dil, 'Hatırlatıcı eklendi efendim: \'${e.baslik}\' — ${e.zamanMetni()} (uygulama açıkken zamanı gelince haber veririm).',
              'تمت إضافة التذكير يا سيدي: \'${e.baslik}\' — ${e.zamanMetni()} (سأخبرك عند حلول الوقت ما دام التطبيق مفتوحاً).'));
    }
    if (RegExp(r'^(?:takvim|takvimim|yaklasan|hatirlaticilar)$').hasMatch(f)) {
      final simdi = DateTime.now();
      final l = etkinlikler.where((e) => e.zaman.isAfter(simdi)).toList()..sort((a, b) => a.zaman.compareTo(b.zaman));
      if (l.isEmpty) return Sonuc(cevap: tt(dil, 'Takvimde etkinlik yok.', 'لا توجد أحداث في التقويم.'));
      return Sonuc(cevap: '${tt(dil, 'Yaklaşan:', 'القادم:')}\n${l.take(8).map((e) => '• ${e.zamanMetni()} — ${e.baslik}').join('\n')}');
    }
    m = RegExp(r'^takvimden\s+sil\s*[:\-]?\s*(.+)$').firstMatch(f);
    if (m != null) {
      final q = m.group(1)!.trim();
      final l = etkinlikler;
      final once = l.length;
      l.removeWhere((e) => kat(e.baslik).contains(q));
      await _takvimYaz(l);
      return Sonuc(
          cevap: once == l.length
              ? tt(dil, 'Takvimde buna uyan bir kayıt bulamadım efendim.', 'لم أجد في التقويم ما يطابق ذلك يا سيدي.')
              : tt(dil, 'Takvimden sildim efendim.', 'حذفتُ من التقويم يا سيدي.'));
    }

    // Kişiler
    m = RegExp(r'^kisi ekle\s*[:\-]?\s*(.+?)\s*\|\s*(.+)$').firstMatch(f);
    if (m != null) {
      final govde = ham.substring(ham.length - (f.length - m.start(1)));
      final ayr = govde.split('|');
      if (ayr.length >= 2) {
        final k = kisiler..[ayr[0].trim()] = ayr[1].trim();
        await p.setString('kisiler', jsonEncode(k));
        return Sonuc(cevap: tt(dil, 'Kişi kaydedildi: ${ayr[0].trim()} → ${ayr[1].trim()}', 'تم حفظ جهة الاتصال: ${ayr[0].trim()} ← ${ayr[1].trim()}'));
      }
    }
    if (RegExp(r'^kisiler$').hasMatch(f)) {
      final k = kisiler;
      if (k.isEmpty) {
        return Sonuc(cevap: tt(dil, 'Henüz kişi kaydedilmedi. Eklemek için: \'kişi ekle: İsim|numara\'', 'لم تُحفظ أي جهة اتصال بعد. للإضافة: \'kişi ekle: الاسم|الرقم\''));
      }
      return Sonuc(cevap: '${tt(dil, 'Kayıtlı Kişiler:', 'جهات الاتصال المحفوظة:')}\n${k.entries.map((e) => '• ${e.key}: ${e.value}').join('\n')}');
    }

    // WhatsApp: whatsapp Ahmet | mesaj   (WhatsApp açılır, Gönder'e sen basarsın)
    m = RegExp(r'^whatsapp\s+(.+?)\s*\|\s*(.+)$').firstMatch(f);
    if (m != null) {
      final govde = ham.substring(ham.length - (f.length - m.start(1)));
      final ayr = govde.split('|');
      final num = _numaraBul(ayr[0]);
      final mesaj = ayr.sublist(1).join('|').trim();
      if (num == null) {
        return Sonuc(
            cevap: tt(dil, '\'${ayr[0].trim()}\' için numara bulamadım. Önce: \'kişi ekle: ${ayr[0].trim()}|05xx...\'',
                'لم أجد رقماً لـ \'${ayr[0].trim()}\'. أضفه أولاً: \'kişi ekle: ${ayr[0].trim()}|05xx...\''));
      }
      return Sonuc(
          cevap: tt(dil, 'WhatsApp açılıyor efendim; mesaj hazır, Gönder\'e sen bas.', 'جارٍ فتح واتساب يا سيدي؛ الرسالة جاهزة، اضغط أنت إرسال.'),
          url: 'https://wa.me/$num?text=${Uri.encodeComponent(mesaj)}');
    }

    // Arama
    m = RegExp(r'^(?:ara|arama yap|telefon et)\s*[:\-]?\s*(.+)$').firstMatch(f);
    if (m != null) {
      final govde = ham.substring(ham.length - m.group(1)!.length).trim();
      final num = _numaraBul(govde);
      if (num != null) {
        return Sonuc(cevap: tt(dil, 'Arama ekranı açılıyor efendim: $govde', 'جارٍ فتح شاشة الاتصال يا سيدي: $govde'), url: 'tel:+$num');
      }
    }

    // YouTube / Spotify
    final yt = RegExp(r"^(?:youtube\S*|yt)\s+(.+)$").firstMatch(f);
    if (yt != null) {
      final q = _fiilSil(ham.substring(ham.length - yt.group(1)!.length));
      return Sonuc(
          cevap: tt(dil, 'YouTube\'da \'$q\' açılıyor efendim.', 'جارٍ فتح \'$q\' في يوتيوب يا سيدي.'),
          url: 'https://www.youtube.com/results?search_query=${Uri.encodeComponent(q)}');
    }
    final sp = RegExp(r"^(?:spotify\S*)\s+(.+)$").firstMatch(f);
    if (sp != null) {
      final q = _fiilSil(ham.substring(ham.length - sp.group(1)!.length));
      return Sonuc(
          cevap: tt(dil, 'Spotify\'da \'$q\' araması açılıyor efendim.', 'جارٍ فتح البحث عن \'$q\' في Spotify يا سيدي.'),
          url: 'https://open.spotify.com/search/${Uri.encodeComponent(q)}');
    }
    final muzik = RegExp(r'^(?:muzik\s+cal|sarki\s+cal|cal)\s*[:\-]?\s*(.+)$').firstMatch(f);
    if (muzik != null) {
      final q = _fiilSil(ham.substring(ham.length - muzik.group(1)!.length));
      return Sonuc(
          cevap: tt(dil, 'YouTube\'da \'$q\' açılıyor efendim.', 'جارٍ فتح \'$q\' في يوتيوب يا سيدي.'),
          url: 'https://www.youtube.com/results?search_query=${Uri.encodeComponent(q)}');
    }
    return null;
  }

  String _fiilSil(String s) {
    final t = s.replaceAll(RegExp(r'(?<![\p{L}])(?:ara|aç|ac|çal|cal|izle|oynat)(?![\p{L}])', unicode: true, caseSensitive: false), ' ');
    final q = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return q.isEmpty ? s.trim() : q;
  }
}
