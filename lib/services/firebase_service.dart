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

  // TEMP DIAGNOSTIC (revert once the silent-failure cause below is found
  // and fixed — see the matching note in login_screen.dart's
  // _forgotPassword()): returns the raw HTTP status and body alongside
  // success, instead of just a bool, so the caller can show *why* a reset
  // request failed rather than only ever showing the generic "if an
  // account exists…" message. That generic message is the right
  // long-term behavior (avoids leaking which emails are registered) —
  // this richer return is only here to diagnose why nothing is being
  // sent at all right now. Once confirmed working, collapse this back
  // to `Future<bool>` returning `res.statusCode == 200`.
  Future<(bool ok, int status, String body)> sendPasswordReset(String email) async {
    try {
      final res = await http.post(
        Uri.parse('$_kAuthBase:sendOobCode?key=$_kApiKey'),
        headers: await _headers(),
        body: jsonEncode({
          'requestType': 'PASSWORD_RESET',
          'email': email,
        }),
      );
      if (res.statusCode != 200) {
        debugPrint('Password reset error: ${res.statusCode} ${res.body}');
      }
      return (res.statusCode == 200, res.statusCode, res.body);
    } catch (e) {
      debugPrint('Password reset error: $e');
      return (false, -1, e.toString());
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

  // FIX: putRoom/patchRoom now return whether the write actually
  // succeeded (based on HTTP status), instead of a fire-and-forget void.
  // Previously a rules-rejected write (403/401, or any non-2xx) was
  // swallowed silently — the caller (createRoom in game_notifier.dart)
  // would generate a room code and show "Waiting for players…" even
  // though nothing was ever written to the database, which is exactly
  // what caused "Room not found" for joiners: there was no room to find.
  Future<bool> putRoom(String code, Map<String, dynamic> data, String tok) =>
      _put('rooms/$code', data, tok);

  Future<bool> patchRoom(String code, Map<String, dynamic> data, String tok) =>
      _patch('rooms/$code', data, tok);

  // ── Tournaments ───────────────────────────────────────────────────────────
  Future<Map<dynamic, dynamic>?> getTournaments(String tok) =>
      _get('tournaments', tok);

  Future<bool> putTournament(String tid, Map<String, dynamic> data, String tok) =>
      _put('tournaments/$tid', data, tok);

  Future<bool> joinTournament(String tid, String uid, Map<String, dynamic> data, String tok) =>
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
      if (res.statusCode != 200) {
        debugPrint('FB GET $path failed: ${res.statusCode} ${res.body}');
        return null;
      }
      final body = jsonDecode(res.body);
      return body is Map ? body : null;
    } catch (e) {
      debugPrint('FB GET error: $e');
      return null;
    }
  }

  // FIX: was fire-and-forget (Future<void>) and never inspected the
  // response, so a rules-rejected write (e.g. ".write": false) looked
  // identical to a successful one from the caller's perspective — no
  // exception is thrown for an HTTP 401/403, only for network-level
  // failures. Now returns true only for a genuine 2xx.
  Future<bool> _put(String path, Map<String, dynamic> data, String tok) async {
    try {
      final res = await http.put(
        Uri.parse('$_kDbUrl/$path.json?auth=$tok'),
        headers: await _headers(),
        body: jsonEncode(data),
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        debugPrint('FB PUT $path failed: ${res.statusCode} ${res.body}');
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('FB PUT error: $e');
      return false;
    }
  }

  Future<bool> _patch(String path, Map<String, dynamic> data, String tok) async {
    try {
      final res = await http.patch(
        Uri.parse('$_kDbUrl/$path.json?auth=$tok'),
        headers: await _headers(),
        body: jsonEncode(data),
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        debugPrint('FB PATCH $path failed: ${res.statusCode} ${res.body}');
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('FB PATCH error: $e');
      return false;
    }
  }
}
