// z2roN Net - 플랫폼별 네트워크 정보 읽기
//   Android : android_patch/MainActivity.kt (MethodChannel 'z2ron/net')
//   Windows : PowerShell / netsh 를 실행해서 같은 모양의 데이터를 만들어 줍니다. (플러그인·C++ 코드 필요 없음)
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

abstract class NetBridge {
  Future<bool> requestLocation();
  Future<Map<String, dynamic>> info();
  Future<List<dynamic>> scanWifi();
  Future<void> openUrl(String url);
}

final NetBridge bridge = Platform.isWindows ? WinBridge() : AndroidBridge();

// ------------------------------------------------------------------ Android
class AndroidBridge implements NetBridge {
  static const MethodChannel _ch = MethodChannel('z2ron/net');

  @override
  Future<bool> requestLocation() async {
    try {
      return (await _ch.invokeMethod<bool>('requestLocation')) ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>> info() async {
    final m = await _ch.invokeMethod<Map>('info');
    return m == null ? <String, dynamic>{} : Map<String, dynamic>.from(m);
  }

  @override
  Future<List<dynamic>> scanWifi() async {
    final r = await _ch.invokeMethod<List>('scanWifi');
    return r ?? <dynamic>[];
  }

  @override
  Future<void> openUrl(String url) async {
    await _ch.invokeMethod('openUrl', {'url': url});
  }
}

// ------------------------------------------------------------------ Windows
const List<String> _psLines = [
  r"$ErrorActionPreference='SilentlyContinue'",
  r"$os=Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber,OSArchitecture",
  r"$cs=Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer,Model",
  r"$ad=@(Get-NetAdapter | Where-Object {$_.Status -eq 'Up'} | Select-Object Name,InterfaceDescription,LinkSpeed,PhysicalMediaType,Virtual)",
  r"$mt=@(Get-NetIPInterface -AddressFamily IPv4 | Select-Object InterfaceIndex,InterfaceMetric)",
  r"$pf=@(Get-NetConnectionProfile | Select-Object Name,InterfaceAlias)",
  r"$cf=@(Get-NetIPConfiguration | Where-Object {$_.NetAdapter.Status -eq 'Up'} | ForEach-Object {[pscustomobject]@{Name=$_.InterfaceAlias;Index=$_.InterfaceIndex;IPv4=(@($_.IPv4Address.IPAddress) -join ',');Prefix=(@($_.IPv4Address.PrefixLength))[0];Gateway=(@($_.IPv4DefaultGateway.NextHop) -join ',');DNS=(@($_.DNSServer.ServerAddresses) -join ',')}})",
  r"[pscustomobject]@{os=$os;cs=$cs;adapters=$ad;metrics=$mt;profiles=$pf;cfg=$cf} | ConvertTo-Json -Depth 4 -Compress",
];

class WinBridge implements NetBridge {
  @override
  Future<bool> requestLocation() async => true;

  @override
  Future<void> openUrl(String url) async {
    await Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
  }

  static Future<String> _run(String exe, List<String> args, {Encoding? enc, int seconds = 20}) async {
    try {
      final r = await Process.run(exe, args, stdoutEncoding: enc ?? systemEncoding, stderrEncoding: enc ?? systemEncoding)
          .timeout(Duration(seconds: seconds));
      return r.stdout.toString();
    } catch (_) {
      return '';
    }
  }

  static Future<String> _ps(String script) => _run(
      'powershell', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', '[Console]::OutputEncoding=[Text.Encoding]::UTF8; ' + script],
      enc: utf8, seconds: 40);

  static List<Map<String, dynamic>> _rows(dynamic v) {
    if (v == null) return <Map<String, dynamic>>[];
    final List<dynamic> src = v is List ? v : <dynamic>[v];
    return src.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static bool _isIp(String s) => InternetAddress.tryParse(s) != null;

  static double? _mbps(dynamic s) {
    final m = RegExp(r'([\d.]+)\s*([GMK]?)\s*(?:bps|bit/s)', caseSensitive: false).firstMatch('${s ?? ''}');
    if (m == null) return null;
    final v = double.tryParse(m.group(1)!);
    if (v == null) return null;
    final u = m.group(2)!.toUpperCase();
    return u == 'G' ? v * 1000 : (u == 'K' ? v / 1000 : v);
  }

  static String _kind(Map<String, dynamic> a) {
    final media = '${a['PhysicalMediaType'] ?? ''}';
    final desc = '${a['InterfaceDescription'] ?? ''}'.toLowerCase();
    if (RegExp(r'vpn|wireguard|tailscale|zerotier|wintun|tap-|tunnel').hasMatch(desc)) return 'vpn';
    if (a['Virtual'] == true || RegExp(r'virtual|vmware|hyper-v|vethernet|loopback|bluetooth').hasMatch(desc)) return 'other';
    if (media.contains('802.11') || RegExp(r'wi-?fi|wireless|802\.11|무선').hasMatch(desc)) return 'wifi';
    if (RegExp(r'wwan|mobile|cellular|lte').hasMatch(desc)) return 'cellular';
    return 'ethernet';
  }

  static int? _freq(int? chan, String? band) {
    if (chan == null) return null;
    if (band == '6') return 5950 + 5 * chan;
    if (band == '5') return 5000 + 5 * chan;
    if (band == '2.4') return chan == 14 ? 2484 : 2407 + 5 * chan;
    if (chan <= 14) return chan == 14 ? 2484 : 2407 + 5 * chan;
    return 5000 + 5 * chan;
  }

  static String _sec(String v) {
    if (v.isEmpty) return '';
    if (v.contains('WPA3') || v.contains('SAE')) return 'WPA3';
    if (v.contains('WPA2')) return 'WPA2';
    if (v.contains('WPA')) return 'WPA';
    if (v.contains('WEP')) return 'WEP';
    return '개방';
  }

  /// `netsh wlan show interfaces` (영어/한글 공통) -> ssid, bssid, pct(신호 %), chan, band, rx, tx
  static Map<String, dynamic> parseNetshInterfaces(String txt) {
    final d = <String, dynamic>{};
    final rates = <double>[];
    for (final line in const LineSplitter().convert(txt)) {
      final i = line.indexOf(':');
      if (i < 0) continue;
      final k = line.substring(0, i).trim();
      final v = line.substring(i + 1).trim();
      if ((k == 'Name' || k == '이름') && d.isNotEmpty) break; // 두 번째 무선 어댑터부터는 무시
      if (k == 'SSID') {
        if (v.isNotEmpty) d['ssid'] = v;
      } else if (k == 'BSSID' || k == 'AP BSSID') {
        if (v.isNotEmpty) d['bssid'] = v;
      } else if (k.contains('Mbps') || v.contains('Mbps')) {
        final m = RegExp(r'([\d.]+)').firstMatch(v);
        if (m != null) {
          final x = double.tryParse(m.group(1)!);
          if (x != null) rates.add(x);
        }
      } else if (v.endsWith('%')) {
        final m = RegExp(r'^(\d+)%').firstMatch(v);
        if (m != null) d['pct'] = int.parse(m.group(1)!);
      } else if (k == 'Channel' || k == '채널') {
        final c = int.tryParse(v);
        if (c != null) d['chan'] = c;
      } else if (v.contains('GHz')) {
        final m = RegExp(r'(\d(?:\.\d)?)\s*GHz').firstMatch(v);
        if (m != null) d['band'] = m.group(1);
      }
    }
    if (rates.isNotEmpty) {
      d['rx'] = rates[0];
      d['tx'] = rates.length > 1 ? rates[1] : rates[0];
    }
    return d;
  }

  /// `netsh wlan show networks mode=bssid` -> [{ssid,bssid,level(dBm),freq,sec}]
  static List<Map<String, dynamic>> parseNetshNetworks(String txt) {
    final out = <Map<String, dynamic>>[];
    String ssid = '';
    String sec = '';
    Map<String, dynamic>? cur;
    for (final line in const LineSplitter().convert(txt)) {
      final t = line.trim();
      final mSsid = RegExp(r'^SSID\s+\d+\s*:\s*(.*)$').firstMatch(t);
      if (mSsid != null) {
        if (cur != null) out.add(cur);
        cur = null;
        ssid = mSsid.group(1)!.trim();
        sec = '';
        continue;
      }
      final mB = RegExp(r'^BSSID\s+\d+\s*:\s*(\S+)').firstMatch(t);
      if (mB != null) {
        if (cur != null) out.add(cur);
        cur = <String, dynamic>{'ssid': ssid, 'bssid': mB.group(1)!, 'level': -100, 'freq': null, 'sec': sec, '_ch': null, '_band': null};
        continue;
      }
      final i = t.indexOf(':');
      if (i < 0) continue;
      final k = t.substring(0, i).trim();
      final v = t.substring(i + 1).trim();
      final c = cur;
      if (c == null) {
        if (RegExp(r'Authentication|인증').hasMatch(k)) sec = _sec(v);
        continue;
      }
      if (v.endsWith('%')) {
        final m = RegExp(r'^(\d+)%').firstMatch(v);
        if (m != null) c['level'] = (int.parse(m.group(1)!) / 2 - 100).round();
      } else if (k == 'Channel' || k == '채널') {
        c['_ch'] = int.tryParse(v);
      } else if (v.contains('GHz')) {
        final m = RegExp(r'(\d(?:\.\d)?)\s*GHz').firstMatch(v);
        if (m != null) c['_band'] = m.group(1);
      }
    }
    if (cur != null) out.add(cur);
    for (final c in out) {
      c['freq'] = _freq(c['_ch'] as int?, c['_band'] as String?);
      c.remove('_ch');
      c.remove('_band');
    }
    return out;
  }

  @override
  Future<List<dynamic>> scanWifi() async {
    final txt = await _run('netsh', ['wlan', 'show', 'networks', 'mode=bssid'], seconds: 25);
    final out = parseNetshNetworks(txt);
    if (out.isEmpty) {
      throw 'Wi-Fi 목록을 읽지 못했습니다. (Wi-Fi 어댑터가 꺼져 있거나 Windows 설정의 위치 서비스가 꺼져 있을 수 있습니다)';
    }
    return out;
  }

  @override
  Future<Map<String, dynamic>> info() async {
    final m = <String, dynamic>{
      'deviceName': Platform.localHostname,
      'hasLocation': true,
      'locationOn': true,
      'osText': Platform.operatingSystemVersion,
      'kernel': Platform.operatingSystemVersion,
    };
    final raw = await _ps(_psLines.join('; '));
    final st = raw.indexOf('{');
    Map<String, dynamic> j = <String, dynamic>{};
    if (st >= 0) {
      try {
        j = Map<String, dynamic>.from(jsonDecode(raw.substring(st)) as Map);
      } catch (_) {}
    }

    final os = _rows(j['os']);
    if (os.isNotEmpty) {
      final cap = '${os.first['Caption'] ?? 'Windows'}'.replaceFirst('Microsoft ', '').trim();
      final arch = '${os.first['OSArchitecture'] ?? ''}';
      m['osText'] = '$cap (버전 ${os.first['Version'] ?? '-'}${arch.isEmpty ? '' : ', $arch'})';
      m['kernel'] = '${os.first['Version'] ?? ''} (빌드 ${os.first['BuildNumber'] ?? ''})';
    }
    final cs = _rows(j['cs']);
    if (cs.isNotEmpty) {
      m['manufacturer'] = '${cs.first['Manufacturer'] ?? ''}';
      m['model'] = '${cs.first['Model'] ?? ''}';
    }

    final byName = <String, Map<String, dynamic>>{};
    for (final a in _rows(j['adapters'])) {
      byName['${a['Name']}'] = a;
    }
    final metric = <String, int>{};
    for (final x in _rows(j['metrics'])) {
      final v = x['InterfaceMetric'];
      metric['${x['InterfaceIndex']}'] = v is num ? v.toInt() : 9999;
    }

    final cands = <Map<String, dynamic>>[];
    final ifs = <String>[];
    for (final c in _rows(j['cfg'])) {
      final ip = '${c['IPv4'] ?? ''}'.split(',').first.trim();
      if (!_isIp(ip)) continue;
      final a = byName['${c['Name']}'] ?? <String, dynamic>{};
      final gw = '${c['Gateway'] ?? ''}'.split(',').first.trim();
      final p = c['Prefix'];
      ifs.add('${c['Name']}: $ip');
      cands.add(<String, dynamic>{
        'name': '${c['Name']}',
        'ip': ip,
        'prefix': p is num ? p.toInt() : 24,
        'gw': _isIp(gw) ? gw : '',
        'dns': '${c['DNS'] ?? ''}'.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty && _isIp(e)).toList(),
        'kind': _kind(a),
        'metric': metric['${c['Index']}'] ?? 9999,
        'link': _mbps(a['LinkSpeed']),
      });
    }

    int rank(Map<String, dynamic> c) {
      final k = c['kind'] as String;
      return ((k == 'vpn' || k == 'other') ? 1000 : 0) + ((c['gw'] as String).isEmpty ? 500 : 0) + (c['metric'] as int);
    }

    if (cands.isEmpty) {
      // PowerShell 을 쓸 수 없을 때: dart:io 로 최소한의 정보만 읽기
      try {
        for (final ni in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
          for (final a in ni.addresses) {
            if (!a.isLoopback && !a.address.startsWith('169.254.')) {
              ifs.add('${ni.name}: ${a.address}');
              if (m['localIp'] == null) {
                m['localIp'] = a.address;
                m['iface'] = ni.name;
              }
            }
          }
        }
      } catch (_) {}
      m['transport'] = m['localIp'] == null ? 'none' : 'other';
      m['prefix'] = 24;
      m['dns'] = <String>[];
      m['ifaces'] = ifs;
      return m;
    }

    cands.sort((a, b) => rank(a).compareTo(rank(b)));
    final p = cands.first;
    final kind = p['kind'] as String;
    m['transport'] = kind;
    m['localIp'] = p['ip'];
    m['prefix'] = p['prefix'];
    m['gateway'] = (p['gw'] as String).isEmpty ? null : p['gw'];
    m['iface'] = p['name'];
    m['dns'] = p['dns'];
    m['ifaces'] = ifs;

    final link = p['link'] as double?;
    if (kind == 'wifi') {
      final w = parseNetshInterfaces(await _run('netsh', ['wlan', 'show', 'interfaces']));
      if (w['ssid'] != null) {
        m['ssid'] = w['ssid'];
      } else {
        String? prof;
        for (final x in _rows(j['profiles'])) {
          if ('${x['InterfaceAlias']}' == p['name']) prof = '${x['Name']}';
        }
        if (prof != null && prof.isNotEmpty) {
          m['ssid'] = '$prof (연결 프로필 이름)';
        } else {
          m['ssidHint'] = '(Windows 설정 > 개인정보 및 보안 > 위치 에서 위치 서비스를 켜면 보입니다)';
        }
      }
      if (w['bssid'] != null) m['bssid'] = w['bssid'];
      final tx = w['tx'] as double?;
      final rx = w['rx'] as double?;
      final sp = tx ?? link;
      if (sp != null) m['linkSpeed'] = sp.round();
      if (rx != null) m['rxSpeed'] = rx.round();
      if (tx != null) m['txSpeed'] = tx.round();
      final pct = w['pct'] as int?;
      if (pct != null) m['rssi'] = (pct / 2 - 100).round();
      final f = _freq(w['chan'] as int?, w['band'] as String?);
      if (f != null) m['freq'] = f;
    } else if (link != null) {
      m['linkSpeed'] = link.round();
    }
    return m;
  }
}
