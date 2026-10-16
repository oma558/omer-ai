import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';

import 'dunya.dart';
import 'gemini.dart';
import 'pc.dart';
import 'yerel.dart';

void main() => runApp(const OmerApp());

final RegExp kArapca = RegExp(r'[\u0600-\u06FF]');

class OmerApp extends StatelessWidget {
  const OmerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ÖMER AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kArka,
        colorScheme: const ColorScheme.dark(primary: kAna, surface: kPanel),
        useMaterial3: true,
      ),
      home: const Acilis(),
    );
  }
}

class Acilis extends StatelessWidget {
  const Acilis({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SharedPreferences>(
      future: SharedPreferences.getInstance(),
      builder: (c, s) {
        if (!s.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        return AnaSayfa(s.data!);
      },
    );
  }
}

class Mesaj {
  final bool bot;
  final bool pc;
  final String metin;
  final String zaman;
  Mesaj(this.bot, this.metin, this.zaman, {this.pc = false});
}

class AnaSayfa extends StatefulWidget {
  final SharedPreferences p;
  const AnaSayfa(this.p, {super.key});
  @override
  State<AnaSayfa> createState() => _AnaSayfaState();
}

class _AnaSayfaState extends State<AnaSayfa> {
  late final Yerel _yerel = Yerel(widget.p);
  late final Gemini _gemini = Gemini(widget.p.getString('gemini_anahtar') ?? '');
  final List<Mesaj> _mesajlar = [];
  final List<Map<String, String>> _gecmis = [];
  final _kontrol = TextEditingController();
  final _kaydir = ScrollController();
  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  Baglanti? _pc;
  bool _pcBagli = false;
  int _pcSurum = 0;
  int _pcSonId = 0;
  Timer? _hatirlatZaman;

  bool _dinliyor = false;
  bool _sttHazir = false;
  bool _dusunuyor = false;
  bool _sesli = true;
  String _dil = 'tr';

  String t(String tr, String ar) => tt(_dil, tr, ar);

  @override
  void initState() {
    super.initState();
    _dil = widget.p.getString('dil') ?? 'tr';
    _sesli = widget.p.getBool('sesli') ?? true;
    _tts.setSpeechRate(0.5);
    final taban = widget.p.getString('pc_taban');
    final token = widget.p.getString('pc_token');
    if (taban != null && token != null && token.isNotEmpty) _pcAc(Baglanti(taban, token));
    _hatirlatZaman = Timer.periodic(const Duration(seconds: 20), (_) => _hatirlatKontrol());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bot(t(
          'ÖMER AI hazır efendim. Telefonda tek başıma çalışırım; "bilgisayarda ..." diye başlarsan komutu PC\'ye gönderirim.',
          'عمر AI جاهز يا سيدي. أعمل على الهاتف وحدي؛ وإن بدأت الجملة بـ«bilgisayarda» أرسلتها إلى الكمبيوتر.'));
      if (_gemini.anahtar.trim().isEmpty) _anahtarDialog();
    });
  }

  @override
  void dispose() {
    _pcSurum++;
    _hatirlatZaman?.cancel();
    _stt.cancel();
    _tts.stop();
    _kontrol.dispose();
    _kaydir.dispose();
    super.dispose();
  }

  String _saat() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
  }

  void _ekle(Mesaj m) {
    if (!mounted) return;
    setState(() => _mesajlar.add(m));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_kaydir.hasClients) {
        _kaydir.animateTo(_kaydir.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  void _kullanici(String m) => _ekle(Mesaj(false, m, _saat()));

  void _bot(String m, {bool konus = false}) {
    _ekle(Mesaj(true, m, _saat()));
    if (konus && _sesli) _konus(m);
  }

  Future<void> _konus(String metin) async {
    final temiz = metin
        .replaceAll(RegExp(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}]', unicode: true), ' ')
        .replaceAll(RegExp(r'[*#_`>|•]'), ' ')
        .replaceAll(RegExp(r'https?://\S+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (temiz.isEmpty) return;
    await _tts.setLanguage(kArapca.hasMatch(temiz) || _dil == 'ar' ? 'ar-SA' : 'tr-TR');
    await _tts.speak(temiz.length > 700 ? temiz.substring(0, 700) : temiz);
  }

  void _bildir(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ── Hatırlatıcılar ──
  Future<void> _hatirlatKontrol() async {
    final gelen = await _yerel.vadesiGelenler();
    for (final e in gelen) {
      _bot('⏰ ${e.baslik}', konus: true);
    }
  }

  // ── PC bağlantısı ──
  void _pcAc(Baglanti b) {
    _pc = b;
    _pcBagli = false;
    _pcSonId = 0;
    final surum = ++_pcSurum;
    _pcDinle(b, surum);
  }

  Future<void> _pcDinle(Baglanti b, int surum) async {
    var bekle = 1;
    while (mounted && surum == _pcSurum) {
      try {
        await for (final o in b.olaylar(son: _pcSonId)) {
          bekle = 1;
          if (!mounted || surum != _pcSurum) return;
          _pcOlay(o);
        }
      } catch (_) {}
      if (!mounted || surum != _pcSurum) return;
      setState(() => _pcBagli = false);
      await Future<void>.delayed(Duration(seconds: bekle));
      bekle = bekle < 10 ? bekle + 2 : 10;
    }
  }

  void _pcOlay(Map<String, dynamic> o) {
    final tur = o['t'];
    if (tur == 'durum') {
      setState(() => _pcBagli = true);
      return;
    }
    if (tur == 'mesaj') {
      final id = o['id'];
      if (id is int && id > _pcSonId) _pcSonId = id;
      final bot = o['kim'] == 'bot';
      final metin = (o['metin'] ?? '').toString();
      if (!_pcBagli) setState(() => _pcBagli = true);
      _ekle(Mesaj(bot, metin, (o['zaman'] ?? _saat()).toString(), pc: true));
      if (bot && o['ses'] == true && _sesli) _konus(metin);
    }
  }

  Future<void> _pcBaglanSayfa() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => PcEslestirSayfa(dil: _dil)));
    if (ok == true) {
      final taban = widget.p.getString('pc_taban');
      final token = widget.p.getString('pc_token');
      if (taban != null && token != null) {
        _pcAc(Baglanti(taban, token));
        _bot(t('PC ile eşleştim efendim. "bilgisayarda ..." komutlarını artık PC yapar.',
            'تم الاقتران بالكمبيوتر يا سيدي. أوامر «bilgisayarda» سينفذها الكمبيوتر الآن.'));
      }
    }
  }

  Future<void> _pcKes() async {
    _pcSurum++;
    _pc = null;
    await widget.p.remove('pc_token');
    await widget.p.remove('pc_taban');
    if (mounted) setState(() => _pcBagli = false);
    _bot(t('PC bağlantısını kestim efendim.', 'قطعتُ الاتصال بالكمبيوتر يا سيدي.'));
  }

  Future<void> _pcEkrani() async {
    final b = _pc;
    if (b == null) {
      _bildir(t('Önce menüden PC\'ye bağlan.', 'اتصل بالكمبيوتر أولاً من القائمة.'));
      return;
    }
    final r = await b.resim('/api/ekran.jpg');
    if (!mounted) return;
    if (r == null) {
      _bildir(t('Bilgisayar ekranı alınamadı.', 'تعذّر الحصول على شاشة الكمبيوتر.'));
      return;
    }
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: kPanel,
        insetPadding: const EdgeInsets.all(8),
        child: InteractiveViewer(child: Image.memory(r)),
      ),
    );
  }

  // ── Komut işleme ──
  Future<void> _gonder(String ham) async {
    final m = ham.trim();
    if (m.isEmpty) return;
    final sonuc = await _yerel.komut(m, _dil);
    final ozel = sonuc?.ozel;
    if (ozel != null && ozel.startsWith('pc:')) {
      final k = ozel.substring(3).trim();
      final b = _pc;
      if (b == null) {
        _kullanici(m);
        _bot(t('Bilgisayara bağlı değilim efendim. Menüden "PC\'ye bağlan" ile eşleştir.',
            'لست متصلاً بالكمبيوتر يا سيدي. اقترن به من القائمة.'));
        return;
      }
      try {
        await b.komut(k, _sesli); // yankı PC'den gelir (kullanıcı balonu da PC'den eklenir)
      } catch (e) {
        _kullanici(m);
        _bot(e is String ? e : t('Bilgisayara ulaşılamadı.', 'تعذّر الوصول إلى الكمبيوتر.'));
      }
      return;
    }
    _kullanici(m);
    if (sonuc != null) {
      await _yerelIsle(sonuc);
      return;
    }
    await _yapayZeka(m);
  }

  Future<void> _yerelIsle(Sonuc s) async {
    final ozel = s.ozel;
    if (ozel == 'kamera') {
      await _kameraSoru();
      return;
    }
    if (ozel == 'pcekran') {
      await _pcEkrani();
      return;
    }
    if (ozel == 'dil:ar' || ozel == 'dil:tr') {
      setState(() => _dil = ozel == 'dil:ar' ? 'ar' : 'tr');
      await widget.p.setString('dil', _dil);
      _bot(t('Dil Türkçe oldu efendim.', 'تم تغيير اللغة إلى العربية يا سيدي.'), konus: true);
      return;
    }
    if (s.cevap != null) _bot(s.cevap!, konus: true);
    if (s.url != null) {
      try {
        await launchUrl(Uri.parse(s.url!), mode: LaunchMode.externalApplication);
      } catch (_) {
        _bot(t('Bağlantı açılamadı.', 'تعذّر فتح الرابط.'));
      }
    }
  }

  Future<void> _yapayZeka(String m) async {
    if (_gemini.anahtar.trim().isEmpty) {
      _bot(t('Yapay zekâ anahtarı girilmemiş efendim; yerel komutlar çalışır, sohbet için anahtar lazım.',
          'لم يُدخل مفتاح الذكاء الاصطناعي يا سيدي؛ الأوامر المحلية تعمل، وللمحادثة يلزم المفتاح.'));
      _anahtarDialog();
      return;
    }
    setState(() => _dusunuyor = true);
    try {
      final y = await _gemini.sor(m, _gecmis, _dil, _yerel.hafizaMetni());
      _gecmis
        ..add({'rol': 'user', 'metin': m})
        ..add({'rol': 'model', 'metin': y.metin});
      if (_gecmis.length > 24) _gecmis.removeRange(0, _gecmis.length - 24);
      await _yerel.hafizaIsle(y);
      _bot(y.metin, konus: true);
    } on GeminiHata catch (e) {
      _bot(e.mesaj(_dil));
      if (e.kod == 'anahtar') _anahtarDialog();
    } catch (_) {
      _bot(t('Bir sorun çıktı, tekrar dene.', 'حدثت مشكلة، حاول مجدداً.'));
    } finally {
      if (mounted) setState(() => _dusunuyor = false);
    }
  }

  Future<void> _kameraSoru() async {
    if (_gemini.anahtar.trim().isEmpty) {
      _anahtarDialog();
      return;
    }
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 1800);
      if (x == null) return;
      final Uint8List bytes = await x.readAsBytes();
      _bot(t('Fotoğrafı aldım, soruyu okuyup çözüyorum...', 'التقطتُ الصورة، أقرأ السؤال وأحلّه...'));
      setState(() => _dusunuyor = true);
      final c = await _gemini.soruCoz(bytes);
      _bot(c);
      final cevap = c.split('\n').lastWhere((l) => l.trim().startsWith('Cevap'), orElse: () => '');
      if (_sesli && cevap.isNotEmpty) _konus(cevap);
    } on GeminiHata catch (e) {
      _bot(e.mesaj(_dil));
    } catch (_) {
      _bot(t('Kamera açılamadı ya da fotoğraf alınamadı.', 'تعذّر فتح الكاميرا أو التقاط الصورة.'));
    } finally {
      if (mounted) setState(() => _dusunuyor = false);
    }
  }

  Future<void> _mik() async {
    if (_dinliyor) {
      await _stt.stop();
      setState(() => _dinliyor = false);
      return;
    }
    if (!_sttHazir) {
      _sttHazir = await _stt.initialize(onError: (e) {
        if (mounted) setState(() => _dinliyor = false);
      });
    }
    if (!_sttHazir) {
      _bildir(t('Mikrofon izni verilmedi ya da ses tanıma yok.', 'لم يُمنح إذن الميكروفون أو لا يوجد تعرف على الصوت.'));
      return;
    }
    await _tts.stop();
    setState(() => _dinliyor = true);
    await _stt.listen(
      localeId: _dil == 'ar' ? 'ar_SA' : 'tr_TR',
      onResult: (r) {
        _kontrol.text = r.recognizedWords;
        if (r.finalResult) {
          final m = r.recognizedWords.trim();
          _kontrol.clear();
          if (mounted) setState(() => _dinliyor = false);
          if (m.isNotEmpty) _gonder(m);
        }
      },
    );
  }

  Future<void> _anahtarDialog() async {
    if (!mounted) return;
    final c = TextEditingController(text: _gemini.anahtar);
    final sonuc = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kPanel,
        title: Text(t('Yapay zekâ anahtarı', 'مفتاح الذكاء الاصطناعي')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                t('Ücretsiz anahtarı aistudio.google.com/apikey adresinden alabilirsin. Anahtar sadece bu telefonda saklanır.',
                    'يمكنك الحصول على مفتاح مجاني من aistudio.google.com/apikey. يُحفظ المفتاح على هذا الهاتف فقط.'),
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              decoration: const InputDecoration(hintText: 'AIza...', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(t('Vazgeç', 'إلغاء'))),
          TextButton(
            onPressed: () => launchUrl(Uri.parse('https://aistudio.google.com/apikey'), mode: LaunchMode.externalApplication),
            child: Text(t('Anahtar al', 'احصل على مفتاح')),
          ),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(c.text.trim()), child: Text(t('Kaydet', 'حفظ'))),
        ],
      ),
    );
    if (sonuc != null && sonuc.isNotEmpty) {
      _gemini.anahtar = sonuc;
      await widget.p.setString('gemini_anahtar', sonuc);
      _bot(t('Anahtar kaydedildi efendim.', 'تم حفظ المفتاح يا سيدي.'));
    }
  }

  Widget _balon(Mesaj m) {
    final ar = kArapca.hasMatch(m.metin);
    return Align(
      alignment: m.bot ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.84),
        decoration: BoxDecoration(
          color: m.bot ? kPanel : const Color(0xFF0E3A4A),
          border: Border.all(color: m.bot ? const Color(0xFF123456) : kAna.withOpacity(0.5)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Directionality(
              textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
              child: SelectableText(m.metin, style: const TextStyle(fontSize: 15, height: 1.3)),
            ),
            const SizedBox(height: 2),
            Text('${m.pc ? '💻 ' : ''}${m.zaman}', style: const TextStyle(fontSize: 10, color: Colors.white38)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pcDurum = _pc == null
        ? t('Tek başına', 'وحدي')
        : (_pcBagli ? t('PC bağlı', 'الكمبيوتر متصل') : t('PC aranıyor...', 'جارٍ البحث عن الكمبيوتر...'));
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kPanel,
        titleSpacing: 12,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ÖMER AI', style: TextStyle(color: kAna, fontWeight: FontWeight.bold, letterSpacing: 3, fontSize: 18)),
            Text(pcDurum, style: TextStyle(fontSize: 11, color: _pcBagli ? Colors.greenAccent : Colors.white54)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: t('Sesli cevap', 'الرد الصوتي'),
            icon: Icon(_sesli ? Icons.volume_up : Icons.volume_off),
            onPressed: () {
              setState(() => _sesli = !_sesli);
              widget.p.setBool('sesli', _sesli);
              if (!_sesli) _tts.stop();
            },
          ),
          IconButton(tooltip: t('Kameradan soru çöz', 'حل سؤال بالكاميرا'), icon: const Icon(Icons.photo_camera), onPressed: _kameraSoru),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'anahtar') _anahtarDialog();
              if (v == 'pcbaglan') _pcBaglanSayfa();
              if (v == 'pckes') _pcKes();
              if (v == 'pcekran') _pcEkrani();
              if (v == 'dil') _yerelIsle(Sonuc(ozel: _dil == 'tr' ? 'dil:ar' : 'dil:tr'));
              if (v == 'hafiza') _gonder('hafızam');
              if (v == 'temizle') setState(() => _mesajlar.clear());
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'anahtar', child: Text(t('Yapay zekâ anahtarı', 'مفتاح الذكاء الاصطناعي'))),
              PopupMenuItem(value: 'pcbaglan', child: Text(t('PC\'ye bağlan', 'الاتصال بالكمبيوتر'))),
              if (_pc != null) PopupMenuItem(value: 'pcekran', child: Text(t('PC ekranını göster', 'عرض شاشة الكمبيوتر'))),
              if (_pc != null) PopupMenuItem(value: 'pckes', child: Text(t('PC bağlantısını kes', 'قطع الاتصال بالكمبيوتر'))),
              PopupMenuItem(value: 'dil', child: Text(t('Dili değiştir (Türkçe/Arapça)', 'تغيير اللغة (تركي/عربي)'))),
              PopupMenuItem(value: 'hafiza', child: Text(t('Hafızamı göster', 'عرض ذاكرتي'))),
              PopupMenuItem(value: 'temizle', child: Text(t('Sohbeti temizle', 'مسح المحادثة'))),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 200, width: double.infinity, child: DunyaGorunum()),
            if (_dusunuyor) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: _mesajlar.isEmpty
                  ? Center(child: Text(t('Bir şey söyle ya da yaz.', 'قل شيئاً أو اكتب.'), style: const TextStyle(color: Colors.white38)))
                  : ListView.builder(
                      controller: _kaydir,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: _mesajlar.length,
                      itemBuilder: (_, i) => _balon(_mesajlar[i]),
                    ),
            ),
            Container(
              color: kPanel,
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: _mik,
                    icon: Icon(_dinliyor ? Icons.stop : Icons.mic),
                    color: _dinliyor ? Colors.redAccent : kAna,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _kontrol,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (v) {
                        _kontrol.clear();
                        _gonder(v);
                      },
                      decoration: InputDecoration(
                        hintText: _dinliyor ? t('Dinliyorum...', 'أستمع...') : t('Komut yaz...', 'اكتب أمراً...'),
                        isDense: true,
                        border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(24))),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    onPressed: () {
                      final m = _kontrol.text;
                      _kontrol.clear();
                      _gonder(m);
                    },
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
