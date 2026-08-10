// lib/services/firebase_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_app_check/firebase_app_check.dart';
import '../game/game_state.dart';

// Set these via --dart-define or a .env loader at build time.
const _kApiKey = String.fromEnvironment('FIREBASE_API_KEY');
const _kDbUrl  = String.fromEnvironment('FIREBASE_DB_URL');
const _kAuthBase = 'https://identitytoolkit.googleapis.com/v1/accounts';

final firebaseServiceProvider = Provider((ref) => FirebaseService());

class FirebaseService {
  // NEW: every request now carries an App Check token, proving it came
  // from this real app (not a hand-crafted script hitting the REST API
  // directly). This is fetched fresh per-request since App Check tokens
  // are short-lived and the SDK caches/refreshes them internally, so this
  // call is cheap in practice. If the token fetch fails for any reason,
  // requests still go out without it rather than blocking the user —
  // App Check is currently in monitoring mode (unenforced) in the
  // Firebase console, so this is safe; once enforcement is turned on for
  // Realtime Database, a missing token will be rejected server-side.
  Future<Map<String, String>> _headers() async {
    final headers = {'Content-Type': 'application/json'};
    try {
      final token = await FirebaseAppCheck.instance.getToken();
      if (token != null) headers['X-Firebase-AppCheck'] = token;
    } catch (e) {
      debugPrint('App Check token fetch failed: $e');
    }
    return headers;
  }

  // ── Auth ──────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> signIn(String email, String pw) =>
      _authReq('signInWithPassword', email, pw);

  Future<Map<String, dynamic>?> signUp(String email, String pw) =>
      _authReq('signUp', email, pw);

  Future<Map<String, dynamic>?> _authReq(String ep, String email, String pw) async {
    try {
      final res = await http.post(
        Uri.parse('$_kAuthBase:$ep?key=$_kApiKey'),
        headers: await _headers(),
        body: jsonEncode({'email': email, 'password': pw, 'returnSecureToken': true}),
      );
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Auth error: $e');
      return null;
    }
  }

  // ── User data ─────────────────────────────────────────────────────────────
  Future<Map<dynamic, dynamic>?> getUser(String uid, String tok) =>
      _get('users/$uid', tok);

  Future<void> saveUser(UserData ud) async {
    if (ud.idToken == null || ud.uid == 'offline') return;
    await _put('users/${ud.uid}', ud.toJson(), ud.idToken!);
  }

  // ── Rooms ─────────────────────────────────────────────────────────────────
  Future<Map<dynamic, dynamic>?> getRoom(String code, String tok) =>
      _get('rooms/$code', tok);

  Future<void> putRoom(String code, Map<String, dynamic> data, String tok) =>
      _put('rooms/$code', data, tok);

  Future<void> patchRoom(String code, Map<String, dynamic> data, String tok) =>
      _patch('rooms/$code', data, tok);

  // ── Tournaments ───────────────────────────────────────────────────────────
  Future<Map<dynamic, dynamic>?> getTournaments(String tok) =>
      _get('tournaments', tok);

  Future<void> putTournament(String tid, Map<String, dynamic> data, String tok) =>
      _put('tournaments/$tid', data, tok);

  Future<void> joinTournament(String tid, String uid, Map<String, dynamic> data, String tok) =>
      _patch('tournaments/$tid/players/$uid', data, tok);

  // ── Leaderboard ───────────────────────────────────────────────────────────
  Future<Map<dynamic, dynamic>?> getLeaderboard(String tok) =>
      _get('users', tok);

  // ── HTTP helpers ──────────────────────────────────────────────────────────
  Future<Map<dynamic, dynamic>?> _get(String path, String tok) async {
    try {
      final res = await http.get(
        Uri.parse('$_kDbUrl/$path.json?auth=$tok'),
        headers: await _headers(),
      );
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      return body is Map ? body : null;
    } catch (e) {
      debugPrint('FB GET error: $e');
      return null;
    }
  }

  Future<void> _put(String path, Map<String, dynamic> data, String tok) async {
    try {
      await http.put(
        Uri.parse('$_kDbUrl/$path.json?auth=$tok'),
        headers: await _headers(),
        body: jsonEncode(data),
      );
    } catch (e) {
      debugPrint('FB PUT error: $e');
    }
  }

  Future<void> _patch(String path, Map<String, dynamic> data, String tok) async {
    try {
      await http.patch(
        Uri.parse('$_kDbUrl/$path.json?auth=$tok'),
        headers: await _headers(),
        body: jsonEncode(data),
      );
    } catch (e) {
      debugPrint('FB PATCH error: $e');
    }
  }
}
