// lib/widgets/board_painter.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../theme/app_theme.dart';

class BoardPainter extends CustomPainter {
  final Map<int, List<List<int>>> tokens;
  final int  currentTurn;
  final bool diceRolled;
  final int  playerIndex;

  BoardPainter({
    required this.tokens,
    required this.currentTurn,
    required this.diceRolled,
    required this.playerIndex,
  });

  // Arrow direction for every outer track cell
  static const Map<String, double> _arrows = {
    '6,1': 0,'6,2': 0,'6,3': 0,'6,4': 0,'6,5': 0,
    '5,6': -math.pi/2,'4,6': -math.pi/2,'3,6': -math.pi/2,
    '2,6': -math.pi/2,'1,6': -math.pi/2,'0,6': -math.pi/2,
    '0,7': 0,'0,8': 0,
    '1,8': math.pi/2,'2,8': math.pi/2,'3,8': math.pi/2,
    '4,8': math.pi/2,'5,8': math.pi/2,
    '6,9': 0,'6,10': 0,'6,11': 0,'6,12': 0,'6,13': 0,'6,14': 0,
    '7,14': math.pi/2,
    '8,14': math.pi,'8,13': math.pi,'8,12': math.pi,
    '8,11': math.pi,'8,10': math.pi,'8,9': math.pi,
    '9,8': math.pi/2,'10,8': math.pi/2,'11,8': math.pi/2,
    '12,8': math.pi/2,'13,8': math.pi/2,'14,8': math.pi/2,
    '14,7': math.pi,'14,6': math.pi,
    '13,6': -math.pi/2,'12,6': -math.pi/2,'11,6': -math.pi/2,
    '10,6': -math.pi/2,'9,6': -math.pi/2,
    '8,5': math.pi,'8,4': math.pi,'8,3': math.pi,
    '8,2': math.pi,'8,1': math.pi,'8,0': math.pi,
    '7,0': -math.pi/2,'6,0': -math.pi/2,
  };

  // Inward arrow angles for home columns: Red→, Green↓, Yellow←, Blue↑
  static const List<double> _homeAngles = [
    0, math.pi/2, math.pi, -math.pi/2,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cw = size.width  / kBoardSize;
    final ch = size.height / kBoardSize;

    final nestSets = [
      for (int i = 0; i < 4; i++)
        {for (final p in kNestPositions[i]) '${p[0]},${p[1]}'},
    ];
    final hpSets = [
      for (int i = 0; i < 4; i++)
        {for (final p in kHousePaths[i]) '${p[0]},${p[1]}'},
    ];
    final trackSet = {for (final p in kTrackPath) '${p[0]},${p[1]}'};
    final startMap = <String, int>{};
    for (int i = 0; i < 4; i++) {
      startMap['${kStartPositions[i][0]},${kStartPositions[i][1]}'] = i;
    }

    // Token position map
    final tokMap = <String, List<(int, int)>>{};
    for (final e in tokens.entries) {
      for (int ti = 0; ti < e.value.length; ti++) {
        final k = '${e.value[ti][0]},${e.value[ti][1]}';
        tokMap.putIfAbsent(k, () => []).add((e.key, ti));
      }
    }

    // ── Paint every cell ─────────────────────────────────────────────────
    for (int r = 0; r < kBoardSize; r++) {
      for (int c = 0; c < kBoardSize; c++) {
        final key  = '$r,$c';
        final rect = Rect.fromLTWH(
            c * cw + 0.3, r * ch + 0.3, cw - 0.6, ch - 0.6);
        final rr = RRect.fromRectAndRadius(rect, const Radius.circular(2));

        int?  nestOwner, hpOwner;
        for (int i = 0; i < 4; i++) {
          if (nestSets[i].contains(key)) { nestOwner = i; break; }
        }
        if (nestOwner == null) {
          for (int i = 0; i < 4; i++) {
            if (hpSets[i].contains(key)) { hpOwner = i; break; }
          }
        }

        // ── Background colour ──────────────────────────────────────────
        Color bg;
        if (nestOwner != null) {
          bg = AppColors.nests[nestOwner];
        } else if (key == '${kFinalHome[0]},${kFinalHome[1]}') {
          bg = AppColors.boardHome;
        } else if (kSafeSquares.contains(key)) {
          bg = AppColors.boardSafe;
        } else if (hpOwner != null) {
          // ── FIX: home path cells including the one next to centre ──
          bg = AppColors.housePaths[hpOwner];
        } else if (trackSet.contains(key)) {
          bg = AppColors.boardTrack;
        } else if (startMap.containsKey(key)) {
          bg = AppColors.players[startMap[key]!].withOpacity(0.85);
        } else {
          // White cross background
          final inCross = (r >= 6 && r <= 8) || (c >= 6 && c <= 8);
          bg = inCross
              ? const Color(0xFF22223A)
              : AppColors.surface;
        }

        // Override start square colour
        if (startMap.containsKey(key)) {
          bg = AppColors.players[startMap[key]!].withOpacity(0.85);
        }

        canvas.drawRRect(rr, Paint()..color = bg);
        // Grid border
        canvas.drawRRect(rr,
            Paint()
              ..color = AppColors.border.withOpacity(0.45)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.4);

        final cx = rect.left + rect.width  / 2;
        final cy = rect.top  + rect.height / 2;

        // ── Decorations ────────────────────────────────────────────────
        if (kSafeSquares.contains(key)) {
          _star(canvas, cx, cy, cw * 0.27, Colors.white70);
        }
        if (key == '${kFinalHome[0]},${kFinalHome[1]}') {
          // Large home covers junction gap
          final homePaint = Paint()..color = AppColors.boardHome;
          canvas.drawCircle(Offset(cx, cy), cw * 1.15, homePaint);
          canvas.drawCircle(Offset(cx, cy), cw * 1.15,
              Paint()
                ..color = Colors.white.withOpacity(0.25)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2);
          _text(canvas, '🏠', rect, cw * 0.6);
        }
        // Outer track arrows
        final arrowAngle = _arrows[key];
        if (arrowAngle != null && !kSafeSquares.contains(key) &&
            !startMap.containsKey(key)) {
          _arrow(canvas, cx, cy, cw * 0.27, arrowAngle,
              Colors.white.withOpacity(0.38));
        }
        // Home column arrows pointing inward
        if (hpOwner != null) {
          _arrow(canvas, cx, cy, cw * 0.22, _homeAngles[hpOwner],
              AppColors.players[hpOwner].withOpacity(0.6));
        }

        // ── Tokens ─────────────────────────────────────────────────────
        final here = tokMap[key];
        if (here != null && here.isNotEmpty) {
          _drawTokens(canvas, rect, here, cw);
        }
      }
    }
  }

  void _drawTokens(Canvas canvas, Rect rect,
      List<(int, int)> toks, double cw) {
    if (toks.length == 1) {
      final (pi, ti) = toks.first;
      final color    = AppColors.players[pi];
      final r        = cw * 0.33;
      final cx = rect.left + rect.width  / 2;
      final cy = rect.top  + rect.height / 2;
      final highlight = diceRolled && pi == playerIndex;

      if (highlight) {
        canvas.drawCircle(Offset(cx, cy), r + 3,
            Paint()
              ..color = color.withOpacity(0.5)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
      }
      canvas.drawCircle(Offset(cx + 1, cy + 1.5), r,
          Paint()..color = Colors.black38);
      canvas.drawCircle(Offset(cx, cy), r, Paint()..color = color);
      canvas.drawCircle(Offset(cx, cy), r,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
      _text(canvas, '${ti + 1}', rect, cw * 0.26,
          color: Colors.white, bold: true);
    } else {
      for (int k = 0; k < math.min(toks.length, 4); k++) {
        final (pi, _) = toks[k];
        final ox = k * cw * 0.13 - toks.length * cw * 0.065;
        final oy = k * cw * 0.09  - toks.length * cw * 0.045;
        final cx = rect.left + rect.width  / 2 + ox;
        final cy = rect.top  + rect.height / 2 + oy;
        canvas.drawCircle(Offset(cx, cy), cw * 0.19,
            Paint()..color = AppColors.players[pi]);
        canvas.drawCircle(Offset(cx, cy), cw * 0.19,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1);
      }
    }
  }

  void _arrow(Canvas canvas, double cx, double cy,
      double r, double angle, Color color) {
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(angle);
    final path = Path()
      ..moveTo(r, 0)
      ..lineTo(-r * 0.5,  r * 0.55)
      ..lineTo(-r * 0.5, -r * 0.55)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.restore();
  }

  void _star(Canvas canvas, double cx, double cy, double r, Color color) {
    final path = Path();
    for (int i = 0; i < 10; i++) {
      final a  = i * math.pi / 5 - math.pi / 2;
      final rd = i.isEven ? r : r * 0.42;
      final x  = cx + math.cos(a) * rd;
      final y  = cy + math.sin(a) * rd;
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _text(Canvas canvas, String t, Rect rect, double fs,
      {Color color = Colors.white, bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: t,
          style: TextStyle(
              fontSize:   fs,
              color:      color,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              height:     1)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas,
        Offset(rect.left + (rect.width  - tp.width)  / 2,
               rect.top  + (rect.height - tp.height) / 2));
  }

  @override
  bool shouldRepaint(BoardPainter old) =>
      old.tokens      != tokens      ||
      old.currentTurn != currentTurn ||
      old.diceRolled  != diceRolled;
}
