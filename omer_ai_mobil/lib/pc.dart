import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'yerel.dart';

const Color kArka = Color(0xFF050A14);
const Color kPanel = Color(0xFF0B1424);
const Color kAna = Color(0xFF00D4FF);

/// Bilgisayardaki ÖMER AI (Omer-GBT-v4.py) ile konuşan istemci.
class Baglanti {
  final String taban;
  final String token;
  Baglanti(this.taban, this.token);

  Map<String, String> get baslik => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  static String adresDuzelt(String girdi) {
    var a = girdi.trim();
    if (!a.startsWith('http')) a = 'http://$a';
    final u = Uri.parse(a);
    return Uri(scheme: u.scheme, host: u.host, port: u.hasPort ? u.port : 8765).toString();
  }

  static Future<String?> eslestir(String taban, String pin) async {
    final r = await http
        .post(Uri.parse('$taban/api/eslestir'),
            headers: {'Content-Type': 'application/json'}, body: jsonEncode({'pin': pin}))
        .timeout(const Duration(seconds: 8));
    if (r.statusCode == 200) {
      return (jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>)['token'] as String?;
    }
    if (r.statusCode == 429) throw 'Çok fazla yanlış deneme, 5 dakika bekle.';
    throw 'PIN yanlış ya da süresi dolmuş. PC\'de "telefon eşleştir" yaz.';
  }

  Future<void> komut(String metin, bool ses) async {
    final r = await http
        .post(Uri.parse('$taban/api/komut'), headers: baslik, body: jsonEncode({'metin': metin, 'ses': ses}))
        .timeout(const Duration(seconds: 8));
    if (r.statusCode == 401) throw 'PC eşleşmesi geçersiz, yeniden bağlan.';
    if (r.statusCode != 200) throw 'Komut PC\'ye gönderilemedi (${r.statusCode}).';
  }

  Future<Uint8List?> resim(String yol) async {
    try {
      final r = await http.get(Uri.parse('$taban$yol'), headers: baslik).timeout(const Duration(seconds: 10));
      return r.statusCode == 200 ? r.bodyBytes : null;
    } catch (_) {
      return null;
    }
  }

  /// PC'den gelen olay akışı (SSE). Bağlantı koparsa akış biter.
  Stream<Map<String, dynamic>> olaylar({int son = 0}) async* {
    final client = http.Client();
    try {
      final istek = http.Request('GET', Uri.parse('$taban/api/olaylar?son=$son'));
      istek.headers.addAll(baslik);
      final yanit = await client.send(istek).timeout(const Duration(seconds: 10));
      if (yanit.statusCode != 200) throw 'Bağlantı reddedildi (${yanit.statusCode})';
      await for (final satir in yanit.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (satir.startsWith('data: ')) {
          yield jsonDecode(satir.substring(6)) as Map<String, dynamic>;
        }
      }
    } finally {
      client.close();
    }
  }
}

/// PC eşleştirme sayfası. Başarılı olursa true döndürerek kapanır.
class PcEslestirSayfa extends StatefulWidget {
  final String dil;
  const PcEslestirSayfa({super.key, required this.dil});
  @override
  State<PcEslestirSayfa> createState() => _PcEslestirState();
}

class _PcEslestirState extends State<PcEslestirSayfa> {
  final _adres = TextEditingController();
  final _pin = TextEditingController();
  bool _yukleniyor = false;
  String _hata = '';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final t = p.getString('pc_taban');
      if (t != null && mounted) _adres.text = t.replaceFirst('http://', '');
    });
  }

  @override
  void dispose() {
    _adres.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _baglan() async {
    final dil = widget.dil;
    setState(() {
      _yukleniyor = true;
      _hata = '';
    });
    try {
      final taban = Baglanti.adresDuzelt(_adres.text);
      final token = await Baglanti.eslestir(taban, _pin.text.trim());
      if (token == null) throw 'Eşleşme başarısız.';
      final p = await SharedPreferences.getInstance();
      await p.setString('pc_taban', taban);
      await p.setString('pc_token', token);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _hata = e is String
          ? e
          : tt(dil, 'Bilgisayara ulaşılamadı. Aynı Wi-Fi\'de misin? Adres doğru mu? PC\'de program açık mı?',
              'تعذّر الوصول إلى الكمبيوتر. هل أنتما على نفس الشبكة؟ هل العنوان صحيح؟ هل البرنامج مفتوح؟'));
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dil = widget.dil;
    return Scaffold(
      appBar: AppBar(backgroundColor: kPanel, title: Text(tt(dil, 'PC\'ye bağlan', 'الاتصال بالكمبيوتر'))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(
                  tt(dil, 'PC\'deki ÖMER AI açılınca sohbette adres ve PIN yazar. Telefon ve PC aynı Wi-Fi\'de olsun.',
                      'عند فتح عمر AI على الكمبيوتر يظهر العنوان والرمز في المحادثة. يجب أن يكونا على نفس الشبكة.'),
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 20),
              TextField(
                controller: _adres,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                    labelText: tt(dil, 'Bilgisayar adresi', 'عنوان الكمبيوتر'),
                    hintText: '192.168.1.20:8765',
                    border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _pin,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                    labelText: tt(dil, 'PIN (PC ekranında yazar)', 'الرمز (يظهر على شاشة الكمبيوتر)'),
                    border: const OutlineInputBorder()),
              ),
              if (_hata.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_hata, style: const TextStyle(color: Colors.redAccent), textAlign: TextAlign.center),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _yukleniyor ? null : _baglan,
                  child: _yukleniyor
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(tt(dil, 'Bağlan', 'اتصال')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
