"""
LUDO PRO MAX — Complete Professional Edition
Single-page architecture. Audio deferred. All inits guarded.
"""

import flet as ft
import random, time, json, os, asyncio, aiohttp

# ── CONFIG ────────────────────────────────────────────────────────────────────
FIREBASE_API_KEY  = os.environ.get("FIREBASE_API_KEY", "")
FIREBASE_DB_URL   = os.environ.get("FIREBASE_DB_URL", "")
FIREBASE_AUTH_URL = "https://identitytoolkit.googleapis.com/v1/accounts"
OFFLINE_FILE      = "ludo_save.json"
FLUTTERWAVE_URL   = "https://flutterwave.com/pay/ou2066snurqa"
APP_VERSION       = "2.0.0"

# ── BOARD CONSTANTS ───────────────────────────────────────────────────────────
BOARD_SIZE = 15
NEST_POS = [
    [(1,1),(1,4),(4,1),(4,4)],
    [(1,10),(1,13),(4,10),(4,13)],
    [(10,10),(10,13),(13,10),(13,13)],
    [(10,1),(10,4),(13,1),(13,4)],
]
START_POS  = [(6,1),(1,8),(8,13),(13,6)]
SAFE_SPOTS = {(6,2),(2,6),(6,12),(8,2),(12,8),(8,12),(2,8),(12,6)}
FINAL_HOME = (7,7)

TRACK_PATH = [
    (6,1),(6,2),(6,3),(6,4),(6,5),(5,6),(4,6),(3,6),(2,6),(1,6),(0,6),
    (0,7),(0,8),(1,8),(2,8),(3,8),(4,8),(5,8),(6,9),(6,10),(6,11),(6,12),(6,13),(6,14),
    (7,14),(8,14),(8,13),(8,12),(8,11),(8,10),(8,9),(9,8),(10,8),(11,8),(12,8),(13,8),(14,8),
    (14,7),(14,6),(13,6),(12,6),(11,6),(10,6),(9,6),(8,5),(8,4),(8,3),(8,2),(8,1),(8,0),
    (7,0),(6,0),
]
TRACK_SET = set(TRACK_PATH)

HOUSE_PATHS = [
    [(7,1),(7,2),(7,3),(7,4),(7,5),(7,6)],
    [(1,7),(2,7),(3,7),(4,7),(5,7),(6,7)],
    [(7,13),(7,12),(7,11),(7,10),(7,9),(7,8)],
    [(13,7),(12,7),(11,7),(10,7),(9,7),(8,7)],
]

PLAYER_COLORS = [ft.Colors.RED_600, ft.Colors.GREEN_600,
                 ft.Colors.YELLOW_700, ft.Colors.BLUE_600]
PLAYER_NAMES  = ["Red", "Green", "Yellow", "Blue"]
DICE_EMOJI    = {1:"⚀",2:"⚁",3:"⚂",4:"⚃",5:"⚄",6:"⚅"}
EMOTES        = ["😂","😡","😎","🎉","😭","👍","🤔","💀","🔥","👑"]
DEFAULT_ELO   = 1000
ELO_K         = 32

# ── FIREBASE ──────────────────────────────────────────────────────────────────
async def fb_req(method, url, data=None):
    try:
        async with aiohttp.ClientSession() as s:
            kw = {"json": data} if data else {}
            async with getattr(s, method)(url, **kw) as r:
                return await r.json()
    except Exception as ex:
        return {"error": str(ex)}

async def fb_auth(email, pw, signup=False):
    ep = "signUp" if signup else "signInWithPassword"
    return await fb_req("post",
        f"{FIREBASE_AUTH_URL}:{ep}?key={FIREBASE_API_KEY}",
        {"email": email, "password": pw, "returnSecureToken": True})

async def fb_get(path, tok):
    return await fb_req("get", f"{FIREBASE_DB_URL}/{path}.json?auth={tok}")

async def fb_put(path, data, tok):
    return await fb_req("put", f"{FIREBASE_DB_URL}/{path}.json?auth={tok}", data)

async def fb_patch(path, data, tok):
    return await fb_req("patch", f"{FIREBASE_DB_URL}/{path}.json?auth={tok}", data)

# ── ELO ───────────────────────────────────────────────────────────────────────
def new_elo(ra, rb, won):
    ea = 1 / (1 + 10 ** ((rb - ra) / 400))
    return int(ra + ELO_K * ((1 if won else 0) - ea))

# ── MAIN ──────────────────────────────────────────────────────────────────────
async def main(page: ft.Page):
    page.title      = "Ludo Pro Max"
    page.theme_mode = ft.ThemeMode.DARK
    page.bgcolor    = "#1a1a2e"
    page.padding    = 0

    # ── ROOT: single persistent container ─────────────────────────────────────
    root = ft.Column(expand=True, spacing=0, scroll=ft.ScrollMode.AUTO)
    page.add(ft.Container(content=root, expand=True, bgcolor="#1a1a2e"))
    page.update()

    def show(controls):
        root.controls.clear()
        for c in controls:
            root.controls.append(c)
        try:
            page.update()
        except Exception:
            pass

    # ── SNACK ─────────────────────────────────────────────────────────────────
    def snack(msg, color=ft.Colors.PURPLE_700):
        try:
            page.snack_bar = ft.SnackBar(
                ft.Text(msg, color=ft.Colors.WHITE, weight=ft.FontWeight.W_500),
                bgcolor=color, duration=2500,
            )
            page.snack_bar.open = True
            page.update()
        except Exception:
            pass

    # ── AUDIO (deferred — added after first page.update) ──────────────────────
    SOUND_URLS = {
        "dice":    "https://cdn.freesound.org/previews/362/362204_1676145-lq.mp3",
        "move":    "https://cdn.freesound.org/previews/399/399934_1676145-lq.mp3",
        "capture": "https://cdn.freesound.org/previews/331/331912_3248244-lq.mp3",
        "win":     "https://cdn.freesound.org/previews/456/456966_9159316-lq.mp3",
        "invalid": "https://cdn.freesound.org/previews/142/142608_1840739-lq.mp3",
        "six":     "https://cdn.freesound.org/previews/270/270402_5123851-lq.mp3",
        "bgm":     "https://cdn.freesound.org/previews/612/612598_5674468-lq.mp3",
    }
    _audio   = {}
    _sfx_on  = {"v": True}
    _bgm_on  = {"v": True}
    _audio_ready = {"v": False}

    def init_audio():
        if _audio_ready["v"]:
            return
        try:
            for key, url in SOUND_URLS.items():
                a = ft.Audio(src=url, autoplay=False,
                             volume=0.3 if key == "bgm" else 0.8)
                if key == "bgm":
                    a.release_mode = ft.ReleaseMode.LOOP
                page.overlay.append(a)
                _audio[key] = a
            page.update()
            _audio_ready["v"] = True
        except Exception:
            pass

    async def play(k):
        if not _sfx_on["v"] or k == "bgm" or not _audio_ready["v"]:
            return
        try:
            await _audio[k].resume_async()
        except Exception:
            try:
                await _audio[k].play_async()
            except Exception:
                pass

    async def play_bgm():
        if not _bgm_on["v"] or not _audio_ready["v"]:
            return
        try:
            await _audio["bgm"].play_async()
        except Exception:
            pass

    async def stop_bgm():
        if not _audio_ready["v"]:
            return
        try:
            await _audio["bgm"].pause_async()
        except Exception:
            pass

    # ── GAME STATE ────────────────────────────────────────────────────────────
    gs = {
        "user": None, "user_data": None,
        "room_id": None, "player_index": 0,
        "is_host": False, "is_online": False,
        "game_started": False, "current_turn": 0,
        "dice1": 0, "dice2": 0, "two_dice_mode": False,
        "tokens": {}, "players": {},
        "six_count": 0, "extra_turn": False,
        "winner": None, "finished_players": [],
        "local_players": 0, "bot_difficulty": "hard",
        "chat_messages": [], "last_chat_len": 0,
        "poll_task": None, "stop_poll": False,
        "can_roll": True, "bot_thinking": False,
    }

    # ── OFFLINE ───────────────────────────────────────────────────────────────
    def save_offline():
        try:
            with open(OFFLINE_FILE, "w") as f:
                json.dump({"user": gs["user"], "user_data": gs["user_data"]}, f)
        except Exception:
            pass

    def load_offline():
        try:
            if os.path.exists(OFFLINE_FILE):
                with open(OFFLINE_FILE) as f:
                    d = json.load(f)
                    gs["user"]      = d.get("user")
                    gs["user_data"] = d.get("user_data")
                    return bool(gs["user_data"])
        except Exception:
            pass
        return False

    async def sync_user():
        try:
            if gs["user"] and gs["user_data"] and gs["user"].get("idToken"):
                await fb_put(f"users/{gs['user']['localId']}",
                             gs["user_data"], gs["user"]["idToken"])
        except Exception:
            pass
        save_offline()

    async def init_user(uid, email):
        existing = {}
        try:
            existing = await fb_get(f"users/{uid}", gs["user"]["idToken"]) or {}
        except Exception:
            pass
        if not isinstance(existing, dict) or "email" not in existing:
            existing = {
                "email": email, "display_name": email.split("@")[0],
                "coins": 500, "wins": 0, "losses": 0, "games": 0,
                "elo": DEFAULT_ELO, "tournament_wins": 0,
                "skins": {}, "ads": {}, "achievements": [],
            }
            try:
                await fb_put(f"users/{uid}", existing, gs["user"]["idToken"])
            except Exception:
                pass
        gs["user_data"] = existing
        save_offline()

    # ── BOARD LOGIC ───────────────────────────────────────────────────────────
    def path_index(player, pos):
        pos = tuple(pos)
        if pos in [tuple(n) for n in NEST_POS[player]]: return -1
        if pos == FINAL_HOME: return 200
        for i, hp in enumerate(HOUSE_PATHS[player]):
            if pos == tuple(hp): return 100 + i
        if pos in TRACK_SET:
            si = TRACK_PATH.index(START_POS[player])
            pi = TRACK_PATH.index(pos)
            return (pi - si) % len(TRACK_PATH)
        return -2

    def can_move(player, t_idx, steps):
        pidx = path_index(player, gs["tokens"][player][t_idx])
        if pidx == -1:  return steps == 6
        if pidx == 200: return False
        if pidx >= 100: return (pidx - 100) + steps <= 5
        rem = len(TRACK_PATH) - pidx
        if steps >= rem: return (steps - rem) <= 6
        return True

    def calc_new_pos(player, t_idx, steps):
        pos  = gs["tokens"][player][t_idx]
        pidx = path_index(player, pos)
        if pidx == -1: return list(START_POS[player])
        if pidx >= 100:
            ni = (pidx - 100) + steps
            return list(HOUSE_PATHS[player][ni]) if ni < 6 else list(FINAL_HOME)
        ti  = TRACK_PATH.index(tuple(pos))
        si  = TRACK_PATH.index(START_POS[player])
        rem = len(TRACK_PATH) - (ti - si) % len(TRACK_PATH)
        if steps >= rem:
            hs = steps - rem
            if hs < 6:  return list(HOUSE_PATHS[player][hs])
            if hs == 6: return list(FINAL_HOME)
        return list(TRACK_PATH[(ti + steps) % len(TRACK_PATH)])

    def all_home(player):
        return all(tuple(p) == FINAL_HOME for p in gs["tokens"][player])

    # ── PERSISTENT GAME WIDGETS ───────────────────────────────────────────────
    dice1_txt = ft.Text("⚀", size=48, weight=ft.FontWeight.BOLD, color=ft.Colors.WHITE)
    dice2_txt = ft.Text("⚀", size=48, weight=ft.FontWeight.BOLD, color=ft.Colors.WHITE)
    roll_btn  = ft.ElevatedButton(
        text="Roll Dice", icon=ft.Icons.CASINO,
        style=ft.ButtonStyle(
            shape=ft.RoundedRectangleBorder(radius=12),
            bgcolor=ft.Colors.PURPLE_700, color=ft.Colors.WHITE,
            padding=ft.Padding(left=20, right=20, top=12, bottom=12),
        ),
    )
    status_txt  = ft.Text("", size=12, color=ft.Colors.WHITE70)
    board_col   = ft.Column(spacing=1, alignment=ft.MainAxisAlignment.CENTER)
    pstrip      = ft.Row(wrap=True, spacing=4,
                         alignment=ft.MainAxisAlignment.SPACE_AROUND)
    chat_list   = ft.ListView(height=86, spacing=2, auto_scroll=True)
    chat_field  = ft.TextField(
        hint_text="Message…", bgcolor="#2d2d44", border_radius=8,
        dense=True, expand=True, color=ft.Colors.WHITE,
        hint_style=ft.TextStyle(color=ft.Colors.WHITE38),
    )
    emote_row   = ft.Row(scroll=ft.ScrollMode.AUTO, spacing=4)

    # ── SHARED WIDGET HELPERS ─────────────────────────────────────────────────
    def mk_btn(text, on_click, icon=None, color=ft.Colors.PURPLE_700, width=300):
        return ft.ElevatedButton(
            text=text, icon=icon, on_click=on_click, width=width,
            style=ft.ButtonStyle(
                shape=ft.RoundedRectangleBorder(radius=12),
                bgcolor=color, color=ft.Colors.WHITE,
                padding=ft.Padding(left=14, right=14, top=12, bottom=12),
                elevation=3,
            ),
        )

    def mk_header(title):
        return ft.Container(
            content=ft.Row([
                ft.Text("🎲", size=20),
                ft.Text(title, size=18, weight=ft.FontWeight.BOLD,
                        color=ft.Colors.WHITE),
            ], spacing=8),
            bgcolor="#12122a",
            padding=ft.Padding(left=16, right=16, top=12, bottom=12),
        )

    def support_card():
        async def donate(e):
            try:
                page.launch_url(FLUTTERWAVE_URL)
            except Exception:
                pass
        return ft.Container(
            content=ft.Column([
                ft.Row([
                    ft.Icon(ft.Icons.VOLUNTEER_ACTIVISM,
                            color=ft.Colors.ORANGE_300, size=16),
                    ft.Text("Support the Developer", size=12,
                            weight=ft.FontWeight.BOLD, color=ft.Colors.WHITE),
                ], spacing=6),
                ft.Text("Ludo Pro Max is free — buy the dev a coffee ☕!",
                        size=11, color=ft.Colors.WHITE70),
                ft.ElevatedButton(
                    "☕ Buy a Coffee", icon=ft.Icons.FAVORITE,
                    on_click=donate, width=260,
                    style=ft.ButtonStyle(
                        shape=ft.RoundedRectangleBorder(radius=10),
                        bgcolor=ft.Colors.ORANGE_700, color=ft.Colors.WHITE,
                        padding=ft.Padding(left=12, right=12, top=8, bottom=8),
                    ),
                ),
            ], spacing=6, horizontal_alignment=ft.CrossAxisAlignment.CENTER),
            bgcolor="#2d1f0a", padding=12, border_radius=12,
            border=ft.border.all(1, ft.Colors.ORANGE_800), width=300,
        )

    # ── GAME SETUP ────────────────────────────────────────────────────────────
    def setup_game(num_players, mode="bot", difficulty="hard", two_dice=False):
        gs.update({
            "stop_poll": True, "is_online": False,
            "two_dice_mode": two_dice, "player_index": 0,
            "local_players": num_players if mode == "local" else 0,
            "bot_difficulty": difficulty,
            "game_started": True, "current_turn": 0,
            "winner": None, "finished_players": [],
            "dice1": 0, "dice2": 0, "six_count": 0,
            "extra_turn": False, "bot_thinking": False, "can_roll": True,
        })
        gs["players"] = ({0:"You",1:"Bot A",2:"Bot B",3:"Bot C"}
                         if mode == "bot"
                         else {i: f"Player {i+1}" for i in range(num_players)})
        n = 4 if mode == "bot" else num_players
        gs["tokens"] = {i: [list(p) for p in NEST_POS[i]] for i in range(n)}
        if gs["user_data"]:
            gs["user_data"]["games"] = gs["user_data"].get("games", 0) + 1
        dice1_txt.value = dice2_txt.value = "⚀"

    # ── BOARD BUILD ───────────────────────────────────────────────────────────
    def build_board():
        board_col.controls.clear()
        csz = 23
        nest_sets  = [set(map(tuple, NEST_POS[i]))    for i in range(4)]
        hp_sets    = [set(map(tuple, HOUSE_PATHS[i]))  for i in range(4)]
        hp_dirs    = ["↑","→","↓","←"]
        hp_cols    = ["#ef9a9a","#a5d6a7","#fff59d","#90caf9"]
        nest_cols  = ["#c62828","#2e7d32","#f9a825","#1565c0"]
        start_cols = ["#e53935","#43a047","#fdd835","#1e88e5"]

        tok_map = {}
        for pi, toks in gs["tokens"].items():
            for ti, tp in enumerate(toks):
                tok_map.setdefault(tuple(tp), []).append((pi, ti))

        for ri in range(BOARD_SIZE):
            row = ft.Row(spacing=1, alignment=ft.MainAxisAlignment.CENTER)
            for ci in range(BOARD_SIZE):
                pos = (ri, ci)
                bg  = "#2d2d44"
                txt = ""

                placed = False
                for i in range(4):
                    if pos in nest_sets[i]:
                        bg = nest_cols[i]; placed = True; break
                if not placed:
                    if pos in SAFE_SPOTS:   bg, txt = "#607d8b", "★"
                    elif pos == FINAL_HOME: bg, txt = "#7b1fa2", "🏠"
                    elif pos in TRACK_SET:  bg = "#3a3a5c"
                    else:
                        for i in range(4):
                            if pos in hp_sets[i]:
                                bg, txt = hp_cols[i], hp_dirs[i]; break
                for i in range(4):
                    if pos == START_POS[i]:
                        bg = start_cols[i]; break

                here = tok_map.get(pos, [])
                if len(here) == 1:
                    pi, ti = here[0]
                    r2 = (csz - 6) // 2
                    cell_c = ft.Container(
                        width=csz-6, height=csz-6,
                        border_radius=ft.BorderRadius(r2,r2,r2,r2),
                        bgcolor=PLAYER_COLORS[pi],
                        border=ft.border.all(1.5, ft.Colors.WHITE),
                        alignment=ft.alignment.center,
                        data=f"{pi},{ti}",
                        on_click=lambda e: page.run_task(token_click, e),
                        content=ft.Text(str(ti+1), size=7, color=ft.Colors.WHITE,
                                        weight=ft.FontWeight.BOLD),
                        shadow=ft.BoxShadow(blur_radius=3, color=ft.Colors.BLACK54),
                    )
                elif len(here) > 1:
                    items = []
                    for k, (pi, ti) in enumerate(here[:4]):
                        items.append(ft.Container(
                            width=10, height=10,
                            border_radius=ft.BorderRadius(5,5,5,5),
                            bgcolor=PLAYER_COLORS[pi],
                            left=k*5, top=k*4,
                            border=ft.border.all(1, ft.Colors.WHITE),
                            data=f"{pi},{ti}",
                            on_click=lambda e: page.run_task(token_click, e),
                        ))
                    cell_c = ft.Stack(items, width=csz, height=csz)
                else:
                    cell_c = ft.Text(txt, size=8, weight=ft.FontWeight.BOLD,
                                     color=ft.Colors.WHITE)

                row.controls.append(ft.Container(
                    width=csz, height=csz, bgcolor=bg,
                    border=ft.border.all(0.4, "#44446a"),
                    alignment=ft.alignment.center,
                    content=cell_c,
                    border_radius=ft.BorderRadius(2,2,2,2),
                ))
            board_col.controls.append(row)

    # ── UI REFRESH ────────────────────────────────────────────────────────────
    def refresh_ui():
        try:
            is_turn = gs["current_turn"] == gs["player_index"]
            total_d = gs["dice1"] + gs["dice2"] if gs["two_dice_mode"] else gs["dice1"]
            can_r   = (is_turn and total_d == 0 and gs["game_started"]
                       and gs["winner"] is None and not gs["bot_thinking"])
            roll_btn.disabled = not can_r
            if gs["winner"] is not None:
                roll_btn.text = f"🏆 {PLAYER_NAMES[gs['winner']]} Wins!"
                roll_btn.style.bgcolor = ft.Colors.GREEN_700
            elif is_turn:
                roll_btn.text = "🎲 Your Turn — Roll!"
                roll_btn.style.bgcolor = ft.Colors.PURPLE_700
            else:
                roll_btn.text = f"⏳ {PLAYER_NAMES[gs['current_turn']]}'s Turn"
                roll_btn.style.bgcolor = ft.Colors.BLUE_GREY_700

            ud = gs["user_data"]
            if ud:
                status_txt.value = (f"🪙 {ud.get('coins',0)}  "
                                    f"🏆 {ud.get('wins',0)}W  "
                                    f"📊 {ud.get('elo', DEFAULT_ELO)} ELO")
            pstrip.controls.clear()
            for idx in range(len(gs["players"])):
                name     = gs["players"].get(idx, PLAYER_NAMES[idx])
                finished = idx in gs["finished_players"]
                active   = idx == gs["current_turn"] and not finished
                pstrip.controls.append(ft.Container(
                    content=ft.Column([
                        ft.Text(PLAYER_NAMES[idx], size=9, color=ft.Colors.WHITE,
                                weight=ft.FontWeight.BOLD),
                        ft.Text(name[:8], size=8, color=ft.Colors.WHITE70),
                        ft.Text("✅" if finished else ("🎲" if active else ""), size=9),
                    ], spacing=1, horizontal_alignment=ft.CrossAxisAlignment.CENTER),
                    bgcolor=PLAYER_COLORS[idx] if active else "#2d2d44",
                    padding=ft.Padding(left=6, right=6, top=4, bottom=4),
                    border_radius=ft.BorderRadius(8,8,8,8),
                    border=ft.border.all(2 if active else 0, ft.Colors.WHITE),
                ))
            build_board()
            page.update()
        except Exception:
            pass

    # ── MOVE LOGIC ────────────────────────────────────────────────────────────
    async def do_move(player, t_idx, steps):
        if not can_move(player, t_idx, steps): return False
        np   = calc_new_pos(player, t_idx, steps)
        npt  = tuple(np)
        capt = False

        if (npt not in SAFE_SPOTS
                and np not in [list(h) for h in HOUSE_PATHS[player]]
                and npt != FINAL_HOME):
            for p, toks in gs["tokens"].items():
                if p == player: continue
                for ti, tp in enumerate(toks):
                    if tp == np and tuple(tp) not in SAFE_SPOTS:
                        gs["tokens"][p][ti] = list(NEST_POS[p][ti])
                        snack(f"💥 {PLAYER_NAMES[player]} captured {PLAYER_NAMES[p]}!",
                              ft.Colors.RED_700)
                        capt = True
                        gs["extra_turn"] = True
                        await play("capture")

        gs["tokens"][player][t_idx] = np
        await play("move")
        gs["dice1"] = gs["dice2"] = 0
        dice1_txt.value = dice2_txt.value = "⚀"

        if all_home(player):
            gs["finished_players"].append(player)
            total_p = len(gs["players"])
            if player == gs["player_index"]:
                place  = len(gs["finished_players"])
                reward = [300,200,100,50][min(place-1,3)]
                gs["user_data"]["wins"]  += 1
                gs["user_data"]["coins"] += reward
                gs["user_data"]["games"] += 1
                gs["user_data"]["elo"]    = new_elo(gs["user_data"]["elo"], 1000, True)
                await sync_user()
                snack(f"🏆 #{place} place! +{reward} coins", ft.Colors.GREEN_700)
            if len(gs["finished_players"]) == total_p - 1:
                last = [p for p in range(total_p)
                        if p not in gs["finished_players"]][0]
                if last == gs["player_index"]:
                    gs["user_data"]["losses"] += 1
                    gs["user_data"]["elo"] = new_elo(gs["user_data"]["elo"], 1000, False)
                    await sync_user()
                gs["winner"] = gs["finished_players"][0]
                refresh_ui()
                await play("win")
                await show_game_over(gs["winner"])
                return True

        if steps != 6 and not capt and not gs["extra_turn"]:
            await advance_turn()
        else:
            gs["extra_turn"] = False
            refresh_ui()
            if not gs["is_online"]:
                page.run_task(maybe_bot)
        await sync_room()
        refresh_ui()
        return True

    # ── DICE ──────────────────────────────────────────────────────────────────
    async def roll_dice(e):
        if (not gs["can_roll"] or gs["bot_thinking"]
                or gs["current_turn"] != gs["player_index"]
                or not gs["game_started"]): return
        gs["can_roll"] = False
        d1 = random.randint(1, 6)
        d2 = random.randint(1, 6) if gs["two_dice_mode"] else 0
        gs["dice1"], gs["dice2"] = d1, d2
        dice1_txt.value = DICE_EMOJI[d1]
        if gs["two_dice_mode"]: dice2_txt.value = DICE_EMOJI[d2]
        await play("dice")
        total = d1 + d2 if gs["two_dice_mode"] else d1

        if d1 == 6 or (gs["two_dice_mode"] and d2 == 6):
            gs["six_count"] += 1
            gs["extra_turn"] = True
            await play("six")
            if gs["six_count"] == 3:
                snack("3 sixes — skipped! ⛔", ft.Colors.RED_700)
                gs["dice1"] = gs["dice2"] = 0
                gs["six_count"] = 0
                gs["extra_turn"] = False
                gs["can_roll"] = True
                await advance_turn()
                return
        else:
            gs["six_count"] = 0
            gs["extra_turn"] = False

        movable = [i for i in range(4) if can_move(gs["player_index"], i, total)]
        if not movable:
            snack("No moves 😔", ft.Colors.ORANGE_700)
            await play("invalid")
            gs["dice1"] = gs["dice2"] = 0
            dice1_txt.value = dice2_txt.value = "⚀"
            if not gs["extra_turn"]: await advance_turn()

        gs["can_roll"] = True
        await sync_room()
        refresh_ui()

    # ── TURNS ─────────────────────────────────────────────────────────────────
    async def advance_turn():
        if gs["winner"] is not None: return
        total = len(gs["players"])
        nxt   = (gs["current_turn"] + 1) % total
        loops = 0
        while nxt in gs["finished_players"] and loops < total:
            nxt = (nxt + 1) % total
            loops += 1
        gs["current_turn"] = nxt
        gs["dice1"] = gs["dice2"] = 0
        dice1_txt.value = dice2_txt.value = "⚀"
        refresh_ui()
        if not gs["is_online"]: page.run_task(maybe_bot)

    async def maybe_bot():
        if gs["winner"] is not None: return
        cur = gs["current_turn"]
        if gs["local_players"] == 0 and cur == gs["player_index"]: return
        if gs["local_players"] > 1 and cur == 0: return
        if not gs["bot_thinking"]: page.run_task(run_bot)

    async def run_bot():
        gs["bot_thinking"] = True
        await asyncio.sleep(0.9)
        if gs["winner"] is not None:
            gs["bot_thinking"] = False; return
        bot   = gs["current_turn"]
        d1    = random.randint(1, 6)
        d2    = random.randint(1, 6) if gs["two_dice_mode"] else 0
        total = d1 + d2 if gs["two_dice_mode"] else d1
        gs["dice1"], gs["dice2"] = d1, d2
        dice1_txt.value = DICE_EMOJI[d1]
        if gs["two_dice_mode"]: dice2_txt.value = DICE_EMOJI[d2]
        diff = gs["bot_difficulty"]
        snack(f"{PLAYER_NAMES[bot]} rolled {total}", ft.Colors.BLUE_GREY_700)
        refresh_ui()
        await asyncio.sleep(0.6)

        moves = []
        for ti in range(4):
            if not can_move(bot, ti, total): continue
            pidx  = path_index(bot, gs["tokens"][bot][ti])
            score = 0
            if diff == "easy":
                score = random.randint(0, 100)
            elif diff == "hard":
                np2 = calc_new_pos(bot, ti, total)
                for p, toks in gs["tokens"].items():
                    if p == bot: continue
                    if np2 in toks and tuple(np2) not in SAFE_SPOTS: score += 150
                if pidx >= 100: score += 80
                if pidx == -1:  score += 40
                score += pidx if pidx >= 0 else 0
            elif diff == "hardest":
                np2   = calc_new_pos(bot, ti, total)
                npidx = path_index(bot, np2)
                for p, toks in gs["tokens"].items():
                    if p == bot: continue
                    if np2 in toks and tuple(np2) not in SAFE_SPOTS: score += 300
                if tuple(np2) == FINAL_HOME: score += 500
                if npidx >= 100:             score += 200
                if pidx == -1:               score += 80
                score += (pidx if 0 <= pidx < 100 else 0) * 2
                score += random.randint(0, 20)
            moves.append((ti, score))

        if moves:
            await do_move(bot, max(moves, key=lambda x: x[1])[0], total)
        else:
            snack(f"{PLAYER_NAMES[bot]} no moves", ft.Colors.GREY_600)
            gs["dice1"] = gs["dice2"] = 0
            if total != 6: await advance_turn()
            else: refresh_ui()
        gs["bot_thinking"] = False

    # ── TOKEN CLICK ───────────────────────────────────────────────────────────
    async def token_click(e):
        if not gs["game_started"]: return
        if gs["current_turn"] != gs["player_index"]: return
        total = gs["dice1"] + gs["dice2"] if gs["two_dice_mode"] else gs["dice1"]
        if total == 0: snack("Roll first! 🎲", ft.Colors.ORANGE_700); return
        try: p_idx, t_idx = map(int, e.control.data.split(","))
        except: return
        if p_idx != gs["player_index"]: return
        await do_move(p_idx, t_idx, total)

    # ── CHAT ──────────────────────────────────────────────────────────────────
    def refresh_chat():
        try:
            chat_list.controls.clear()
            for m in gs["chat_messages"][-30:]:
                idx = PLAYER_NAMES.index(m["player"]) if m["player"] in PLAYER_NAMES else 0
                chat_list.controls.append(ft.Row([
                    ft.Container(
                        ft.Text(m["player"], size=9, color=ft.Colors.WHITE,
                                weight=ft.FontWeight.BOLD),
                        bgcolor=PLAYER_COLORS[idx],
                        padding=ft.Padding(left=4, right=4, top=2, bottom=2),
                        border_radius=ft.BorderRadius(4,4,4,4),
                    ),
                    ft.Text(m["msg"], size=10, color=ft.Colors.WHITE70, expand=True),
                ], spacing=4))
            page.update()
        except Exception:
            pass

    async def send_chat(e):
        msg = chat_field.value.strip()
        if not msg: return
        chat_field.value = ""
        entry = {"player": PLAYER_NAMES[gs["player_index"]], "msg": msg,
                 "time": int(time.time())}
        if gs["is_online"] and gs["room_id"]:
            try:
                await fb_patch(
                    f"rooms/{gs['room_id']}/chat/{int(time.time()*1000)}",
                    entry, gs["user"]["idToken"])
            except Exception: pass
        else:
            gs["chat_messages"].append(entry)
            refresh_chat()

    async def send_emote(em):
        m = {"player": PLAYER_NAMES[gs["player_index"]], "msg": em,
             "time": int(time.time())}
        if gs["is_online"] and gs["room_id"]:
            try:
                await fb_patch(
                    f"rooms/{gs['room_id']}/chat/{int(time.time()*1000)}",
                    m, gs["user"]["idToken"])
            except Exception: pass
        else:
            gs["chat_messages"].append(m)
            refresh_chat()

    # ── ONLINE ────────────────────────────────────────────────────────────────
    async def poll_room():
        last = None
        while not gs["stop_poll"] and gs["is_online"] and gs["room_id"]:
            try:
                room = await fb_get(f"rooms/{gs['room_id']}", gs["user"]["idToken"])
                if room and room != last:
                    gs["tokens"]           = {int(k):v for k,v in room.get("tokens",{}).items()}
                    gs["current_turn"]     = room.get("current_turn", 0)
                    gs["dice1"]            = room.get("dice1", 0)
                    gs["dice2"]            = room.get("dice2", 0)
                    gs["winner"]           = room.get("winner")
                    gs["players"]          = {int(k):v for k,v in room.get("players",{}).items()}
                    gs["finished_players"] = room.get("finished_players", [])
                    if room.get("state") == "playing": gs["game_started"] = True
                    cd = room.get("chat", {})
                    if len(cd) != gs["last_chat_len"]:
                        gs["chat_messages"] = sorted(cd.values(), key=lambda x: x["time"])
                        gs["last_chat_len"] = len(cd)
                        refresh_chat()
                    dice1_txt.value = DICE_EMOJI.get(gs["dice1"], "⚀")
                    dice2_txt.value = DICE_EMOJI.get(gs["dice2"], "⚀")
                    refresh_ui()
                    last = room
            except Exception: pass
            await asyncio.sleep(1.5)

    def start_poll():
        gs["stop_poll"] = False
        if not gs["poll_task"] or gs["poll_task"].done():
            gs["poll_task"] = asyncio.ensure_future(poll_room())

    async def sync_room():
        if gs["is_online"] and gs["room_id"] and gs["user"].get("idToken"):
            try:
                await fb_patch(f"rooms/{gs['room_id']}", {
                    "tokens": {str(k):v for k,v in gs["tokens"].items()},
                    "current_turn": gs["current_turn"],
                    "dice1": gs["dice1"], "dice2": gs["dice2"],
                    "winner": gs["winner"],
                    "finished_players": gs["finished_players"],
                }, gs["user"]["idToken"])
            except Exception: pass

    async def create_room(two_dice=False):
        code = str(random.randint(100000, 999999))
        gs.update({"room_id": code, "player_index": 0, "is_host": True,
                   "is_online": True, "two_dice_mode": two_dice,
                   "players": {0: gs["user_data"]["email"]},
                   "tokens": {0: [list(p) for p in NEST_POS[0]]},
                   "game_started": False, "winner": None, "finished_players": []})
        await fb_put(f"rooms/{code}", {
            "players": {"0": gs["user_data"]["email"]},
            "tokens": {"0": [list(p) for p in NEST_POS[0]]},
            "current_turn": 0, "dice1": 0, "dice2": 0,
            "winner": None, "state": "waiting",
            "two_dice_mode": two_dice, "finished_players": [], "chat": {},
        }, gs["user"]["idToken"])
        start_poll()
        return code

    async def join_room(code):
        room = await fb_get(f"rooms/{code}", gs["user"]["idToken"])
        if not room: return False, "Room not found"
        players = room.get("players", {})
        if len(players) >= 4: return False, "Room is full"
        idx = len(players)
        players[str(idx)] = gs["user_data"]["email"]
        tokens = room.get("tokens", {})
        tokens[str(idx)] = [list(p) for p in NEST_POS[idx]]
        state  = "playing" if len(players) == 4 else "waiting"
        await fb_patch(f"rooms/{code}",
                       {"players": players, "tokens": tokens, "state": state},
                       gs["user"]["idToken"])
        gs.update({"room_id": code, "player_index": idx, "is_online": True,
                   "two_dice_mode": room.get("two_dice_mode", False),
                   "players": {int(k):v for k,v in players.items()},
                   "tokens":  {int(k):v for k,v in tokens.items()},
                   "game_started": state == "playing",
                   "winner": None, "finished_players": []})
        start_poll()
        return True, "Joined!"

    # ── GAME OVER DIALOG ──────────────────────────────────────────────────────
    async def show_game_over(winner_idx):
        labels  = ["🥇 1st","🥈 2nd","🥉 3rd","4th"]
        rewards = [300,200,100,50]
        my_pl   = (gs["finished_players"].index(gs["player_index"])
                   if gs["player_index"] in gs["finished_players"]
                   else len(gs["finished_players"]))

        async def rematch(e):
            try: page.close(dlg)
            except Exception: pass
            setup_game(len(gs["players"]),
                       "local" if gs["local_players"] > 0 else "bot",
                       gs["bot_difficulty"], gs["two_dice_mode"])
            show_game_screen()

        async def go_menu(e):
            try: page.close(dlg)
            except Exception: pass
            gs["stop_poll"] = True
            await stop_bgm()
            show_menu_screen()

        dlg = ft.AlertDialog(
            modal=True, bgcolor="#1a1a2e",
            shape=ft.RoundedRectangleBorder(radius=14),
            content=ft.Column([
                ft.Text("🏆 Game Over!", size=22, weight=ft.FontWeight.BOLD,
                        color=ft.Colors.WHITE, text_align=ft.TextAlign.CENTER),
                ft.Text(f"{PLAYER_NAMES[winner_idx]} wins!", size=17,
                        color=PLAYER_COLORS[winner_idx],
                        text_align=ft.TextAlign.CENTER),
                ft.Divider(color="#44446a"),
                ft.Text(f"You: {labels[min(my_pl,3)]}", size=13,
                        color=ft.Colors.WHITE70, text_align=ft.TextAlign.CENTER),
                ft.Text(f"+{rewards[min(my_pl,3)]} coins 🪙", size=13,
                        color=ft.Colors.AMBER_400, text_align=ft.TextAlign.CENTER),
                ft.Divider(color="#44446a"),
                support_card(),
                ft.Divider(color="#44446a"),
                ft.Row([
                    ft.ElevatedButton(
                        "Play Again", icon=ft.Icons.REPLAY,
                        on_click=lambda e: page.run_task(rematch, e),
                        style=ft.ButtonStyle(
                            shape=ft.RoundedRectangleBorder(radius=10),
                            bgcolor=ft.Colors.PURPLE_700, color=ft.Colors.WHITE),
                    ),
                    ft.ElevatedButton(
                        "Menu", icon=ft.Icons.HOME,
                        on_click=lambda e: page.run_task(go_menu, e),
                        style=ft.ButtonStyle(
                            shape=ft.RoundedRectangleBorder(radius=10),
                            bgcolor=ft.Colors.GREY_700, color=ft.Colors.WHITE),
                    ),
                ], alignment=ft.MainAxisAlignment.CENTER, spacing=10),
            ], spacing=10, horizontal_alignment=ft.CrossAxisAlignment.CENTER,
               tight=True, scroll=ft.ScrollMode.AUTO),
            actions=[],
        )
        try:
            page.open(dlg)
            page.update()
        except Exception:
            pass

    # ═══════════════════════════════════════════════════════════════════════════
    # SCREENS
    # ═══════════════════════════════════════════════════════════════════════════

    def show_login_screen():
        ef = ft.TextField(
            label="Email", width=290, bgcolor="#2d2d44", border_radius=10,
            color=ft.Colors.WHITE,
            label_style=ft.TextStyle(color=ft.Colors.WHITE54),
        )
        pf = ft.TextField(
            label="Password", password=True, can_reveal_password=True,
            width=290, bgcolor="#2d2d44", border_radius=10,
            color=ft.Colors.WHITE,
            label_style=ft.TextStyle(color=ft.Colors.WHITE54),
        )
        loading = ft.ProgressRing(visible=False, width=22, height=22,
                                  color=ft.Colors.PURPLE_300)

        async def do_auth(signup):
            if not ef.value or not pf.value:
                snack("Enter email and password", ft.Colors.RED_700); return
            loading.visible = True
            try: page.update()
            except Exception: pass
            try:
                user = await fb_auth(ef.value, pf.value, signup=signup)
                if "error" in user:
                    snack(str(user["error"].get("message","Auth failed")),
                          ft.Colors.RED_700)
                else:
                    gs["user"] = user
                    await init_user(user["localId"], ef.value)
                    show_menu_screen()
            except Exception as ex:
                snack(str(ex), ft.Colors.RED_700)
            loading.visible = False
            try: page.update()
            except Exception: pass

        def do_offline(e):
            if load_offline():
                show_menu_screen()
            else:
                gs["user"]      = {"localId": "offline", "idToken": ""}
                gs["user_data"] = {
                    "email": "Offline Player", "display_name": "Player",
                    "coins": 500, "wins": 0, "losses": 0, "games": 0,
                    "elo": DEFAULT_ELO, "tournament_wins": 0,
                    "skins": {}, "ads": {}, "achievements": [],
                }
                show_menu_screen()

        show([
            ft.Container(
                expand=True, bgcolor="#1a1a2e", padding=28,
                content=ft.Column(
                    scroll=ft.ScrollMode.AUTO,
                    horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                    spacing=14,
                    controls=[
                        ft.Container(height=28),
                        ft.Text("🎲", size=64, text_align=ft.TextAlign.CENTER),
                        ft.Text("Ludo Pro Max", size=30,
                                weight=ft.FontWeight.BOLD,
                                color=ft.Colors.WHITE,
                                text_align=ft.TextAlign.CENTER),
                        ft.Text(f"v{APP_VERSION}", size=11,
                                color=ft.Colors.WHITE38,
                                text_align=ft.TextAlign.CENTER),
                        ft.Container(height=14),
                        ef, pf, loading,
                        mk_btn("Login",
                               lambda e: page.run_task(do_auth, False),
                               icon=ft.Icons.LOGIN),
                        mk_btn("Create Account",
                               lambda e: page.run_task(do_auth, True),
                               icon=ft.Icons.PERSON_ADD,
                               color=ft.Colors.INDIGO_700),
                        ft.TextButton(
                            "Play Offline", on_click=do_offline,
                            style=ft.ButtonStyle(color=ft.Colors.WHITE54),
                        ),
                        ft.Container(height=20),
                    ],
                ),
            )
        ])

    def show_menu_screen():
        ud = gs["user_data"] or {}

        def go_bot(diff, two=False):
            setup_game(4, "bot", diff, two_dice=two)
            show_game_screen()

        def go_local(n):
            setup_game(n, "local")
            show_game_screen()

        def go_online(e):
            if not gs["user"] or gs["user"]["localId"] == "offline":
                snack("Login to play online", ft.Colors.RED_700); return
            show_lobby_screen()

        show([
            mk_header("Ludo Pro Max"),
            ft.Container(
                expand=True, bgcolor="#1a1a2e", padding=16,
                content=ft.Column(
                    scroll=ft.ScrollMode.AUTO,
                    horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                    spacing=10,
                    controls=[
                        ft.Container(
                            content=ft.Row([
                                ft.CircleAvatar(
                                    content=ft.Text(
                                        ud.get("display_name","P")[0].upper(),
                                        size=17, weight=ft.FontWeight.BOLD,
                                        color=ft.Colors.WHITE),
                                    bgcolor=ft.Colors.PURPLE_700, radius=22),
                                ft.Column([
                                    ft.Text(ud.get("display_name","Player"),
                                            size=14, weight=ft.FontWeight.BOLD,
                                            color=ft.Colors.WHITE),
                                    ft.Text(
                                        f"🪙 {ud.get('coins',0)}  "
                                        f"🏆 {ud.get('wins',0)}W  "
                                        f"📊 {ud.get('elo',DEFAULT_ELO)} ELO",
                                        size=11, color=ft.Colors.WHITE70),
                                ], spacing=2, expand=True),
                            ], spacing=10),
                            bgcolor="#2d2d44", padding=12, border_radius=10,
                        ),
                        ft.Divider(color="#44446a"),
                        ft.Text("🤖 VS AI", size=13, weight=ft.FontWeight.BOLD,
                                color=ft.Colors.WHITE70),
                        mk_btn("Easy Bot 😊", lambda e: go_bot("easy"),
                               color=ft.Colors.GREEN_700),
                        mk_btn("Hard Bot 😤", lambda e: go_bot("hard"),
                               color=ft.Colors.ORANGE_700),
                        mk_btn("Hardest Bot 💀", lambda e: go_bot("hardest"),
                               color=ft.Colors.RED_700),
                        mk_btn("2-Dice vs Bot 🎲🎲",
                               lambda e: go_bot("hard", True),
                               color=ft.Colors.DEEP_PURPLE_700),
                        ft.Divider(color="#44446a"),
                        ft.Text("👥 Local Play", size=13, weight=ft.FontWeight.BOLD,
                                color=ft.Colors.WHITE70),
                        ft.Row([
                            mk_btn("2P", lambda e: go_local(2),
                                   width=88, color=ft.Colors.BLUE_700),
                            mk_btn("3P", lambda e: go_local(3),
                                   width=88, color=ft.Colors.TEAL_700),
                            mk_btn("4P", lambda e: go_local(4),
                                   width=88, color=ft.Colors.INDIGO_700),
                        ], alignment=ft.MainAxisAlignment.CENTER, spacing=6),
                        ft.Divider(color="#44446a"),
                        ft.Text("🌐 Online", size=13, weight=ft.FontWeight.BOLD,
                                color=ft.Colors.WHITE70),
                        mk_btn("Online Multiplayer 🌍", go_online,
                               icon=ft.Icons.WIFI, color=ft.Colors.CYAN_700),
                        mk_btn("Tournaments 🏆",
                               lambda e: show_tournament_screen(),
                               icon=ft.Icons.EMOJI_EVENTS,
                               color=ft.Colors.AMBER_700),
                        mk_btn("Leaderboard 📊",
                               lambda e: show_leaderboard_screen(),
                               icon=ft.Icons.LEADERBOARD,
                               color=ft.Colors.PINK_700),
                        ft.Divider(color="#44446a"),
                        support_card(),
                        ft.TextButton(
                            "Logout",
                            on_click=lambda e: show_login_screen(),
                            style=ft.ButtonStyle(color=ft.Colors.WHITE38),
                        ),
                        ft.Container(height=24),
                    ],
                ),
            ),
        ])

    def show_lobby_screen():
        code_f = ft.TextField(
            label="Room Code", width=180, bgcolor="#2d2d44",
            border_radius=10, color=ft.Colors.WHITE,
            text_align=ft.TextAlign.CENTER,
            label_style=ft.TextStyle(color=ft.Colors.WHITE54),
        )
        info = ft.Text("", color=ft.Colors.WHITE70, size=12)

        async def do_create(two=False):
            code = await create_room(two_dice=two)
            info.value = f"Room: {code} — waiting…"
            try: page.update()
            except Exception: pass
            show_game_screen()

        async def do_join(e):
            if not code_f.value.strip():
                snack("Enter room code", ft.Colors.RED_700); return
            ok, msg = await join_room(code_f.value.strip())
            if ok: show_game_screen()
            else:  snack(msg, ft.Colors.RED_700)

        show([
            mk_header("Online Lobby"),
            ft.Container(
                expand=True, bgcolor="#1a1a2e", padding=20,
                content=ft.Column(
                    scroll=ft.ScrollMode.AUTO,
                    horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                    spacing=12,
                    controls=[
                        ft.Text("Create a room and share the code",
                                size=12, color=ft.Colors.WHITE70,
                                text_align=ft.TextAlign.CENTER),
                        mk_btn("Create Room (1 Dice)",
                               lambda e: page.run_task(do_create, False),
                               icon=ft.Icons.ADD_CIRCLE, color=ft.Colors.GREEN_700),
                        mk_btn("Create Room (2 Dice 🎲🎲)",
                               lambda e: page.run_task(do_create, True),
                               icon=ft.Icons.ADD_CIRCLE,
                               color=ft.Colors.DEEP_PURPLE_700),
                        ft.Divider(color="#44446a"),
                        ft.Text("— or join an existing room —",
                                size=12, color=ft.Colors.WHITE54),
                        ft.Row([
                            code_f,
                            ft.ElevatedButton(
                                "Join", on_click=do_join,
                                style=ft.ButtonStyle(
                                    shape=ft.RoundedRectangleBorder(radius=10),
                                    bgcolor=ft.Colors.BLUE_700,
                                    color=ft.Colors.WHITE),
                            ),
                        ], alignment=ft.MainAxisAlignment.CENTER, spacing=8),
                        info,
                        ft.Divider(color="#44446a"),
                        mk_btn("← Back", lambda e: show_menu_screen(),
                               color=ft.Colors.GREY_700),
                    ],
                ),
            ),
        ])

    def show_game_screen():
        # init audio the first time we enter the game screen
        init_audio()

        roll_btn.on_click = lambda e: page.run_task(roll_dice, e)
        page.run_task(play_bgm)

        emote_row.controls.clear()
        for em in EMOTES:
            emote_row.controls.append(ft.ElevatedButton(
                text=em,
                on_click=lambda e, em=em: page.run_task(send_emote, em),
                style=ft.ButtonStyle(
                    shape=ft.RoundedRectangleBorder(radius=8),
                    bgcolor="#2d2d44", color=ft.Colors.WHITE,
                    padding=ft.Padding(left=5, right=5, top=4, bottom=4),
                ),
            ))

        dice_row = ft.Row(
            controls=[dice1_txt] + ([dice2_txt] if gs["two_dice_mode"] else []),
            alignment=ft.MainAxisAlignment.CENTER, spacing=10,
        )
        chat_section = ft.Column([
            ft.Text("💬 Chat", size=11, weight=ft.FontWeight.BOLD,
                    color=ft.Colors.WHITE70),
            chat_list,
            ft.Row([
                chat_field,
                ft.IconButton(icon=ft.Icons.SEND, icon_color=ft.Colors.PURPLE_300,
                              on_click=lambda e: page.run_task(send_chat, e)),
            ], spacing=4),
        ], spacing=4) if gs["is_online"] else ft.Container(height=0)

        async def go_back(e):
            gs["stop_poll"] = True
            gs["game_started"] = False
            await stop_bgm()
            show_menu_screen()

        refresh_ui()
        show([
            ft.Container(
                expand=True, bgcolor="#1a1a2e",
                content=ft.Column(
                    scroll=ft.ScrollMode.AUTO,
                    spacing=6,
                    controls=[
                        ft.Container(
                            content=ft.Row([
                                ft.IconButton(
                                    icon=ft.Icons.ARROW_BACK,
                                    icon_color=ft.Colors.WHITE,
                                    on_click=lambda e: page.run_task(go_back, e),
                                ),
                                status_txt,
                                ft.Row([
                                    ft.IconButton(
                                        icon=ft.Icons.VOLUME_UP,
                                        icon_color=ft.Colors.WHITE,
                                        on_click=lambda e: (
                                            _sfx_on.update({"v": not _sfx_on["v"]}),
                                            page.update()
                                        ),
                                    ),
                                    ft.IconButton(
                                        icon=ft.Icons.MUSIC_NOTE,
                                        icon_color=ft.Colors.WHITE,
                                        on_click=lambda e: (
                                            _bgm_on.update({"v": not _bgm_on["v"]}),
                                            page.run_task(
                                                play_bgm if _bgm_on["v"] else stop_bgm
                                            )
                                        ),
                                    ),
                                ], spacing=0),
                            ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
                            bgcolor="#12122a",
                            padding=ft.Padding(left=6, right=6, top=6, bottom=6),
                        ),
                        pstrip,
                        ft.Container(
                            content=board_col,
                            alignment=ft.alignment.center,
                            padding=ft.Padding(left=1, right=1, top=0, bottom=0),
                        ),
                        ft.Container(
                            content=ft.Row(
                                [dice_row, roll_btn],
                                alignment=ft.MainAxisAlignment.SPACE_AROUND,
                                spacing=10,
                            ),
                            bgcolor="#12122a", padding=10, border_radius=10,
                        ),
                        ft.Container(
                            content=ft.Column([
                                ft.Text("😄 Emotes", size=10,
                                        color=ft.Colors.WHITE54),
                                emote_row,
                            ], spacing=3),
                            padding=ft.Padding(left=6, right=6, top=0, bottom=0),
                        ),
                        chat_section,
                        support_card(),
                        ft.Container(height=20),
                    ],
                ),
            ),
        ])
        if not gs["is_online"]:
            page.run_task(maybe_bot)

    def show_tournament_screen():
        t_list  = ft.ListView(expand=True, spacing=6, height=360)
        spinner = ft.ProgressRing(visible=True, width=24, height=24,
                                  color=ft.Colors.AMBER_400)

        async def load():
            try:
                data = await fb_get("tournaments", gs["user"]["idToken"])
                spinner.visible = False
                t_list.controls.clear()
                if not data or not isinstance(data, dict):
                    t_list.controls.append(
                        ft.Text("No active tournaments", color=ft.Colors.WHITE54,
                                text_align=ft.TextAlign.CENTER))
                else:
                    for tid, t in data.items():
                        cnt = len(t.get("players", {}))
                        t_list.controls.append(ft.Container(
                            content=ft.Row([
                                ft.Column([
                                    ft.Text(t.get("name","Tournament"), size=13,
                                            weight=ft.FontWeight.BOLD,
                                            color=ft.Colors.WHITE),
                                    ft.Text(
                                        f"👥 {cnt}/8  🏆 {t.get('prize_coins',500)} coins",
                                        size=11, color=ft.Colors.WHITE70),
                                ], expand=True, spacing=2),
                                ft.ElevatedButton(
                                    "Join",
                                    on_click=lambda e, tid=tid: page.run_task(join_t, tid),
                                    style=ft.ButtonStyle(
                                        shape=ft.RoundedRectangleBorder(radius=8),
                                        bgcolor=ft.Colors.AMBER_700,
                                        color=ft.Colors.WHITE),
                                ),
                            ]),
                            bgcolor="#2d2d44", padding=12, border_radius=10,
                        ))
                try: page.update()
                except Exception: pass
            except Exception as ex:
                spinner.visible = False
                snack(str(ex), ft.Colors.RED_700)
                try: page.update()
                except Exception: pass

        async def join_t(tid):
            try:
                uid = gs["user"]["localId"]
                await fb_patch(f"tournaments/{tid}/players/{uid}", {
                    "email": gs["user_data"]["email"],
                    "elo": gs["user_data"].get("elo", DEFAULT_ELO),
                }, gs["user"]["idToken"])
                snack("Joined! 🏆", ft.Colors.GREEN_700)
            except Exception as ex:
                snack(str(ex), ft.Colors.RED_700)

        async def create_t(e):
            name = f"Tournament {random.randint(100,999)}"
            tid  = f"t_{int(time.time())}"
            try:
                await fb_put(f"tournaments/{tid}", {
                    "name": name, "created_by": gs["user"]["localId"],
                    "prize_coins": 500, "state": "open",
                    "players": {gs["user"]["localId"]: {
                        "email": gs["user_data"]["email"],
                        "elo": gs["user_data"].get("elo", DEFAULT_ELO),
                    }},
                    "created_at": int(time.time()),
                }, gs["user"]["idToken"])
                snack(f"'{name}' created! 🎉", ft.Colors.GREEN_700)
                await load()
            except Exception as ex:
                snack(str(ex), ft.Colors.RED_700)

        show([
            mk_header("Tournaments 🏆"),
            ft.Container(
                expand=True, bgcolor="#1a1a2e", padding=16,
                content=ft.Column(
                    scroll=ft.ScrollMode.AUTO,
                    horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                    spacing=10,
                    controls=[
                        mk_btn("+ Create Tournament", create_t,
                               icon=ft.Icons.ADD, color=ft.Colors.AMBER_700),
                        ft.Divider(color="#44446a"),
                        spinner, t_list,
                        mk_btn("← Back", lambda e: show_menu_screen(),
                               color=ft.Colors.GREY_700),
                    ],
                ),
            ),
        ])
        page.run_task(load)

    def show_leaderboard_screen():
        lb_list = ft.ListView(expand=True, spacing=6, height=460)
        spinner = ft.ProgressRing(visible=True, width=24, height=24,
                                  color=ft.Colors.PINK_400)

        async def load():
            try:
                data = await fb_get("users", gs["user"]["idToken"])
                spinner.visible = False
                lb_list.controls.clear()
                if not data or not isinstance(data, dict):
                    lb_list.controls.append(
                        ft.Text("No data yet", color=ft.Colors.WHITE54))
                else:
                    ranked = sorted(
                        [(uid, u) for uid, u in data.items()
                         if isinstance(u, dict)],
                        key=lambda x: x[1].get("elo", DEFAULT_ELO),
                        reverse=True,
                    )[:20]
                    medals = ["🥇","🥈","🥉"] + ["🎖️"]*17
                    for i, (uid, u) in enumerate(ranked):
                        is_me = gs["user"] and uid == gs["user"].get("localId")
                        lb_list.controls.append(ft.Container(
                            content=ft.Row([
                                ft.Text(medals[i], size=18),
                                ft.Column([
                                    ft.Text(
                                        u.get("display_name",
                                              u.get("email","?"))[:20],
                                        size=13, weight=ft.FontWeight.BOLD,
                                        color=ft.Colors.WHITE),
                                    ft.Text(
                                        f"ELO {u.get('elo',DEFAULT_ELO)}  "
                                        f"🏆 {u.get('wins',0)} wins",
                                        size=11, color=ft.Colors.WHITE70),
                                ], expand=True, spacing=2),
                            ], spacing=8),
                            bgcolor=ft.Colors.PURPLE_900 if is_me else "#2d2d44",
                            padding=10, border_radius=10,
                            border=(ft.border.all(1, ft.Colors.PURPLE_400)
                                    if is_me else None),
                        ))
                try: page.update()
                except Exception: pass
            except Exception as ex:
                spinner.visible = False
                snack(str(ex), ft.Colors.RED_700)
                try: page.update()
                except Exception: pass

        show([
            mk_header("Leaderboard 📊"),
            ft.Container(
                expand=True, bgcolor="#1a1a2e", padding=16,
                content=ft.Column(
                    scroll=ft.ScrollMode.AUTO,
                    horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                    spacing=10,
                    controls=[
                        spinner, lb_list,
                        mk_btn("← Back", lambda e: show_menu_screen(),
                               color=ft.Colors.GREY_700),
                    ],
                ),
            ),
        ])
        page.run_task(load)

    # ── LAUNCH ────────────────────────────────────────────────────────────────
    show_login_screen()


ft.app(target=main)
