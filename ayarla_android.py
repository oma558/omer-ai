# flutter create'in ürettiği Android dosyalarına izinleri ekler (internet, mikrofon, düz HTTP ile yerel ağ bağlantısı).
import re

p = "android/app/src/main/AndroidManifest.xml"
s = open(p, encoding="utf-8").read()

izin = """<uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>
    <uses-permission android:name="android.permission.BLUETOOTH"/>
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
    <queries>
        <intent><action android:name="android.speech.RecognitionService"/></intent>
        <intent><action android:name="android.intent.action.TTS_SERVICE"/></intent>
        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="https"/></intent>
        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="tel"/></intent>
        <intent><action android:name="android.media.action.IMAGE_CAPTURE"/></intent>
    </queries>
    """
if "android.permission.INTERNET" not in s:
    s = s.replace("<application", izin + "<application", 1)
if "usesCleartextTraffic" not in s:
    s = s.replace("<application", '<application android:usesCleartextTraffic="true"', 1)
s = re.sub(r'android:label="[^"]*"', 'android:label="ÖMER AI"', s, count=1)
open(p, "w", encoding="utf-8").write(s)
print("AndroidManifest hazır")
