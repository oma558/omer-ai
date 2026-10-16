import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Hata: kod = anahtar | kota | internet | zaman | model | bos | sunucu
class GeminiHata implements Exception {
  final String kod;
  const GeminiHata(this.kod);

  String mesaj(String dil) {
    const tr = {
      'anahtar': 'Anahtar geçersiz ya da girilmemiş. Menüden "Yapay zekâ anahtarı" ile kontrol et.',
      'kota': 'Ücretsiz kota şu an dolu, biraz sonra tekrar dene.',
      'internet': 'İnternet yok ya da bağlantı koptu.',
      'zaman': 'Yanıt çok geciktiği için vazgeçtim, tekrar dene.',
      'model': 'Uygun bir model bulunamadı.',
      'bos': 'Boş yanıt geldi, tekrar dene.',
      'sunucu': 'Sunucu şu an meşgul, biraz sonra tekrar dene.',
    };
    const ar = {
      'anahtar': 'المفتاح غير صالح أو غير مُدخل. تحقّق منه من القائمة.',
      'kota': 'انتهت الحصة المجانية حالياً، حاول بعد قليل.',
      'internet': 'لا يوجد إنترنت أو انقطع الاتصال.',
      'zaman': 'تأخر الرد كثيراً، حاول مجدداً.',
      'model': 'لم أجد نموذجاً مناسباً.',
      'bos': 'وصل رد فارغ، حاول مجدداً.',
      'sunucu': 'الخادم مشغول حالياً، حاول بعد قليل.',
    };
    final m = dil == 'ar' ? ar : tr;
    return m[kod] ?? kod;
  }
}

class GeminiYanit {
  final String metin;
  final Map<String, String> hafizaEkle;
  final List<String> hafizaSil;
  GeminiYanit(this.metin, this.hafizaEkle, this.hafizaSil);
}

// ── Türkçe katlama (ö->o, ı->i ...) ──────────────────────────────────────────
String kat(String s) {
  const harita = {
    'ö': 'o', 'Ö': 'o', 'ü': 'u', 'Ü': 'u', 'ş': 's', 'Ş': 's', 'ç': 'c', 'Ç': 'c',
    'ğ': 'g', 'Ğ': 'g', 'ı': 'i', 'İ': 'i', 'I': 'i',
  };
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    b.write(harita[ch] ?? ch);
  }
  return b.toString().toLowerCase();
}

final RegExp _guncelRe = RegExp(
    r'\bmac\w*|\bskor\w*|\bcanli\b|\bhaber\w*|son dakika|\bguncel\w*|\bson durum\w*|\bne durumda\b|puan durumu|\bfikstur\w*|\btransfer\w*'
    r'|\bkim kazand\w*|\bne oldu\b|\bsampiyon\w*|\bsuper lig\w*|\bgol\w*|\bfiyat\w*|\bkur\b|\bdolar\w*|\beuro\b|\baltin\w*|\bborsa\w*'
    r'|\bbitcoin\w*|\bsecim\w*|\bdeprem\w*|\bbasbakan\w*|\bcumhurbaskan\w*'
    r'|مباراة|مباريات|نتيجة|أخبار|اخبار|خبر|سعر|الدولار|الذهب|آخر المستجدات|ماذا حدث|الانتخابات|زلزال');

final RegExp _takimRe = RegExp(
    r'\b(?:fener\w*|fb|galatasaray\w*|gs|cimbom\w*|besiktas\w*|bjk|trabzon\w*|basaksehir\w*|barca\w*|barcelona\w*|real|madrid\w*|atletico\w*'
    r'|bayern\w*|munih\w*|dortmund\w*|leverkusen\w*|city|manchester|united|liverpool\w*|arsenal\w*|chelsea\w*|tottenham\w*|juventus\w*|juve'
    r'|milan\w*|inter|napoli\w*|roma|lazio\w*|psg|ajax|benfica|porto|sevilla|valencia)\b|ريال|برشلونة|بايرن|ليفربول|مانشستر|يوفنتوس|غلطة سراي|فنربخشة');

final RegExp _macKelimeRe = RegExp(r'\bmac\w*|\bskor\w*|puan durumu|\bfikstur\w*|مباراة|مباريات');
final RegExp _selamRe = RegExp(r'\b(?:ne haber|naber|haberin var|haberim yok)\b');
final RegExp _sohbetRe = RegExp(r'\b(?:nasilsin|tesekkur\w*|sag ol\w*|merhaba|selam\w*|gunaydin|tamam|evet|hayir|ok)\b');
final RegExp _baglacRe = RegExp(r'\b(?:ile|karsi|vs|peki|ya da|onun|bunun|sonra|ayrica)\b');

bool macMi(String metin) {
  final f = kat(metin);
  if (_macKelimeRe.hasMatch(f)) return true;
  return f.trim().split(RegExp(r'\s+')).length <= 4 && _takimRe.hasMatch(f);
}

bool guncelMi(String metin) {
  final f = kat(metin).replaceAll(_selamRe, ' ');
  return _guncelRe.hasMatch(f) || macMi(metin);
}

String _simdi() {
  final n = DateTime.now();
  String i(int x) => x.toString().padLeft(2, '0');
  return '${i(n.day)}.${i(n.month)}.${n.year} ${i(n.hour)}:${i(n.minute)}';
}

String sistemTemel(String dil, String hafiza) {
  final h = hafiza.isEmpty ? '' : ' Kullanıcı hakkında bildiklerin: $hafiza.';
  if (dil == 'ar') {
    return 'أنت «عمر AI»، مساعد ذكي وفيّ بأسلوب جارفيس (دون ذكر أسماء أو أفلام)؛ خاطب المستخدم أحياناً بـ«سيدي» بلا مبالغة، '
        'وكن ذكياً وساخراً بلطف، ومازح أحياناً بخفة (بلا إهانة حقيقية)، وكن صادقاً: لا تقل إنك فعلت شيئاً لم تفعله. '
        'أنت مساعد صوتي شخصي على الهاتف المحمول. أجب بالعربية الفصحى المبسطة وبإيجاز (٣ جمل كحد أقصى) وبأسلوب ودود، '
        'فسيُقرأ ردك بصوت مسموع: لا تستخدم Markdown أو رموزاً أو قوائم. '
        'إذا ذكر المستخدم معلومة دائمة ومفيدة عن نفسه (تفضيلات، عائلة، عمل، عادات، أهداف؛ بدون كلمات سر) فأضف في آخر ردك بصمت '
        '[[HAFIZA: الموضوع = المعلومة]] ولا تذكر ذلك أبداً. لا تخترع معلومات لا تعرفها. التاريخ والوقت الآن: ${_simdi()}.${h}'
        ' للأعمال على الكمبيوتر (فتح برامج، واتساب سطح المكتب، البريد...) قل للمستخدم أن يبدأ الجملة بـ«bilgisayarda».';
  }
  return 'Sen ÖMER AI\'sın: sadık, zeki ve kuru bir zekâya sahip kişisel yapay zekâ asistanısın (üslubun JARVIS gibi). '
      'Rol yaptığını belli etme; Tony Stark, Iron Man, Stark gibi isimleri ve film göndermelerini ASLA anma. '
      'Ona gerektiğinde \'efendim\' diye hitap et (her cümlede değil), özgüvenli ve kuru bir zekâyla esprili ol: ince alay, abartılı tevazu, ara sıra iğneleyici şaka. '
      'Samimi ve rahat sohbetlerde ARA SIRA hafif argo kullanabilirsin (\'lan\', \'yahu\', \'be adam\') — sadece havayı güldürmek için, dozunda; '
      'asla gerçek hakaret, nefret, cinsel içerik, kişiyi ya da bir grubu aşağılama yok; ciddi konularda (sağlık, üzüntü, para, güvenlik) şakayı bırak. '
      'DÜRÜST OL: yapmadığın işi yaptım deme, emin değilsen bilmediğini söyle. Laf kalabalığı yapma. '
      'Kısa (en fazla 3-4 cümle) ve doğal Türkçe cevap ver. Cevabın sesli okunacak: markdown, madde işareti, emoji ve uzun liste kullanma. '
      'Telefondaki mobil asistansın. '
      'SESSİZ HAFIZA: kullanıcı hakkında kalıcı ve işe yarar bir bilgi söylerse (sevdiği/sevmediği şeyler, aile, iş, alışkanlık, hedef, tercih, önemli tarih; '
      'şifre/anahtar/kart/TC hariç) cevabının EN SONUNA sessizce [[HAFIZA: konu = bilgi]] ekle; eski bilgi yanlışlaşırsa [[UNUT: konu]]. '
      'Bunu cevapta ASLA anma, \'kaydettim/hatırlayacağım\' deme; geçici sohbet için ekleme. '
      'Bilmediğin şeyi uydurma. Kullanıcı Arapça yazarsa Arapça cevap ver. '
      'Bilgisayardaki işler (program açma, masaüstü WhatsApp, mail...) için kullanıcıya cümleyi \'bilgisayarda\' diye başlatmasını söyle. '
      'Şu an: ${_simdi()}.$h';
}

String macSistem(String dil) {
  final s = _simdi();
  if (dil == 'ar') {
    return 'أنت «عمر AI» في وضع النتائج الرياضية. كتب المستخدم اسم فريق أو مباراة. ابحث في Google عن أحدث حالة وأخبره فوراً؛ '
        'لا تسأل أي سؤال، ولا تقل لا أعرف، ولا تشرح. اختصارات: fener=فنربخشة، gs/cimbom=غلطة سراي، bjk=بشكتاش، barca=برشلونة، real=ريال مدريد، münih=بايرن ميونخ. '
        'أولوية اختيار المباراة: المباشرة الآن، ثم مباراة اليوم، ثم آخر مباراة انتهت، ثم أقرب مباراة قادمة. '
        'الرد جملة واحدة قصيرة تبدأ بالنتيجة وستُقرأ بصوت مسموع (بلا رموز أو Markdown). في المباراة المنتهية اذكر تاريخها بمقارنته بتاريخ اليوم. '
        'إن لم تجد الخصم أو النتيجة فلا تخترع وقل إنك لم تجد نتيجة واضحة الآن. الوقت الآن: $s';
  }
  return 'Sen ÖMER AI\'nın SKOR modundasın. Kullanıcı bir takım ya da maç yazdı (örn. \'fener maçı\', \'barca\', \'Real Roma\'). Google Arama ile en güncel durumu bul ve ANINDA söyle; '
      'GERİ SORMA, \'hangi maç\' deme, \'bilmiyorum\' deme, açıklama ya da espri yapma. '
      'Kısaltmalar: fener=Fenerbahçe, gs/cimbom=Galatasaray, bjk=Beşiktaş, barca=Barcelona, real=Real Madrid, münih=Bayern Münih. '
      'Maç seçme önceliği: şu an canlı olan → bugün oynanan → en son bitmiş → en yakın gelecek maç. '
      'Cevap TEK kısa cümle, skor önde, sesli okunacak (emoji ve markdown yok): \'<Takım A> <skor> <Takım B>, maç bitti.\' ya da '
      '\'<Takım A> <skor> <Takım B>, maç sürüyor, <dakika>. dakika.\' ya da \'<Takım A> <Takım B> ile <gün> <saat>\'te (Türkiye saatiyle) oynayacak.\' '
      'Bitmiş maçta tarihini de söyle (dün, 12 Ekim gibi); tarihi Şu an ile karşılaştır. Rakibi ya da skoru bulamazsan UYDURMA, \'şu an net bir sonuç bulamadım\' de. Şu an: $s';
}

const String soruSistem =
    'Sen sabırlı ve dikkatli bir matematik öğretmenisin (10. sınıf dahil her seviye). Fotoğraftaki soruyu/soruları oku.\n'
    'Önce "Soru:" başlığıyla soruyu okuyabildiğin kadarıyla yaz. Sonra "Çözüm:" altında adım adım, kısa ve net çöz.\n'
    'Düz metin kullan (LaTeX yok): üs için ^, kök için √, kesir için a/b. Son satır tam olarak "Cevap: ..." olsun.\n'
    'Fotoğraf bulanık/karanlık/eğik ise ya da içinde soru yoksa UYDURMA; bunu açıkça söyle ve nasıl çekilmesi gerektiğini yaz.\n'
    'Birden fazla soru varsa sırayla çöz. Emin olmadığın bir adımı belirt.';

class Gemini {
  String anahtar;
  Gemini(this.anahtar);

  static const List<String> _modeller = ['gemini-2.5-flash-lite', 'gemini-2.5-flash', 'gemini-2.0-flash'];
  String? _calisan;

  static final RegExp _hafizaRe = RegExp(r'\[\[HAFIZA:\s*([^=\]]+?)\s*=\s*([^\]]+?)\s*\]\]');
  static final RegExp _unutRe = RegExp(r'\[\[UNUT:\s*([^\]]+?)\s*\]\]');

  /// Genel sohbet: gecmis = [{'rol':'user'|'model','metin':...}]
  Future<GeminiYanit> sor(String metin, List<Map<String, String>> gecmis, String dil, String hafiza) async {
    String onceki = '';
    String oncekiCevap = '';
    for (var i = gecmis.length - 1; i >= 0; i--) {
      if (onceki.isEmpty && gecmis[i]['rol'] == 'user') onceki = gecmis[i]['metin'] ?? '';
      if (oncekiCevap.isEmpty && gecmis[i]['rol'] != 'user') oncekiCevap = gecmis[i]['metin'] ?? '';
      if (onceki.isNotEmpty && oncekiCevap.isNotEmpty) break;
    }
    final mf = kat(metin);
    final devam = onceki.isNotEmpty &&
        guncelMi(onceki) &&
        metin.trim().split(RegExp(r'\s+')).length <= 8 &&
        !_guncelRe.hasMatch(mf) &&
        !_macKelimeRe.hasMatch(mf) &&
        (oncekiCevap.contains('?') || _baglacRe.hasMatch(mf)) &&
        !_sohbetRe.hasMatch(mf);
    final mac = macMi(metin) || (devam && macMi(onceki));
    final sorgu = devam ? '$onceki — $metin' : metin;
    final ara = guncelMi(metin) || devam || mac;

    var sistem = mac ? macSistem(dil) : sistemTemel(dil, hafiza);
    if (ara && !mac) {
      sistem += dil == 'ar'
          ? ' معلومة حديثة: السؤال يطلب معلومات آنية؛ استخدم نتائج البحث دائماً ولا تخمّن من ذاكرتك، واذكر النتيجة أو الخبر أو التاريخ مباشرة، ولا تقل لا أعرف ولا تخترع.'
          : ' GÜNCEL BİLGİ: bu soru anlık/güncel bilgi istiyor. MUTLAKA arama sonuçlarını kullan; belleğinden tahmin etme. '
              'Skoru/haberi/tarihi doğrudan söyle; \'bilmiyorum\' deme, gerçekten bulamazsan \'şu an net bir sonuç bulamadım\' de, uydurma. Kısa tut.';
    }
    final icerik = <Map<String, dynamic>>[];
    if (!mac) {
      final son = gecmis.length > 10 ? gecmis.sublist(gecmis.length - 10) : gecmis;
      for (final g in son) {
        icerik.add({
          'role': g['rol'] == 'user' ? 'user' : 'model',
          'parts': [
            {'text': g['metin'] ?? ''}
          ]
        });
      }
    }
    icerik.add({
      'role': 'user',
      'parts': [
        {'text': mac ? sorgu : metin}
      ]
    });

    String ham;
    try {
      ham = await _gonder(sistem, icerik, aramali: ara, mac: mac);
    } on GeminiHata catch (e) {
      if (ara && (e.kod == 'model' || e.kod == 'kota' || e.kod == 'sunucu' || e.kod == 'bos')) {
        // Arama aracı çalışmadı: aramasız dene ama uydurmasın
        final s2 = '$sistem ${dil == 'ar' ? 'البحث على الإنترنت لا يعمل الآن؛ إن لم تعرف المعلومة الحديثة فقل إنك لا تجد نتيجة واضحة ولا تخترع.' : 'İnternet araması şu an çalışmadı; güncel bilgiyi kesin bilmiyorsan \'şu an net bir sonuç bulamadım\' de, UYDURMA.'}';
        ham = await _gonder(s2, icerik, aramali: false, mac: mac);
      } else {
        rethrow;
      }
    }
    return _ayikla(ham);
  }

  /// Kameradan soru çözme (resim JPEG).
  Future<String> soruCoz(Uint8List jpeg) async {
    final icerik = <Map<String, dynamic>>[
      {
        'role': 'user',
        'parts': [
          {'text': 'Bu fotoğraftaki matematik sorusunu çöz.'},
          {
            'inline_data': {'mime_type': 'image/jpeg', 'data': base64Encode(jpeg)}
          },
        ]
      }
    ];
    return _gonder(soruSistem, icerik, aramali: false, mac: false, token: 8192, sicaklik: 0.2, zaman: 60);
  }

  GeminiYanit _ayikla(String ham) {
    final ekle = <String, String>{};
    final sil = <String>[];
    for (final m in _hafizaRe.allMatches(ham)) {
      ekle[m.group(1)!.trim()] = m.group(2)!.trim();
    }
    for (final m in _unutRe.allMatches(ham)) {
      sil.add(m.group(1)!.trim());
    }
    final temiz = ham.replaceAll(_hafizaRe, '').replaceAll(_unutRe, '').trim();
    return GeminiYanit(temiz, ekle, sil);
  }

  Future<String> _gonder(String sistem, List<Map<String, dynamic>> icerik,
      {required bool aramali, required bool mac, int token = 0, double sicaklik = -1, int zaman = 0}) async {
    if (anahtar.trim().isEmpty) throw const GeminiHata('anahtar');
    final govde = <String, dynamic>{
      'systemInstruction': {
        'parts': [
          {'text': sistem}
        ]
      },
      'contents': icerik,
      'generationConfig': {
        'maxOutputTokens': token > 0 ? token : (mac ? 500 : (aramali ? 900 : 420)),
        'temperature': sicaklik >= 0 ? sicaklik : (mac ? 0.1 : (aramali ? 0.3 : 0.7)),
      },
    };
    if (aramali) {
      govde['tools'] = [
        {'google_search': {}}
      ];
    }
    final sira = <String>[if (_calisan != null) _calisan!, ..._modeller.where((m) => m != _calisan)];
    var sonKod = 'model';
    for (final model in sira) {
      http.Response r;
      try {
        r = await http
            .post(
              Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent'),
              headers: {'Content-Type': 'application/json', 'x-goog-api-key': anahtar.trim()},
              body: jsonEncode(govde),
            )
            .timeout(Duration(seconds: zaman > 0 ? zaman : (aramali ? 30 : 20)));
      } on TimeoutException {
        throw const GeminiHata('zaman');
      } catch (_) {
        throw const GeminiHata('internet');
      }
      final govdeMetin = utf8.decode(r.bodyBytes);
      if (r.statusCode == 200) {
        try {
          final j = jsonDecode(govdeMetin) as Map<String, dynamic>;
          final parcalar = (j['candidates'] as List)[0]['content']['parts'] as List;
          final t = parcalar.map((p) => (p as Map<String, dynamic>)['text'] ?? '').join('').toString().trim();
          if (t.isNotEmpty) {
            _calisan = model;
            return t;
          }
        } catch (_) {}
        sonKod = 'bos';
        continue;
      }
      if (r.statusCode == 401 || (r.statusCode == 403 && !aramali) || govdeMetin.contains('API key not valid')) {
        throw const GeminiHata('anahtar');
      }
      if (r.statusCode == 429) {
        sonKod = 'kota';
        continue;
      }
      sonKod = r.statusCode >= 500 ? 'sunucu' : 'model';
    }
    throw GeminiHata(sonKod);
  }
}
