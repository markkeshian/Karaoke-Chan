// lib/core/services/remote_server.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

import 'package:karaoke_chan/features/library/data/song_repository.dart';
import 'package:karaoke_chan/features/queue/data/queue_notifier.dart';
import 'package:karaoke_chan/features/queue/data/queue_repository.dart';

class RemoteQueueServer {
  RemoteQueueServer(this._ref);

  final Ref _ref;
  HttpServer? _server;
  static const int port = 7331;

  Future<String?> get localIp async {
    try {
      return await NetworkInfo().getWifiIP();
    } catch (_) {
      return null;
    }
  }

  Future<String?> get queueUrl async {
    final ip = await localIp;
    if (ip == null) return null;
    return 'http://$ip:$port/queue-ui';
  }

  Future<void> start() async {
    if (_server != null) return;

    final router = Router()
      ..get('/songs', _handleGetSongs)
      ..get('/queue', _handleGetQueue)
      ..post('/queue', _handlePostQueue)
      ..get('/queue-ui', _handleGetUi);

    final handler =
        const Pipeline().addMiddleware(_cors()).addHandler(router.call);

    _server = await io.serve(handler, InternetAddress.anyIPv4, port);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  bool get isRunning => _server != null;

  // ── Handlers ──────────────────────────────────────────────────────────────

  Future<Response> _handleGetSongs(Request request) async {
    final q = request.url.queryParameters['q'] ?? '';
    final repo = _ref.read(songRepositoryProvider);
    final songs = await repo.getAll(search: q.isEmpty ? null : q);
    final body = jsonEncode(songs.map((s) => {
          'id': s.id,
          'title': s.title,
          'artist': s.artist ?? '',
          'folder': s.folderName ?? '',
          'duration': s.displayDuration,
        }).toList());
    return Response.ok(body, headers: {'content-type': 'application/json'});
  }

  Future<Response> _handleGetQueue(Request request) async {
    final entries = await _ref.read(queueRepositoryProvider).getActive();
    final body = jsonEncode(entries.map((e) => {
          'position': e.position,
          'song': e.song?.title ?? 'Unknown',
          'artist': e.song?.artist ?? '',
          'status': e.status.name,
        }).toList());
    return Response.ok(body, headers: {'content-type': 'application/json'});
  }

  Future<Response> _handlePostQueue(Request request) async {
    try {
      final raw = await request.readAsString();
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final songId = data['song_id'];
      if (songId == null) {
        return Response(400, body: '{"error":"song_id required"}',
            headers: {'content-type': 'application/json'});
      }
      await _ref.read(queueNotifierProvider.notifier).enqueue(songId as int);
      return Response.ok('{"ok":true}',
          headers: {'content-type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
          body: '{"error":"$e"}',
          headers: {'content-type': 'application/json'});
    }
  }

  Future<Response> _handleGetUi(Request request) async {
    final ip = await localIp ?? 'localhost';
    final html = _buildMobileUi(ip);
    return Response.ok(html, headers: {'content-type': 'text/html; charset=utf-8'});
  }

  String _buildMobileUi(String ip) => '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>🎤 Karaoke Chan — Remote Queue</title>
<style>
  *{box-sizing:border-box;margin:0;padding:0}
  body{background:#0d0d1a;color:#fff;font-family:system-ui,sans-serif;padding:16px;min-height:100vh}
  h1{font-size:1.4rem;margin-bottom:4px;color:#BB86FC}
  .sub{color:#666;font-size:.85rem;margin-bottom:20px}
  input[type=text]{width:100%;padding:12px;background:#1a1a2e;border:1px solid #333;border-radius:10px;color:#fff;font-size:1rem;margin-bottom:12px;outline:none}
  input[type=text]:focus{border-color:#BB86FC}
  .song-list{list-style:none}
  .song-item{background:#1a1a2e;border-radius:10px;padding:12px 16px;margin-bottom:8px;cursor:pointer;border:1px solid transparent;transition:.15s}
  .song-item:active{border-color:#BB86FC;background:#23234a}
  .song-title{font-weight:600;font-size:.95rem}
  .song-sub{color:#888;font-size:.8rem;margin-top:2px}
  .queue-section{margin-top:28px}
  .queue-section h2{font-size:1rem;color:#BB86FC;margin-bottom:10px}
  .queue-item{background:#12122a;border-radius:8px;padding:10px 14px;margin-bottom:6px;display:flex;align-items:center;gap:10px}
  .q-num{background:#BB86FC22;color:#BB86FC;border-radius:50%;width:28px;height:28px;display:flex;align-items:center;justify-content:center;font-weight:700;font-size:.85rem;flex-shrink:0}
  .toast{position:fixed;bottom:24px;left:50%;transform:translateX(-50%) translateY(60px);background:#BB86FC;color:#000;padding:10px 20px;border-radius:20px;font-weight:600;transition:.3s;opacity:0}
  .toast.show{transform:translateX(-50%) translateY(0);opacity:1}
  .empty{color:#555;text-align:center;padding:24px 0;font-size:.9rem}
  .status{text-align:center;color:#555;font-size:.8rem;padding:8px}
</style>
</head>
<body>
<h1>🎤 Karaoke Chan</h1>
<p class="sub">Add songs to the queue from your phone</p>

<input type="text" id="search" placeholder="Search songs…" oninput="doSearch(this.value)" autocomplete="off">
<ul class="song-list" id="results"></ul>
<p class="status" id="status">Type to search songs…</p>

<div class="queue-section">
  <h2>Queue</h2>
  <div id="queue-list"><p class="empty">Queue is empty</p></div>
</div>

<div class="toast" id="toast"></div>

<script>
const BASE = 'http://$ip:$port';
let debounce;

async function doSearch(q) {
  clearTimeout(debounce);
  debounce = setTimeout(async () => {
    if (!q.trim()) { document.getElementById('results').innerHTML=''; document.getElementById('status').textContent='Type to search songs…'; return; }
    document.getElementById('status').textContent='Searching…';
    try {
      const r = await fetch(BASE+'/songs?q='+encodeURIComponent(q));
      const songs = await r.json();
      renderSongs(songs);
    } catch(e) { document.getElementById('status').textContent='Error connecting to Karaoke Chan'; }
  }, 350);
}

function renderSongs(songs) {
  const ul = document.getElementById('results');
  const st = document.getElementById('status');
  if (!songs.length) { ul.innerHTML=''; st.textContent='No songs found'; return; }
  st.textContent='';
  ul.innerHTML = songs.map(s => \`<li class="song-item" onclick="addSong(\${s.id})">
    <div class="song-title">\${esc(s.title)}</div>
    <div class="song-sub">\${esc(s.artist || s.folder)}</div>
  </li>\`).join('');
}

async function addSong(id) {
  try {
    const r = await fetch(BASE+'/queue', {
      method:'POST',
      headers:{'Content-Type':'application/json'},
      body: JSON.stringify({song_id: id})
    });
    if (r.ok) { showToast('Added to queue!'); loadQueue(); }
    else { showToast('Failed to add'); }
  } catch(e) { showToast('Error: '+e.message); }
}

async function loadQueue() {
  try {
    const r = await fetch(BASE+'/queue');
    const entries = await r.json();
    const el = document.getElementById('queue-list');
    if (!entries.length) { el.innerHTML='<p class="empty">Queue is empty</p>'; return; }
    el.innerHTML = entries.map(e => \`<div class="queue-item">
      <div class="q-num">\${e.position}</div>
      <div>
        <div style="font-weight:600;font-size:.9rem">\${esc(e.song)}</div>
        <div style="color:#888;font-size:.8rem">\${esc(e.artist)}</div>
      </div>
    </div>\`).join('');
  } catch(_) {}
}

function showToast(msg) {
  const t = document.getElementById('toast');
  t.textContent = msg;
  t.classList.add('show');
  setTimeout(() => t.classList.remove('show'), 2500);
}

function esc(s) {
  return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}

loadQueue();
setInterval(loadQueue, 5000);
</script>
</body>
</html>''';

  Middleware _cors() => (innerHandler) => (request) async {
        final response = await innerHandler(request);
        return response.change(headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type',
        });
      };
}

// ── Providers ─────────────────────────────────────────────────────────────────

final remoteServerProvider = Provider<RemoteQueueServer>((ref) {
  final server = RemoteQueueServer(ref);
  ref.onDispose(server.stop);
  return server;
});

final remoteServerActiveProvider =
    NotifierProvider<RemoteServerNotifier, bool>(RemoteServerNotifier.new);

class RemoteServerNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  Future<void> toggle() async {
    final server = ref.read(remoteServerProvider);
    if (state) {
      await server.stop();
      state = false;
    } else {
      await server.start();
      state = true;
    }
  }
}
