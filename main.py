"""
LUDO PRO MAX — Complete Professional Edition
Features: Solo vs AI (Easy/Hard/Hardest), Online Multiplayer, 2-Dice Mode,
          ELO Rating, Tournaments, Chat, Emotes, Offline Support,
          Coin System, Skins, Leaderboard
Platform: Android, iOS, Desktop (via Flet)
"""

import flet as ft
import random, time, json, os, asyncio, aiohttp
from datetime import date, datetime

# ─────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────
FIREBASE_API_KEY   = os.environ.get('FIREBASE_API_KEY', '')
FIREBASE_DB_URL    = os.environ.get('FIREBASE_DB_URL', '')
FIREBASE_AUTH_URL  = "https://identitytoolkit.googleapis.com/v1/accounts"
OFFLINE_FILE       = "ludo_save.json"
FLUTTERWAVE_URL    = "https://flutterwave.com/pay/ou2066snurqa"
MAX_ADS_PER_DAY    = 5
APP_VERSION        = "2.0.0"

# ─────────────────────────────────────────────
# BOARD CONSTANTS
# ─────────────────────────────────────────────
BOARD_SIZE = 15

NEST_POS = [
    [(1,1),(1,4),(4,1),(4,4)],
    [(1,10),(1,13),(4,10),(4,13)],
    [(10,10),(10,13),(13,10),(13,13)],
    [(10,1),(10,4),(13,1),(13,4)]
]
START_POS   = [(6,1),(1,8),(8,13),(13,6)]
SAFE_SPOTS  = {(6,2),(2,6),(6,12),(8,2),(12,8),(8,12),(2,8),(12,6)}
FINAL_HOME  = (7,7)

TRACK_PATH = [
    (6,1),(6,2),(6,3),(6,4),(6,5),(5,6),(4,6),(3,6),(2,6),(1,6),(0,6),
    (0,7),(0,8),(1,8),(2,8),(3,8),(4,8),(5,8),(6,9),(6,10),(6,11),(6,12),(6,13),(6,14),
    (7,14),(8,14),(8,13),(8,12),(8,11),(8,10),(8,9),(9,8),(10,8),(11,8),(12,8),(13,8),(14,8),
    (14,7),(14,6),(13,6),(12,6),(11,6),(10,6),(9,6),(8,5),(8,4),(8,3),(8,2),(8,1),(8,0),
    (7,0),(6,0)
]
TRACK_SET = set(TRACK_PATH)

HOUSE_PATHS = [
    [(7,1),(7,2),(7,3),(7,4),(7,5),(7,6)],
    [(1,7),(2,7),(3,7),(4,7),(5,7),(6,7)],
    [(7,13),(7,12),(7,11),(7,10),(7,9),(7,8)],
    [(13,7),(12,7),(11,7),(10,7),(9,7),(8,7)]
]

PLAYER_COLORS = [ft.Colors.RED_600, ft.Colors.GREEN_600,
                 ft.Colors.YELLOW_700, ft.Colors.BLUE_600]
PLAYER_BG     = [ft.Colors.RED_100, ft.Colors.GREEN_100,
                 ft.Colors.YELLOW_100, ft.Colors.BLUE_100]
PLAYER_NAMES  = ["Red", "Green", "Yellow", "Blue"]
DICE_EMOJI    = {1:"⚀",2:"⚁",3:"⚂",4:"⚃",5:"⚄",6:"⚅"}
EMOTES        = ["😂","😡","😎","🎉","😭","👍","🤔","💀","🔥","👑"]

ELO_K = 32
DEFAULT_ELO = 1000

# ─────────────────────────────────────────────
# FIREBASE HELPERS
# ─────────────────────────────────────────────
async def fb_request(method, url, data=None):
    async with aiohttp.ClientSession() as s:
        try:
            fn = getattr(s, method)
            kw = {"json": data} if data else {}
            async with fn(url, **kw) as r:
                return await r.json()
        except Exception as e:
            return {"error": str(e)}

async def fb_auth(email, password, signup=False):
    ep  = "signUp" if signup else "signInWithPassword"
    url = f"{FIREBASE_AUTH_URL}:{ep}?key={FIREBASE_API_KEY}"
    return await fb_request("post", url, {"email":email,"password":password,"returnSecureToken":True})

async def fb_get(path, token):
    return await fb_request("get", f"{FIREBASE_DB_URL}/{path}.json?auth={token}")

async def fb_put(path, data, token):
    return await fb_request("put", f"{FIREBASE_DB_URL}/{path}.json?auth={token}", data)

async def fb_patch(path, data, token):
    return await fb_request("patch", f"{FIREBASE_DB_URL}/{path}.json?auth={token}", data)

async def fb_delete(path, token):
    async with aiohttp.ClientSession() as s:
        await s.delete(f"{FIREBASE_DB_URL}/{path}.json?auth={token}")

# ─────────────────────────────────────────────
# ELO
# ─────────────────────────────────────────────
def expected_score(ra, rb):
    return 1 / (1 + 10 ** ((rb - ra) / 400))

def new_elo(ra, rb, won):
    ea = expected_score(ra, rb)
    return int(ra + ELO_K * ((1 if won else 0) - ea))

# ─────────────────────────────────────────────
# MAIN APP
# ─────────────────────────────────────────────
async def main(page: ft.Page):
    page.title        = "Ludo Pro Max"
    page.theme_mode   = ft.ThemeMode.DARK
    page.bgcolor      = "#1a1a2e"
    page.padding      = 0
    page.update()

    # ── SOUND SYSTEM ─────────────────────────
    SOUNDS = {
        "dice":    "https://cdn.freesound.org/previews/362/362204_1676145-lq.mp3",
        "move":    "https://cdn.freesound.org/previews/399/399934_1676145-lq.mp3",
        "capture": "https://cdn.freesound.org/previews/331/331912_3248244-lq.mp3",
        "win":     "https://cdn.freesound.org/previews/456/456966_9159316-lq.mp3",
        "invalid": "https://cdn.freesound.org/previews/142/142608_1840739-lq.mp3",
        "six":     "https://cdn.freesound.org/previews/270/270402_5123851-lq.mp3",
        "bgm":     "https://cdn.freesound.org/previews/612/612598_5674468-lq.mp3",
    }

    _audio_players = {}
    _sound_enabled = {"value": True}
    _music_enabled = {"value": True}

    def make_audio(key, src, loop=False):
        try:
            player = ft.Audio(
                src=src,
                autoplay=False,
                volume=0.8 if key != "bgm" else 0.3,
                balance=0,
            )
            if loop:
                player.release_mode = ft.ReleaseMode.LOOP
            page.overlay.append(player)
            return player
        except:
            return None

    def init_audio():
        for key, url in SOUNDS.items():
            loop = key == "bgm"
            _audio_players[key] = make_audio(key, url, loop=loop)

    init_audio()

    async def play(sound_key):
        if not _sound_enabled["value"]: return
        if sound_key == "bgm": return
        player = _audio_players.get(sound_key)
        if player:
            try:
                await player.resume_async()
            except:
                try:
                    player.src = SOUNDS.get(sound_key, "")
                    await player.play_async()
                except: pass

    async def play_bgm():
        if not _music_enabled["value"]: return
        bgm = _audio_players.get("bgm")
        if bgm:
            try: await bgm.play_async()
            except: pass

    async def stop_bgm():
        bgm = _audio_players.get("bgm")
        if bgm:
            try: await bgm.pause_async()
            except: pass

    def toggle_sound(e=None):
        _sound_enabled["value"] = not _sound_enabled["value"]
        return _sound_enabled["value"]

    def toggle_music(e=None):
        _music_enabled["value"] = not _music_enabled["value"]
        if _music_enabled["value"]:
            page.run_task(play_bgm)
        else:
            page.run_task(stop_bgm)
        return _music_enabled["value"]

    # ── SHARED STATE ──────────────────────────
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
        "tournament": None, "tournament_id": None,
        "ads_today": 0,
    }

    # ── PERSISTENT UI WIDGETS ──────────────────
    dice1_text   = ft.Text("⚀", size=52, weight=ft.FontWeight.BOLD)
    dice2_text   = ft.Text("⚀", size=52, weight=ft.FontWeight.BOLD)
    roll_btn     = ft.ElevatedButton(
        "Roll Dice",
        icon=ft.Icons.CASINO,
        style=ft.ButtonStyle(
            shape=ft.RoundedRectangleBorder(radius=12),
            bgcolor=ft.Colors.PURPLE_700,
            color=ft.Colors.WHITE,
            padding=ft.Padding(left=24, right=24, top=14, bottom=14)
        )
    )
    status_bar   = ft.Text("", size=13, color=ft.Colors.WHITE70)
    board_col    = ft.Column(spacing=1, alignment=ft.MainAxisAlignment.CENTER)
    player_strip = ft.Row(wrap=True, alignment=ft.MainAxisAlignment.SPACE_AROUND, spacing=6)
    chat_list    = ft.ListView(height=90, spacing=2, auto_scroll=True)
    chat_field   = ft.TextField(
        hint_text="Message…", bgcolor="#2d2d44",
        border_radius=8, dense=True, expand=True,
        color=ft.Colors.WHITE,
        hint_style=ft.TextStyle(color=ft.Colors.WHITE38)
    )
    emote_row    = ft.Row(scroll=ft.ScrollMode.AUTO, spacing=4)

    # ── SNACK ────────────────────────────────
    def snack(msg, color=ft.Colors.PURPLE_700):
        page.snack_bar = ft.SnackBar(
            ft.Text(msg, color=ft.Colors.WHITE, weight=ft.FontWeight.W_500),
            bgcolor=color, duration=2500
        )
        page.snack_bar.open = True
        try:
            page.update()
        except:
            pass

    # ── OFFLINE SAVE / LOAD ───────────────────
    def save_offline():
        if gs["user_data"]:
            try:
                with open(OFFLINE_FILE, "w") as f:
                    json.dump({"user": gs["user"], "user_data": gs["user_data"]}, f)
            except: pass

    def load_offline():
        if os.path.exists(OFFLINE_FILE):
            try:
                with open(OFFLINE_FILE) as f:
                    d = json.load(f)
                    gs["user"]      = d.get("user")
                    gs["user_data"] = d.get("user_data")
                    return True
            except: pass
        return False

    # ── USER DATA ────────────────────────────
    async def sync_user():
        if gs["user"] and gs["user_data"]:
            uid = gs["user"]["localId"]
            try:
                await fb_put(f"users/{uid}", gs["user_data"], gs["user"]["idToken"])
            except: pass
            save_offline()

    async def init_user(uid, email):
        existing = await fb_get(f"users/{uid}", gs["user"]["idToken"])
        if not existing or "email" not in existing:
            existing = {
                "email": email, "display_name": email.split("@")[0],
                "coins": 500, "wins": 0, "losses": 0, "games": 0,
                "elo": DEFAULT_ELO, "tournament_wins": 0,
                "skins": {"board": "classic", "dice": "default"},
                "ads": {"date": "", "count": 0},
                "achievements": []
            }
            try:
                await fb_put(f"users/{uid}", existing, gs["user"]["idToken"])
            except: pass
        gs["user_data"] = existing
        save_offline()

    # ── BOARD POSITION HELPERS ────────────────
    def path_index(player, pos):
        pos = tuple(pos)
        if pos in [tuple(n) for n in NEST_POS[player]]: return -1
        if pos == FINAL_HOME: return 200
        for i, hp in enumerate(HOUSE_PATHS[player]):
            if pos == tuple(hp): return 100 + i
        if pos in TRACK_SET:
            start = START_POS[player]
            si = TRACK_PATH.index(start)
            pi = TRACK_PATH.index(pos)
            return (pi - si) % len(TRACK_PATH)
        return -2

    def can_move_token(player, t_idx, steps):
        pos  = gs["tokens"][player][t_idx]
        pidx = path_index(player, pos)
        if pidx == -1:   return steps == 6
        if pidx == 200:  return False
        if pidx >= 100:  return (pidx - 100) + steps <= 5
        remaining = len(TRACK_PATH) - pidx
        if steps >= remaining:
            home_steps = steps - remaining
            return home_steps <= 6
        return True

    def compute_new_pos(player, t_idx, steps):
        pos  = gs["tokens"][player][t_idx]
        pidx = path_index(player, pos)
        if pidx == -1:
            return list(START_POS[player])
        if pidx >= 100:
            ni = (pidx - 100) + steps
            return list(HOUSE_PATHS[player][ni]) if ni < 6 else list(FINAL_HOME)
        ti = TRACK_PATH.index(tuple(pos))
        remaining = len(TRACK_PATH) - (ti - TRACK_PATH.index(START_POS[player])) % len(TRACK_PATH)
        if steps >= remaining:
            home_steps = steps - remaining
            if home_steps < 6:
                return list(HOUSE_PATHS[player][home_steps])
            elif home_steps == 6:
                return list(FINAL_HOME)
        ni = (ti + steps) % len(TRACK_PATH)
        return list(TRACK_PATH[ni])

    def all_home(player):
        return all(tuple(p) == FINAL_HOME for p in gs["tokens"][player])

    # ── MOVE TOKEN ────────────────────────────
    async def do_move(player, t_idx, steps):
        if not can_move_token(player, t_idx, steps):
            return False

        new_pos = compute_new_pos(player, t_idx, steps)
        captured = False

        if (tuple(new_pos) not in SAFE_SPOTS and
            new_pos not in [list(hp) for hp in HOUSE_PATHS[player]] and
            tuple(new_pos) != FINAL_HOME):
            for p, tokens in gs["tokens"].items():
                if p == player: continue
                for ti, tp in enumerate(tokens):
                    if tp == new_pos and tuple(tp) not in SAFE_SPOTS:
                        gs["tokens"][p][ti] = list(NEST_POS[p][ti])
                        snack(f"💥 {PLAYER_NAMES[player]} captured {PLAYER_NAMES[p]}!", ft.Colors.RED_700)
                        captured = True
                        gs["extra_turn"] = True
                        await play("capture")

        gs["tokens"][player][t_idx] = new_pos
        await play("move")
        gs["dice1"] = 0
        gs["dice2"] = 0
        dice1_text.value = "⚀"
        dice2_text.value = "⚀"

        if all_home(player):
            gs["finished_players"].append(player)
            total_p = len(gs["players"])
            if player == gs["player_index"]:
                place = len(gs["finished_players"])
                coin_reward = max(0, [300, 200, 100, 50][place - 1])
                gs["user_data"]["wins"]  += 1
                gs["user_data"]["coins"] += coin_reward
                gs["user_data"]["games"] += 1
                opp_elo = 1000
                gs["user_data"]["elo"] = new_elo(gs["user_data"]["elo"], opp_elo, True)
                await sync_user()
                snack(f"🏆 You finished #{place}! +{coin_reward} coins", ft.Colors.GREEN_700)
            elif len(gs["finished_players"]) == total_p - 1:
                last = [p for p in range(total_p) if p not in gs["finished_players"]][0]
                if last == gs["player_index"]:
                    gs["user_data"]["losses"] += 1
                    gs["user_data"]["elo"] = new_elo(gs["user_data"]["elo"], 1000, False)
                    await sync_user()
                gs["winner"] = gs["finished_players"][0]
                update_ui()
                await play("win")
                await show_game_over(gs["winner"])
                return True

        if steps != 6 and not captured and not gs["extra_turn"]:
            await advance_turn()
        else:
            gs["extra_turn"] = False
            gs["six_count"] = 0 if steps != 6 else gs["six_count"]
            update_ui()
            if not gs["is_online"]:
                await maybe_bot_turn()

        await sync_room()
        update_ui()
        return True

    # ── DICE ROLL ─────────────────────────────
    async def roll_dice(e):
        if not gs["can_roll"] or gs["bot_thinking"]: return
        if gs["current_turn"] != gs["player_index"]: return
        if not gs["game_started"]: return

        gs["can_roll"] = False

        d1 = random.randint(1, 6)
        d2 = random.randint(1, 6) if gs["two_dice_mode"] else 0
        gs["dice1"] = d1
        gs["dice2"] = d2
        dice1_text.value = DICE_EMOJI[d1]
        if gs["two_dice_mode"]:
            dice2_text.value = DICE_EMOJI[d2]

        await play("dice")
        total = d1 + d2 if gs["two_dice_mode"] else d1

        if d1 == 6 or (gs["two_dice_mode"] and d2 == 6):
            gs["six_count"] += 1
            gs["extra_turn"] = True
            await play("six")
            if gs["six_count"] == 3:
                snack("3 sixes — turn skipped! ⛔", ft.Colors.RED_700)
                await play("invalid")
                gs["dice1"] = gs["dice2"] = 0
                gs["six_count"] = 0
                gs["extra_turn"] = False
                gs["can_roll"] = True
                await advance_turn()
                return
        else:
            gs["six_count"] = 0
            gs["extra_turn"] = False

        player = gs["player_index"]
        movable = [i for i in range(4) if can_move_token(player, i, total)]
        if not movable:
            snack("No moves available 😔", ft.Colors.ORANGE_700)
            await play("invalid")
            gs["dice1"] = gs["dice2"] = 0
            dice1_text.value = "⚀"
            dice2_text.value = "⚀"
            if not gs["extra_turn"]:
                await advance_turn()

        gs["can_roll"] = True
        await sync_room()
        update_ui()

    # ── TURN MANAGEMENT ───────────────────────
    async def advance_turn():
        if gs["winner"] is not None: return
        total = len(gs["players"])
        nxt = (gs["current_turn"] + 1) % total
        loops = 0
        while nxt in gs["finished_players"] and loops < total:
            nxt = (nxt + 1) % total
            loops += 1
        gs["current_turn"] = nxt
        gs["dice1"] = gs["dice2"] = 0
        dice1_text.value = "⚀"
        dice2_text.value = "⚀"
        update_ui()
        if not gs["is_online"]:
            await maybe_bot_turn()

    async def maybe_bot_turn():
        if gs["winner"] is not None: return
        cur = gs["current_turn"]
        if gs["local_players"] == 0 and cur == gs["player_index"]: return
        if gs["local_players"] > 1 and cur == 0: return
        if not gs["bot_thinking"]:
            asyncio.create_task(run_bot())

    # ── BOT AI ────────────────────────────────
    async def run_bot():
        gs["bot_thinking"] = True
        await asyncio.sleep(0.9)
        if gs["winner"] is not None:
            gs["bot_thinking"] = False
            return

        bot = gs["current_turn"]
        d1  = random.randint(1, 6)
        d2  = random.randint(1, 6) if gs["two_dice_mode"] else 0
        total = d1 + d2 if gs["two_dice_mode"] else d1
        gs["dice1"] = d1
        gs["dice2"] = d2
        dice1_text.value = DICE_EMOJI[d1]
        if gs["two_dice_mode"]: dice2_text.value = DICE_EMOJI[d2]

        diff = gs["bot_difficulty"]
        snack(f"{PLAYER_NAMES[bot]} rolled {total}", ft.Colors.BLUE_GREY_700)
        update_ui()
        await asyncio.sleep(0.7)

        moves = []
        for ti in range(4):
            if not can_move_token(bot, ti, total): continue
            pos   = gs["tokens"][bot][ti]
            pidx  = path_index(bot, pos)
            score = 0

            if diff == "easy":
                score = random.randint(0, 100)

            elif diff == "hard":
                npos = compute_new_pos(bot, ti, total)
                for p, toks in gs["tokens"].items():
                    if p == bot: continue
                    if npos in toks and tuple(npos) not in SAFE_SPOTS:
                        score += 150
                if pidx >= 100: score += 80
                if pidx == -1:  score += 40
                score += pidx if pidx >= 0 else 0

            elif diff == "hardest":
                npos = compute_new_pos(bot, ti, total)
                npidx = path_index(bot, npos)
                for p, toks in gs["tokens"].items():
                    if p == bot: continue
                    if npos in toks and tuple(npos) not in SAFE_SPOTS:
                        score += 300
                if tuple(npos) == FINAL_HOME:      score += 500
                if npidx >= 100:                   score += 200
                if pidx == -1:                     score += 80
                score += (pidx if 0 <= pidx < 100 else 0) * 2
                if tuple(npos) not in SAFE_SPOTS:  score -= 10
                score += random.randint(0, 20)

            moves.append((ti, score))

        if moves:
            best = max(moves, key=lambda x: x[1])[0]
            await do_move(bot, best, total)
        else:
            snack(f"{PLAYER_NAMES[bot]} has no moves", ft.Colors.GREY_600)
            gs["dice1"] = gs["dice2"] = 0
            if total != 6: await advance_turn()
            else: update_ui()

        gs["bot_thinking"] = False

    # ── TOKEN CLICK ───────────────────────────
    async def token_click(e):
        if not gs["game_started"]: return
        if gs["current_turn"] != gs["player_index"]: return
        total = gs["dice1"] + gs["dice2"] if gs["two_dice_mode"] else gs["dice1"]
        if total == 0:
            snack("Roll the dice first! 🎲", ft.Colors.ORANGE_700)
            return
        try:
            p_idx, t_idx = map(int, e.control.data.split(","))
        except: return
        if p_idx != gs["player_index"]: return
        await do_move(p_idx, t_idx, total)

    # ── BOARD BUILDER ─────────────────────────
    def build_board():
        board_col.controls.clear()
        cell_size = 24

        for row_idx in range(BOARD_SIZE):
            row = ft.Row(spacing=1, alignment=ft.MainAxisAlignment.CENTER)
            for col_idx in range(BOARD_SIZE):
                bg   = "#2d2d44"
                text = ""
                border = ft.border.all(0.4, "#44446a")

                if   (row_idx,col_idx) in NEST_POS[0]: bg = "#c62828"
                elif (row_idx,col_idx) in NEST_POS[1]: bg = "#2e7d32"
                elif (row_idx,col_idx) in NEST_POS[2]: bg = "#f9a825"
                elif (row_idx,col_idx) in NEST_POS[3]: bg = "#1565c0"
                elif (row_idx,col_idx) in SAFE_SPOTS:  bg, text = "#607d8b", "★"
                elif (row_idx,col_idx) in [tuple(x) for x in HOUSE_PATHS[0]]: bg, text = "#ef9a9a", "↑"
                elif (row_idx,col_idx) in [tuple(x) for x in HOUSE_PATHS[1]]: bg, text = "#a5d6a7", "→"
                elif (row_idx,col_idx) in [tuple(x) for x in HOUSE_PATHS[2]]: bg, text = "#fff59d", "↓"
                elif (row_idx,col_idx) in [tuple(x) for x in HOUSE_PATHS[3]]: bg, text = "#90caf9", "←"
                elif (row_idx,col_idx) == FINAL_HOME:  bg, text = "#7b1fa2", "🏠"
                elif (row_idx,col_idx) == START_POS[0]: bg = "#e53935"
                elif (row_idx,col_idx) == START_POS[1]: bg = "#43a047"
                elif (row_idx,col_idx) == START_POS[2]: bg = "#fdd835"
                elif (row_idx,col_idx) == START_POS[3]: bg = "#1e88e5"
                elif (row_idx,col_idx) in TRACK_SET:   bg = "#3a3a5c"

                tokens_here = []
                for pi, toks in gs["tokens"].items():
                    for ti, tp in enumerate(toks):
                        if tuple(tp) == (row_idx, col_idx):
                            tokens_here.append((pi, ti))

                cell_content = ft.Text(text, size=9, weight=ft.FontWeight.BOLD,
                                       color=ft.Colors.WHITE)

                if len(tokens_here) == 1:
                    pi, ti = tokens_here[0]
                    rad = (cell_size - 6) // 2
                    cell_content = ft.Container(
                        width=cell_size-6, height=cell_size-6,
                        border_radius=ft.BorderRadius(rad, rad, rad, rad),
                        bgcolor=PLAYER_COLORS[pi],
                        border=ft.border.all(1.5, ft.Colors.WHITE),
                        alignment=ft.alignment.center,
                        data=f"{pi},{ti}",
                        on_click=lambda e: page.run_task(token_click, e),
                        content=ft.Text(str(ti+1), size=8, color=ft.Colors.WHITE,
                                        weight=ft.FontWeight.BOLD),
                        shadow=ft.BoxShadow(blur_radius=4, color=ft.Colors.BLACK54)
                    )
                elif len(tokens_here) > 1:
                    stack_items = []
                    for i, (pi, ti) in enumerate(tokens_here[:4]):
                        stack_items.append(ft.Container(
                            width=11, height=11,
                            border_radius=ft.BorderRadius(6, 6, 6, 6),
                            bgcolor=PLAYER_COLORS[pi],
                            left=i*5, top=i*4,
                            border=ft.border.all(1, ft.Colors.WHITE),
                            data=f"{pi},{ti}",
                            on_click=lambda e: page.run_task(token_click, e),
                        ))
                    cell_content = ft.Stack(stack_items, width=cell_size, height=cell_size)

                cell = ft.Container(
                    width=cell_size, height=cell_size,
                    bgcolor=bg, border=border,
                    alignment=ft.alignment.center,
                    content=cell_content,
                    border_radius=ft.BorderRadius(2, 2, 2, 2),
                )
                row.controls.append(cell)
            board_col.controls.append(row)

    # ── UI UPDATE ─────────────────────────────
    def update_ui():
        is_turn  = gs["current_turn"] == gs["player_index"]
        total_d  = gs["dice1"] + gs["dice2"] if gs["two_dice_mode"] else gs["dice1"]
        can_roll = (is_turn and total_d == 0 and gs["game_started"]
                    and gs["winner"] is None and not gs["bot_thinking"])
        roll_btn.disabled = not can_roll

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
            status_bar.value = (
                f"🪙 {ud['coins']}  |  🏆 {ud['wins']} wins  |  "
                f"📊 ELO {ud.get('elo', DEFAULT_ELO)}"
            )

        player_strip.controls.clear()
        for idx in range(len(gs["players"])):
            name = gs["players"].get(idx, PLAYER_NAMES[idx])
            finished = idx in gs["finished_players"]
            is_active = idx == gs["current_turn"] and not finished
            player_strip.controls.append(
                ft.Container(
                    content=ft.Column([
                        ft.Text(PLAYER_NAMES[idx], size=10,
                                color=ft.Colors.WHITE, weight=ft.FontWeight.BOLD),
                        ft.Text(name[:10], size=9, color=ft.Colors.WHITE70),
                        ft.Text("✅" if finished else ("🎲" if is_active else ""),
                                size=10)
                    ], spacing=1, horizontal_alignment=ft.CrossAxisAlignment.CENTER),
                    bgcolor=PLAYER_COLORS[idx] if is_active else "#2d2d44",
                    padding=ft.Padding(left=8, right=8, top=5, bottom=5),
                    border_radius=ft.BorderRadius(8, 8, 8, 8),
                    border=ft.border.all(2 if is_active else 0, ft.Colors.WHITE),
                    shadow=ft.BoxShadow(blur_radius=6, color=ft.Colors.BLACK38) if is_active else None
                )
            )

        build_board()
        try:
            page.update()
        except: pass

    # ── CHAT ─────────────────────────────────
    def update_chat():
        chat_list.controls.clear()
        for m in gs["chat_messages"][-30:]:
            color = PLAYER_COLORS[
                PLAYER_NAMES.index(m["player"]) if m["player"] in PLAYER_NAMES else 0
            ]
            chat_list.controls.append(
                ft.Row([
                    ft.Container(
                        ft.Text(m["player"], size=10, color=ft.Colors.WHITE,
                                weight=ft.FontWeight.BOLD),
                        bgcolor=color, padding=ft.Padding(left=5, right=5, top=2, bottom=2),
                        border_radius=ft.BorderRadius(4, 4, 4, 4)
                    ),
                    ft.Text(m["msg"], size=11, color=ft.Colors.WHITE70, expand=True)
                ], spacing=5)
            )
        try: page.update()
        except: pass

    async def send_chat(e):
        msg = chat_field.value.strip()
        if not msg: return
        chat_field.value = ""
        if gs["is_online"] and gs["room_id"] and gs["user"]:
            entry = {"player": PLAYER_NAMES[gs["player_index"]], "msg": msg, "time": int(time.time())}
            try:
                await fb_patch(f"rooms/{gs['room_id']}/chat/{int(time.time()*1000)}",
                               entry, gs["user"]["idToken"])
            except: pass
        else:
            gs["chat_messages"].append({"player": PLAYER_NAMES[gs["player_index"]], "msg": msg})
            update_chat()
        page.update()

    async def send_emote(emote):
        msg = {"player": PLAYER_NAMES[gs["player_index"]], "msg": emote, "time": int(time.time())}
        if gs["is_online"] and gs["room_id"] and gs["user"]:
            try:
                await fb_patch(f"rooms/{gs['room_id']}/chat/{int(time.time()*1000)}",
                               msg, gs["user"]["idToken"])
            except: pass
        else:
            gs["chat_messages"].append(msg)
            update_chat()

    # ── ONLINE POLLING ───────────────────────
    async def poll_room():
        last = None
        while not gs["stop_poll"] and gs["is_online"] and gs["room_id"]:
            try:
                room = await fb_get(f"rooms/{gs['room_id']}", gs["user"]["idToken"])
                if room and room != last:
                    gs["tokens"]        = {int(k): v for k,v in room.get("tokens",{}).items()}
                    gs["current_turn"]  = room.get("current_turn", gs["current_turn"])
                    gs["dice1"]         = room.get("dice1", 0)
                    gs["dice2"]         = room.get("dice2", 0)
                    gs["winner"]        = room.get("winner")
                    gs["players"]       = {int(k): v for k,v in room.get("players",{}).items()}
                    gs["finished_players"] = room.get("finished_players", [])
                    if room.get("state") == "playing":
                        gs["game_started"] = True
                    chat_data = room.get("chat", {})
                    if len(chat_data) != gs["last_chat_len"]:
                        gs["chat_messages"] = sorted(chat_data.values(), key=lambda x: x["time"])
                        gs["last_chat_len"] = len(chat_data)
                        update_chat()
                    dice1_text.value = DICE_EMOJI.get(gs["dice1"], "⚀")
                    dice2_text.value = DICE_EMOJI.get(gs["dice2"], "⚀")
                    update_ui()
                    last = room
            except: pass
            await asyncio.sleep(1.2)

    def start_poll():
        gs["stop_poll"] = False
        if gs["poll_task"] is None or gs["poll_task"].done():
            gs["poll_task"] = asyncio.create_task(poll_room())

    async def sync_room():
        if gs["is_online"] and gs["room_id"] and gs["user"]:
            try:
                await fb_patch(f"rooms/{gs['room_id']}", {
                    "tokens":           {str(k): v for k,v in gs["tokens"].items()},
                    "current_turn":     gs["current_turn"],
                    "dice1":            gs["dice1"],
                    "dice2":            gs["dice2"],
                    "winner":           gs["winner"],
                    "finished_players": gs["finished_players"],
                }, gs["user"]["idToken"])
            except: pass

    # ── ROOM MANAGEMENT ──────────────────────
    async def create_room(two_dice=False):
        code = str(random.randint(100000, 999999))
        gs.update({
            "room_id": code, "player_index": 0, "is_host": True,
            "is_online": True, "two_dice_mode": two_dice,
            "players": {0: gs["user_data"]["email"]},
            "tokens":  {0: [list(p) for p in NEST_POS[0]]},
            "game_started": False, "winner": None, "finished_players": []
        })
        await fb_put(f"rooms/{code}", {
            "players":           {"0": gs["user_data"]["email"]},
            "tokens":            {"0": [list(p) for p in NEST_POS[0]]},
            "current_turn":      0, "dice1": 0, "dice2": 0,
            "winner":            None, "state": "waiting",
            "two_dice_mode":     two_dice,
            "finished_players":  [],
            "chat":              {}
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
        await fb_patch(f"rooms/{code}", {
            "players": players, "tokens": tokens, "state": state
        }, gs["user"]["idToken"])
        gs.update({
            "room_id": code, "player_index": idx, "is_online": True,
            "two_dice_mode": room.get("two_dice_mode", False),
            "players": {int(k): v for k,v in players.items()},
            "tokens":  {int(k): v for k,v in tokens.items()},
            "game_started": state == "playing",
            "winner": None, "finished_players": []
        })
        start_poll()
        return True, "Joined!"

    # ── GAME SETUP ───────────────────────────
    def setup_game(num_players, mode="bot", difficulty="hard", two_dice=False):
        gs.update({
            "stop_poll": True, "is_online": False,
            "two_dice_mode": two_dice,
            "player_index": 0, "is_host": True,
            "local_players": num_players if mode == "local" else 0,
            "bot_difficulty": difficulty,
            "game_started": True, "current_turn": 0,
            "winner": None, "finished_players": [],
            "dice1": 0, "dice2": 0, "six_count": 0, "extra_turn": False,
            "bot_thinking": False, "can_roll": True
        })
        if mode == "bot":
            gs["players"] = {0: "You", 1: "Bot A", 2: "Bot B", 3: "Bot C"}
            gs["tokens"]  = {i: [list(p) for p in NEST_POS[i]] for i in range(4)}
        else:
            gs["players"] = {i: f"Player {i+1}" for i in range(num_players)}
            gs["tokens"]  = {i: [list(p) for p in NEST_POS[i]] for i in range(num_players)}
        gs["user_data"]["games"] = gs["user_data"].get("games", 0) + 1
        dice1_text.value = "⚀"
        dice2_text.value = "⚀"

    # ─────────────────────────────────────────
    # HELPER WIDGETS
    # ─────────────────────────────────────────

    def header(title):
        return ft.Container(
            ft.Row([
                ft.Text("🎲", size=22),
                ft.Text(title, size=20, weight=ft.FontWeight.BOLD, color=ft.Colors.WHITE),
            ], spacing=8),
            bgcolor="#12122a",
            padding=ft.Padding(left=20, right=20, top=14, bottom=14),
        )

    def primary_btn(text, on_click, icon=None, color=ft.Colors.PURPLE_700, width=300):
        return ft.ElevatedButton(
            text, icon=icon, on_click=on_click, width=width,
            style=ft.ButtonStyle(
                shape=ft.RoundedRectangleBorder(radius=12),
                bgcolor=color, color=ft.Colors.WHITE,
                padding=ft.Padding(left=20, right=20, top=14, bottom=14),
                elevation=4
            )
        )

    # ── SUPPORT CARD ─────────────────────────
    def support_card():
        thanked = ft.Text("", size=12, color=ft.Colors.GREEN_400,
                          weight=ft.FontWeight.BOLD, visible=False)

        async def on_support(e):
            page.launch_url(FLUTTERWAVE_URL)
            if gs["user_data"] and not gs.get("support_rewarded"):
                gs["user_data"]["coins"] = gs["user_data"].get("coins", 0) + 100
                gs["support_rewarded"] = True
                await sync_user()
                thanked.value = "🎉 Thank you! +100 coins added!"
                thanked.visible = True
                update_ui()
                page.update()

        return ft.Container(
            ft.Column([
                ft.Row([
                    ft.Icon(ft.Icons.VOLUNTEER_ACTIVISM, color=ft.Colors.ORANGE_300, size=20),
                    ft.Text("Support the Developer", size=14,
                            weight=ft.FontWeight.BOLD, color=ft.Colors.WHITE),
                ], spacing=8),
                ft.Text(
                    "Ludo Pro Max is 100% free.\n"
                    "If you enjoy it, buy the dev a coffee ☕\n"
                    "Every contribution keeps the game alive and ad-free.",
                    size=12, color=ft.Colors.WHITE70
                ),
                thanked,
                ft.ElevatedButton(
                    "☕ Buy a Coffee — Support Us",
                    icon=ft.Icons.FAVORITE,
                    on_click=on_support,
                    style=ft.ButtonStyle(
                        shape=ft.RoundedRectangleBorder(radius=12),
                        bgcolor=ft.Colors.ORANGE_700,
                        color=ft.Colors.WHITE,
                        padding=ft.Padding(left=20, right=20, top=12, bottom=12),
                        elevation=4
                    ),
                    width=300
                )
            ], spacing=8, horizontal_alignment=ft.CrossAxisAlignment.CENTER),
            bgcolor="#2d1f0a",
            padding=16,
            border_radius=14,
            border=ft.border.all(1, ft.Colors.ORANGE_800),
            width=320
        )

    # ── GAME OVER DIALOG ─────────────────────
    async def show_game_over(winner_idx):
        place_labels = ["🥇 1st Place", "🥈 2nd Place", "🥉 3rd Place", "4th Place"]
        coin_rewards = [300, 200, 100, 50]
        my_place = (gs["finished_players"].index(gs["player_index"])
                    if gs["player_index"] in gs["finished_players"]
                    else len(gs["finished_players"]))
        coins_won = coin_rewards[min(my_place, 3)]

        async def rematch(e):
            page.close(dialog)
            setup_game(
                len(gs["players"]),
                "local" if gs["local_players"] > 0 else "bot",
                gs["bot_difficulty"],
                gs["two_dice_mode"]
            )
            page.go("/game")

        async def go_menu(e):
            page.close(dialog)
            gs["stop_poll"] = True
            page.go("/menu")

        dialog = ft.AlertDialog(
            modal=True,
            bgcolor="#1a1a2e",
            shape=ft.RoundedRectangleBorder(radius=16),
            content=ft.Column([
                ft.Text("🏆 Game Over!", size=24, weight=ft.FontWeight.BOLD,
                        color=ft.Colors.WHITE, text_align=ft.TextAlign.CENTER),
                ft.Text(f"{PLAYER_NAMES[winner_idx]} wins!",
                        size=18, color=PLAYER_COLORS[winner_idx],
                        text_align=ft.TextAlign.CENTER),
                ft.Divider(color="#44446a"),
                ft.Text(f"You finished: {place_labels[min(my_place, 3)]}",
                        size=14, color=ft.Colors.WHITE70,
                        text_align=ft.TextAlign.CENTER),
                ft.Text(f"Coins earned: +{coins_won} 🪙",
                        size=14, color=ft.Colors.AMBER_400,
                        text_align=ft.TextAlign.CENTER),
                ft.Text(f"ELO: {gs['user_data'].get('elo', DEFAULT_ELO)} 📊",
                        size=13, color=ft.Colors.WHITE54,
                        text_align=ft.TextAlign.CENTER),
                ft.Divider(color="#44446a"),
                support_card(),
                ft.Divider(color="#44446a"),
                ft.Row([
                    ft.ElevatedButton(
                        "Play Again", icon=ft.Icons.REPLAY,
                        on_click=lambda e: page.run_task(rematch, e),
                        style=ft.ButtonStyle(
                            shape=ft.RoundedRectangleBorder(radius=10),
                            bgcolor=ft.Colors.PURPLE_700, color=ft.Colors.WHITE
                        )
                    ),
                    ft.ElevatedButton(
                        "Menu", icon=ft.Icons.HOME,
                        on_click=lambda e: page.run_task(go_menu, e),
                        style=ft.ButtonStyle(
                            shape=ft.RoundedRectangleBorder(radius=10),
                            bgcolor=ft.Colors.GREY_700, color=ft.Colors.WHITE
                        )
                    ),
                ], alignment=ft.MainAxisAlignment.CENTER, spacing=12)
            ], spacing=10, horizontal_alignment=ft.CrossAxisAlignment.CENTER,
               tight=True, scroll=ft.ScrollMode.AUTO),
            actions=[]
        )
        page.open(dialog)
        page.update()

    # ─────────────────────────────────────────
    # VIEWS — all return ft.View objects
    # ─────────────────────────────────────────

    # ── LOGIN VIEW ────────────────────────────
    def login_view():
        email_f    = ft.TextField(
            label="Email", width=300, bgcolor="#2d2d44",
            border_radius=10, color=ft.Colors.WHITE,
            label_style=ft.TextStyle(color=ft.Colors.WHITE54)
        )
        password_f = ft.TextField(
            label="Password", password=True, can_reveal_password=True,
            width=300, bgcolor="#2d2d44", border_radius=10,
            color=ft.Colors.WHITE,
            label_style=ft.TextStyle(color=ft.Colors.WHITE54)
        )
        loading = ft.ProgressRing(visible=False, width=24, height=24)

        async def do_auth(signup):
            if not email_f.value or not password_f.value:
                snack("Enter email and password", ft.Colors.RED_700)
                return
            loading.visible = True
            page.update()
            try:
                user = await fb_auth(email_f.value, password_f.value, signup=signup)
                if "error" in user:
                    snack(user["error"].get("message", "Auth failed"), ft.Colors.RED_700)
                else:
                    gs["user"] = user
                    await init_user(user["localId"], email_f.value)
                    page.go("/menu")
            except Exception as ex:
                snack(str(ex), ft.Colors.RED_700)
            loading.visible = False
            page.update()

        async def offline_play(e):
            if load_offline() and gs["user_data"]:
                page.go("/menu")
            else:
                gs["user"] = {"localId": "offline", "idToken": ""}
                gs["user_data"] = {
                    "email": "Offline Player", "display_name": "Player",
                    "coins": 500, "wins": 0, "losses": 0, "games": 0,
                    "elo": DEFAULT_ELO, "tournament_wins": 0,
                    "skins": {"board": "classic", "dice": "default"},
                    "ads": {"date": "", "count": 0}, "achievements": []
                }
                page.go("/menu")

        return ft.View(
            "/",
            controls=[
                ft.Container(
                    expand=True,
                    bgcolor="#1a1a2e",
                    padding=24,
                    content=ft.Column(
                        controls=[
                            ft.Container(height=40),
                            ft.Text("🎲", size=64, text_align=ft.TextAlign.CENTER),
                            ft.Text(
                                "Ludo Pro Max", size=32,
                                weight=ft.FontWeight.BOLD,
                                color=ft.Colors.WHITE,
                                text_align=ft.TextAlign.CENTER
                            ),
                            ft.Text(
                                f"v{APP_VERSION}", size=12,
                                color=ft.Colors.WHITE38,
                                text_align=ft.TextAlign.CENTER
                            ),
                            ft.Container(height=24),
                            email_f,
                            password_f,
                            ft.Container(height=8),
                            loading,
                            primary_btn(
                                "Login",
                                lambda e: page.run_task(do_auth, False),
                                icon=ft.Icons.LOGIN
                            ),
                            primary_btn(
                                "Create Account",
                                lambda e: page.run_task(do_auth, True),
                                icon=ft.Icons.PERSON_ADD,
                                color=ft.Colors.INDIGO_700
                            ),
                            ft.TextButton(
                                "Play Offline",
                                on_click=lambda e: page.run_task(offline_play, e),
                                style=ft.ButtonStyle(color=ft.Colors.WHITE54)
                            ),
                        ],
                        horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                        alignment=ft.MainAxisAlignment.START,
                        spacing=12,
                        scroll=ft.ScrollMode.AUTO,
                    )
                )
            ],
            bgcolor="#1a1a2e",
            padding=0,
        )

    # ── MENU VIEW ─────────────────────────────
    def menu_view():
        ud = gs["user_data"] or {}

        async def go_bot(diff, two=False):
            setup_game(4, "bot", diff, two_dice=two)
            page.go("/game")

        async def go_local(n):
            setup_game(n, "local", two_dice=False)
            page.go("/game")

        async def go_online(e):
            if not gs["user"] or gs["user"]["localId"] == "offline":
                snack("Login to play online", ft.Colors.RED_700)
                return
            page.go("/lobby")

        async def go_tournament(e):
            if not gs["user"] or gs["user"]["localId"] == "offline":
                snack("Login to join tournaments", ft.Colors.RED_700)
                return
            page.go("/tournament")

        async def go_leaderboard(e):
            page.go("/leaderboard")

        return ft.View(
            "/menu",
            controls=[
                header("Ludo Pro Max"),
                ft.Container(
                    expand=True,
                    bgcolor="#1a1a2e",
                    padding=16,
                    content=ft.Column(
                        controls=[
                            ft.Container(
                                ft.Row([
                                    ft.CircleAvatar(
                                        content=ft.Text(
                                            ud.get("display_name", "P")[0].upper(),
                                            size=20, weight=ft.FontWeight.BOLD,
                                            color=ft.Colors.WHITE
                                        ),
                                        bgcolor=ft.Colors.PURPLE_700, radius=26
                                    ),
                                    ft.Column([
                                        ft.Text(
                                            ud.get("display_name", "Player"),
                                            size=15, weight=ft.FontWeight.BOLD,
                                            color=ft.Colors.WHITE
                                        ),
                                        ft.Text(
                                            f"🪙 {ud.get('coins', 0)}  |  "
                                            f"🏆 {ud.get('wins', 0)} wins  |  "
                                            f"📊 ELO {ud.get('elo', DEFAULT_ELO)}",
                                            size=11, color=ft.Colors.WHITE70
                                        )
                                    ], spacing=2, expand=True)
                                ], spacing=12),
                                bgcolor="#2d2d44", padding=14, border_radius=12
                            ),
                            ft.Divider(color="#44446a"),
                            ft.Text("🤖 VS AI", size=14, weight=ft.FontWeight.BOLD,
                                    color=ft.Colors.WHITE70),
                            primary_btn("Easy Bot 😊",
                                        lambda e: page.run_task(go_bot, "easy"),
                                        color=ft.Colors.GREEN_700),
                            primary_btn("Hard Bot 😤",
                                        lambda e: page.run_task(go_bot, "hard"),
                                        color=ft.Colors.ORANGE_700),
                            primary_btn("Hardest Bot 💀",
                                        lambda e: page.run_task(go_bot, "hardest"),
                                        color=ft.Colors.RED_700),
                            primary_btn("2-Dice vs Bot 🎲🎲",
                                        lambda e: page.run_task(go_bot, "hard", True),
                                        color=ft.Colors.DEEP_PURPLE_700),
                            ft.Divider(color="#44446a"),
                            ft.Text("👥 Local Play", size=14, weight=ft.FontWeight.BOLD,
                                    color=ft.Colors.WHITE70),
                            ft.Row([
                                primary_btn("2P", lambda e: page.run_task(go_local, 2),
                                            width=90, color=ft.Colors.BLUE_700),
                                primary_btn("3P", lambda e: page.run_task(go_local, 3),
                                            width=90, color=ft.Colors.TEAL_700),
                                primary_btn("4P", lambda e: page.run_task(go_local, 4),
                                            width=90, color=ft.Colors.INDIGO_700),
                            ], alignment=ft.MainAxisAlignment.CENTER, spacing=8),
                            ft.Divider(color="#44446a"),
                            ft.Text("🌐 Online", size=14, weight=ft.FontWeight.BOLD,
                                    color=ft.Colors.WHITE70),
                            primary_btn("Online Multiplayer 🌍", go_online,
                                        icon=ft.Icons.WIFI, color=ft.Colors.CYAN_700),
                            primary_btn("Tournaments 🏆", go_tournament,
                                        icon=ft.Icons.EMOJI_EVENTS, color=ft.Colors.AMBER_700),
                            primary_btn("Leaderboard 📊", go_leaderboard,
                                        icon=ft.Icons.LEADERBOARD, color=ft.Colors.PINK_700),
                            ft.Divider(color="#44446a"),
                            support_card(),
                            ft.TextButton(
                                "Logout",
                                on_click=lambda e: page.go("/"),
                                style=ft.ButtonStyle(color=ft.Colors.WHITE38)
                            )
                        ],
                        horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                        spacing=10,
                        scroll=ft.ScrollMode.AUTO,
                    )
                )
            ],
            bgcolor="#1a1a2e",
            padding=0,
        )

    # ── LOBBY VIEW ────────────────────────────
    def lobby_view():
        code_field = ft.TextField(
            label="Enter Room Code", width=200, bgcolor="#2d2d44",
            border_radius=10, color=ft.Colors.WHITE,
            text_align=ft.TextAlign.CENTER,
            label_style=ft.TextStyle(color=ft.Colors.WHITE54)
        )
        result_text = ft.Text("", color=ft.Colors.WHITE70, size=13)

        async def do_create(two_dice=False):
            code = await create_room(two_dice=two_dice)
            result_text.value = f"Room created! Code: {code}"
            page.update()
            page.go("/game")

        async def do_join(e):
            code = code_field.value.strip()
            if not code:
                snack("Enter room code", ft.Colors.RED_700)
                return
            ok, msg = await join_room(code)
            if ok:
                page.go("/game")
            else:
                snack(msg, ft.Colors.RED_700)

        return ft.View(
            "/lobby",
            controls=[
                header("Online Lobby"),
                ft.Container(
                    expand=True,
                    bgcolor="#1a1a2e",
                    padding=20,
                    content=ft.Column(
                        controls=[
                            ft.Text(
                                "Create a new room and share the code with friends",
                                size=13, color=ft.Colors.WHITE70,
                                text_align=ft.TextAlign.CENTER
                            ),
                            primary_btn(
                                "Create Room (1 Dice)",
                                lambda e: page.run_task(do_create, False),
                                icon=ft.Icons.ADD_CIRCLE, color=ft.Colors.GREEN_700
                            ),
                            primary_btn(
                                "Create Room (2 Dice 🎲🎲)",
                                lambda e: page.run_task(do_create, True),
                                icon=ft.Icons.ADD_CIRCLE, color=ft.Colors.DEEP_PURPLE_700
                            ),
                            ft.Divider(color="#44446a"),
                            ft.Text("Or join an existing room", size=13,
                                    color=ft.Colors.WHITE70),
                            ft.Row([
                                code_field,
                                ft.ElevatedButton(
                                    "Join", on_click=do_join,
                                    style=ft.ButtonStyle(
                                        shape=ft.RoundedRectangleBorder(radius=10),
                                        bgcolor=ft.Colors.BLUE_700, color=ft.Colors.WHITE
                                    )
                                )
                            ], alignment=ft.MainAxisAlignment.CENTER, spacing=8),
                            result_text,
                            ft.Divider(color="#44446a"),
                            primary_btn(
                                "← Back",
                                lambda e: page.go("/menu"),
                                color=ft.Colors.GREY_700
                            )
                        ],
                        horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                        spacing=12,
                        scroll=ft.ScrollMode.AUTO,
                    )
                )
            ],
            bgcolor="#1a1a2e",
            padding=0,
        )

    # ── GAME VIEW ─────────────────────────────
    def game_view():
        roll_btn.on_click = lambda e: page.run_task(roll_dice, e)
        page.run_task(play_bgm)

        emote_row.controls.clear()
        for em in EMOTES:
            emote_row.controls.append(
                ft.ElevatedButton(
                    em,
                    on_click=lambda e, em=em: page.run_task(send_emote, em),
                    style=ft.ButtonStyle(
                        shape=ft.RoundedRectangleBorder(radius=8),
                        bgcolor="#2d2d44", color=ft.Colors.WHITE,
                        padding=ft.Padding(left=6, right=6, top=6, bottom=6)
                    )
                )
            )

        dice_row = ft.Row(
            [dice1_text] + ([dice2_text] if gs["two_dice_mode"] else []),
            alignment=ft.MainAxisAlignment.CENTER, spacing=8
        )

        chat_ui = ft.Column([
            ft.Text("💬 Chat", size=12, weight=ft.FontWeight.BOLD,
                    color=ft.Colors.WHITE70),
            chat_list,
            ft.Row([
                chat_field,
                ft.IconButton(
                    icon=ft.Icons.SEND,
                    icon_color=ft.Colors.PURPLE_300,
                    on_click=lambda e: page.run_task(send_chat, e)
                )
            ], spacing=6)
        ], spacing=4) if gs["is_online"] else ft.Container()

        async def back_to_menu(e):
            gs["stop_poll"] = True
            gs["game_started"] = False
            await stop_bgm()
            page.go("/menu")

        return ft.View(
            "/game",
            controls=[
                ft.Container(
                    expand=True,
                    bgcolor="#1a1a2e",
                    content=ft.Column(
                        controls=[
                            ft.Container(
                                ft.Row([
                                    ft.IconButton(
                                        icon=ft.Icons.ARROW_BACK,
                                        icon_color=ft.Colors.WHITE,
                                        on_click=lambda e: page.run_task(back_to_menu, e)
                                    ),
                                    status_bar,
                                    ft.Row([
                                        ft.IconButton(
                                            icon=ft.Icons.VOLUME_UP,
                                            icon_color=ft.Colors.WHITE,
                                            tooltip="Toggle Sound FX",
                                            on_click=lambda e: (
                                                toggle_sound(),
                                                page.update()
                                            )
                                        ),
                                        ft.IconButton(
                                            icon=ft.Icons.MUSIC_NOTE,
                                            icon_color=ft.Colors.WHITE,
                                            tooltip="Toggle Music",
                                            on_click=lambda e: (
                                                toggle_music(),
                                                page.update()
                                            )
                                        ),
                                    ], spacing=0)
                                ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
                                bgcolor="#12122a",
                                padding=ft.Padding(left=8, right=8, top=6, bottom=6)
                            ),
                            player_strip,
                            ft.Container(
                                board_col,
                                alignment=ft.alignment.center,
                                padding=ft.Padding(left=2, right=2, top=0, bottom=0)
                            ),
                            ft.Container(
                                ft.Row([
                                    dice_row,
                                    roll_btn
                                ], alignment=ft.MainAxisAlignment.SPACE_AROUND, spacing=12),
                                bgcolor="#12122a", padding=10, border_radius=12
                            ),
                            ft.Container(
                                ft.Column([
                                    ft.Text("😄 Emotes", size=11, color=ft.Colors.WHITE54),
                                    emote_row
                                ], spacing=4),
                                padding=ft.Padding(left=8, right=8, top=0, bottom=0)
                            ),
                            chat_ui,
                            support_card(),
                        ],
                        spacing=8,
                        scroll=ft.ScrollMode.AUTO,
                    )
                )
            ],
            bgcolor="#1a1a2e",
            padding=0,
        )

    # ── TOURNAMENT VIEW ───────────────────────
    def tournament_view():
        t_list  = ft.ListView(expand=True, spacing=6, height=400)
        loading = ft.ProgressRing(visible=True, width=28, height=28)

        async def load_tournaments():
            try:
                data = await fb_get("tournaments", gs["user"]["idToken"])
                loading.visible = False
                t_list.controls.clear()
                if not data:
                    t_list.controls.append(
                        ft.Text("No active tournaments", color=ft.Colors.WHITE54,
                                text_align=ft.TextAlign.CENTER)
                    )
                else:
                    for tid, t in data.items():
                        players_count = len(t.get("players", {}))
                        t_list.controls.append(
                            ft.Container(
                                ft.Row([
                                    ft.Column([
                                        ft.Text(t.get("name", "Tournament"),
                                                size=14, weight=ft.FontWeight.BOLD,
                                                color=ft.Colors.WHITE),
                                        ft.Text(
                                            f"👥 {players_count}/8 players  |  "
                                            f"🏆 Prize: {t.get('prize_coins', 500)} coins",
                                            size=11, color=ft.Colors.WHITE70
                                        )
                                    ], expand=True, spacing=2),
                                    ft.ElevatedButton(
                                        "Join",
                                        on_click=lambda e, tid=tid: page.run_task(join_tournament, tid),
                                        style=ft.ButtonStyle(
                                            shape=ft.RoundedRectangleBorder(radius=8),
                                            bgcolor=ft.Colors.AMBER_700, color=ft.Colors.WHITE
                                        )
                                    )
                                ]),
                                bgcolor="#2d2d44", padding=12, border_radius=10
                            )
                        )
                page.update()
            except Exception as ex:
                loading.visible = False
                snack(str(ex), ft.Colors.RED_700)
                page.update()

        async def join_tournament(tid):
            try:
                uid = gs["user"]["localId"]
                await fb_patch(f"tournaments/{tid}/players/{uid}", {
                    "email": gs["user_data"]["email"],
                    "elo": gs["user_data"].get("elo", DEFAULT_ELO)
                }, gs["user"]["idToken"])
                snack("Joined tournament! 🏆", ft.Colors.GREEN_700)
            except Exception as ex:
                snack(str(ex), ft.Colors.RED_700)

        async def create_tournament(e):
            name = f"Tournament {random.randint(100, 999)}"
            tid  = f"t_{int(time.time())}"
            try:
                await fb_put(f"tournaments/{tid}", {
                    "name": name, "created_by": gs["user"]["localId"],
                    "prize_coins": 500, "state": "open",
                    "players": {gs["user"]["localId"]: {
                        "email": gs["user_data"]["email"],
                        "elo": gs["user_data"].get("elo", DEFAULT_ELO)
                    }},
                    "created_at": int(time.time())
                }, gs["user"]["idToken"])
                snack(f"Tournament '{name}' created! 🎉", ft.Colors.GREEN_700)
                await load_tournaments()
            except Exception as ex:
                snack(str(ex), ft.Colors.RED_700)

        page.run_task(load_tournaments)

        return ft.View(
            "/tournament",
            controls=[
                header("Tournaments 🏆"),
                ft.Container(
                    expand=True,
                    bgcolor="#1a1a2e",
                    padding=16,
                    content=ft.Column(
                        controls=[
                            primary_btn(
                                "+ Create Tournament", create_tournament,
                                icon=ft.Icons.ADD, color=ft.Colors.AMBER_700
                            ),
                            ft.Divider(color="#44446a"),
                            loading,
                            t_list,
                            primary_btn(
                                "← Back",
                                lambda e: page.go("/menu"),
                                color=ft.Colors.GREY_700
                            )
                        ],
                        spacing=10,
                        horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                        scroll=ft.ScrollMode.AUTO,
                    )
                )
            ],
            bgcolor="#1a1a2e",
            padding=0,
        )

    # ── LEADERBOARD VIEW ─────────────────────
    def leaderboard_view():
        lb_list = ft.ListView(expand=True, spacing=6, height=500)
        loading = ft.ProgressRing(visible=True, width=28, height=28)

        async def load_lb():
            try:
                data = await fb_get("users", gs["user"]["idToken"])
                loading.visible = False
                lb_list.controls.clear()
                if not data:
                    lb_list.controls.append(
                        ft.Text("No data yet", color=ft.Colors.WHITE54)
                    )
                else:
                    ranked = sorted(
                        [(uid, u) for uid, u in data.items() if isinstance(u, dict)],
                        key=lambda x: x[1].get("elo", DEFAULT_ELO), reverse=True
                    )[:20]
                    medals = ["🥇", "🥈", "🥉"] + ["🎖️"] * 17
                    for i, (uid, u) in enumerate(ranked):
                        is_me = gs["user"] and uid == gs["user"].get("localId")
                        lb_list.controls.append(
                            ft.Container(
                                ft.Row([
                                    ft.Text(medals[i], size=20),
                                    ft.Column([
                                        ft.Text(
                                            u.get("display_name", u.get("email", "?"))[:20],
                                            size=13, weight=ft.FontWeight.BOLD,
                                            color=ft.Colors.WHITE
                                        ),
                                        ft.Text(
                                            f"ELO {u.get('elo', DEFAULT_ELO)}  |  "
                                            f"🏆 {u.get('wins', 0)} wins",
                                            size=11, color=ft.Colors.WHITE70
                                        )
                                    ], expand=True, spacing=2),
                                ], spacing=10),
                                bgcolor=ft.Colors.PURPLE_900 if is_me else "#2d2d44",
                                padding=10, border_radius=10,
                                border=ft.border.all(1, ft.Colors.PURPLE_400) if is_me else None
                            )
                        )
                page.update()
            except Exception as ex:
                loading.visible = False
                snack(str(ex), ft.Colors.RED_700)
                page.update()

        page.run_task(load_lb)

        return ft.View(
            "/leaderboard",
            controls=[
                header("Leaderboard 📊"),
                ft.Container(
                    expand=True,
                    bgcolor="#1a1a2e",
                    padding=16,
                    content=ft.Column(
                        controls=[
                            loading,
                            lb_list,
                            primary_btn(
                                "← Back",
                                lambda e: page.go("/leaderboard"),
                                color=ft.Colors.GREY_700
                            )
                        ],
                        spacing=10,
                        horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                        scroll=ft.ScrollMode.AUTO,
                    )
                )
            ],
            bgcolor="#1a1a2e",
            padding=0,
        )

    # ── ROUTER ───────────────────────────────
    def route_change(e):
        r = page.route
        page.views.clear()

        if r == "/" or not r:
            page.views.append(login_view())

        elif r == "/menu":
            if not gs["user"]:
                if not load_offline():
                    page.views.append(login_view())
                    page.update()
                    return
            page.views.append(menu_view())

        elif r == "/lobby":
            page.views.append(lobby_view())

        elif r == "/game":
            update_ui()
            page.views.append(game_view())
            if not gs["is_online"]:
                asyncio.ensure_future(maybe_bot_turn())

        elif r == "/tournament":
            page.views.append(tournament_view())

        elif r == "/leaderboard":
            page.views.append(leaderboard_view())

        else:
            page.views.append(login_view())

        page.update()

    def view_pop(e):
        if len(page.views) > 1:
            page.views.pop()
            top = page.views[-1]
            page.go(top.route)

    page.on_route_change = route_change
    page.on_view_pop     = view_pop
    page.go("/")


# ─────────────────────────────────────────────
# ENTRY POINT
# ─────────────────────────────────────────────
ft.app(target=main)
