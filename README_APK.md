# ÖMER AI — Telefon (APK)

Telefon uygulaması TEK BAŞINA tam çalışan bir asistandır; istersen bilgisayardaki ÖMER AI'ya da bağlanır.

## Telefonda tek başına neler var
- Sohbet (kendi yapay zekâ anahtarınla), güncel bilgi ve haber (Google Arama), **skor modu** ("fener maçı", "barca" → anında skor)
- Sesli komut (mikrofon) ve sesli cevap, Türkçe / Arapça
- Gerçek NASA dokulu Dünya: gerçek saate göre gündüz/gece çizgisi, şehir ışıkları, gerçek ay konumu ve evresi, kamera çoğu zaman Türkiye'de
- Kameradan matematik sorusu çözme (📷 düğmesi)
- Hafıza (`hatırla:`, `unut:`, `hafızam`), takvim / hatırlatıcı (`hatırlat: toplantı yarın 14:00`), kişiler (`kişi ekle: Ahmet|0555...`)
- WhatsApp (`whatsapp Ahmet | merhaba` → WhatsApp açılır, mesaj hazırdır, Gönder'e sen basarsın), arama (`ara: Ahmet`), YouTube/Spotify (`youtube lofi`, `spotify tarkan`)

## Bilgisayara komut göndermek
Cümleyi **"bilgisayarda ..."** diye başlat: komutu PC yapar (program aç, ses, WhatsApp masaüstü, mail, ekran izleme...) ve cevap telefona gelir.
Örnek: "bilgisayarda chrome aç", "bilgisayarda ses kapat". Menüden "PC ekranını göster" ile PC'nin ekranını da görebilirsin.

Önce bir kez eşleştir: PC'de `Omer-GBT-v4.py` açılınca sohbette adres ve PIN yazar → telefonda menü → "PC'ye bağlan".
Komutlar (PC'de): `telefon eşleştir`, `telefon sıfırla`, `telefon durum`, `telefon kapat`, `telefon aç`.
PIN tek kullanımlıktır, 10 dk geçerlidir; 5 yanlışta 5 dk kilitlenir. Evin dışından bağlanmak için ücretsiz Tailscale kur (router'da port açma).

## İlk açılış
Yapay zekâ anahtarı sorar: ücretsiz anahtarı https://aistudio.google.com/apikey adresinden al; sadece telefonda saklanır.

## APK'yı derle (ücretsiz, bilgisayara Flutter kurmadan)
1. GitHub'da boş bir depo aç, bu klasörün içindekileri (lib, assets, pubspec.yaml, ayarla_android.py, .github, README) yükle.
2. Depoda Actions → "APK derle" → Run workflow. ~5-8 dk sonra "omer-ai-apk" dosyasını indir (içinde app-release.apk).
3. APK'yı telefona at, "bilinmeyen kaynaklardan yükle" izni ver, kur.

Kendi bilgisayarında derlemek istersen (Flutter kuruluysa):
```
flutter create --platforms=android --org com.labrix --project-name omer_ai tmp_proj
cp -r tmp_proj/android ./android && rm -rf tmp_proj
python3 ayarla_android.py
flutter pub get
flutter build apk --release
```

## Sınırlar
- Android, normal bir uygulamanın telefon ekranını sürekli izlemesine izin vermez; bu yüzden "ekran izleme" PC'de çalışır, telefonda yerine kamera ile soru çözme vardır.
- Hatırlatıcılar uygulama açıkken çalar (arka plan bildirimi yok).
- Bilgisayar işleri sadece PC açık ve aynı ağdayken (ya da Tailscale ile) çalışır.
