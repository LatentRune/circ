"""Circ's network and data checks: two simulated clients, Alice and Bob, trading messages
through a stand-in for the game (mock.lua). Covers serializing, channel names, the bundled
recipe list, invites, record sync, prices, the trade ledger, takeover moves and bag sharing.

    python3 tools/tests/protocol.py          # the addon in src/
    python3 tools/tests/protocol.py DIR      # another copy of the addon
"""
import sys, os
from lupa import lua51
HERE = os.path.dirname(os.path.abspath(__file__))
B = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "..", "src")
files = [l.strip().replace("\\", "/") for l in open(os.path.join(B, "Circ.toc")) if l.strip().endswith(".lua")]

def client(name):
    L = lua51.LuaRuntime(unpack_returned_tuples=True)
    L.execute(open(os.path.join(HERE, "mock.lua")).read())
    L.execute(f'__me = "{name}"')
    L.execute("NS = {}")
    for f in files:
        L.execute(f'__load([[{os.path.join(B, f)}]], NS)')
    L.execute('__fire("ADDON_LOADED", "Circ"); CircDB.debug = true; __fire("PLAYER_LOGIN")')
    return L

A, Bc = client("Alice"), client("Bob")
clients = {"Alice-Realm": A, "Bob-Realm": Bc}

def deliver():
    moved = 0
    for sender, L in clients.items():
        out = L.eval("__outbox")
        msgs = [dict(out[i]) for i in range(1, len(out) + 1)]
        L.execute("__outbox = {}")
        for m in msgs:
            moved += 1
            for rname, R in clients.items():
                if rname == sender: continue
                if m["dist"] == "WHISPER" and not rname.startswith(m["target"].split("-")[0]): continue
                if m["dist"] == "CHANNEL" and R.eval("GetChannelName('CIRCTEST')") == 0 and not R.eval("NS.Union:ChannelID()"): continue
                fire = R.eval("function(t, d, s, ch) __fire('CHAT_MSG_ADDON', 'CIRC', t, d, s, '', 0, 5, ch) end")
                fire(m["text"], m["dist"], sender, R.eval("NS.Union:Name()") or "")
    return moved

def step(sec=5, rounds=40):
    for _ in range(rounds):
        for L in clients.values(): L.execute(f"__advance({sec})")
        deliver()

def check(cond, label):
    print(("PASS " if cond else "FAIL ") + label)
    if not cond: check.failed = True
check.failed = False

# Unit checks
check(A.eval('NS.Serialize.Decode(NS.Serialize.Encode({a="x:y", b={1,2,{c=true}}, n=1.5})).b[3].c') == True, "serializer round trip")
check(A.eval('NS:ParseMoney("1g20s5c")') == 12005 and A.eval('NS:ParseMoney("1.5")') == 15000 and A.eval('NS:ParseMoney("off")') == False, "money parsing")
s1 = A.eval('NS.Union.Successor("circQ7K2smith", 1)'); s1b = Bc.eval('NS.Union.Successor("CIRCQ7K2SMITH", 1)')
check(s1 == s1b and s1 != "circQ7K2smith" and s1.isalnum() and s1.startswith("circ") and s1.endswith("smith") and s1[4:8] == s1[4:8].upper() and len(s1) == 13, f"successor name is deterministic, circ + ID + name ({s1})")
check(A.eval('NS.Union.Normalize("CIRC_1234_SMITH")') == "circ1234smith", "old channel names drop the underscores")
check(A.eval('NS.Union.Normalize("CIRCAAAASTART")') == "circ0000start", "any starter spelling becomes circ0000start")
check(A.eval('NS.Union.Same("CIRCQ7K2SMITH", "circq7k2smith")') == True, "channel names compare regardless of case")
check(A.eval('NS.From36(NS.To36(123456))') == 123456, "base36")

# Bundled recipe database works before any scan
check(A.eval('NS.Recipes:Get(2387).p') == 2570 and A.eval('NS.Recipes:Get(2387).r[2996]') == 1, "bundled: Linen Cloak definition")
check(A.eval('NS.Recipes:Get(3920).c') == 200, "bundled: Crafted Light Shot makes 200")
check(A.eval('NS.Recipes:Get(13890).prof') == "Enchanting" and A.eval('NS.Recipes:Get(13890).p') == 0, "bundled: enchant with no product")
check(A.eval('NS.Recipes.usedIn[2589][2963]') == True, "bundled: Linen Cloth indexed as Bolt reagent")
check(A.eval('NS.Recipes.madeBy[12360][17187]') == True, "bundled: Arcanite Bar made by transmute")
check(A.eval('NS.Lookup:Resolve("arcanite bar")') == 12360, "resolve name from bundled item names")
cnt = A.eval('(NS.Recipes:Count())')
check(cnt > 1500, f"bundled recipe count ({cnt})")
check(A.eval('NS.Recipes:Get(990001)') is None, "unbundled recipe unknown before scan")

# Alice scans Tailoring, creates union; Bob joins
A.execute('__fire("TRADE_SKILL_SHOW")'); step(1, 5)
check(A.eval('#NS:CharDB().professions.Tailoring.recipes') == 3, "scan found 3 recipes")
check(A.eval('NS.Union:Bind("CIRC_TEST_XXXXX")') == False, "invalid union name rejected")
step(5, 3)
check(A.eval('NS.Union:Name()') == "circ0000start", "new user auto-joins the starter union")
v = lambda t: A.eval(f'(select(2, NS.Union.Validate("{t}")))')
check(v("SMI") == "Exactly 5 letters (3 so far)", "validation: length")
check(v("SM1TH") == "Letters only", "validation: letters only")
check(v("start") == "START is the starter ledger", "validation: START reserved")
check(A.eval('NS.Union.Validate(" smith ")') == "SMITH", "validation: cleaned to SMITH")
A.execute('NS.Union:Create("smith")')
check("starter ledger" in A.eval('__popup[2]') and A.eval('__popup[3]') == "START (starter ledger)", "create warns about leaving START")
A.execute('StaticPopupDialogs.CIRC_SWITCH.OnAccept(nil, __popup[4])')
UNION = A.eval('NS.Union:Name()')
check(UNION.startswith("circ") and UNION.endswith("smith") and UNION.isalnum() and A.eval('NS.Union:DisplayName()') == "SMITH", f"hidden channel {UNION}, shown as SMITH")
step(5, 3)
A.execute('__printed = {}; NS.Union:Invite("Alice")')
check(any("can't invite yourself" in str(m) for m in A.eval("__printed").values()), "self-invite explained")
A.execute('NS.Union:Invite("Bob")'); step(1, 5)
check(any("Bob got your invite" in str(m) for m in A.eval("__printed").values()), "inviter told the invite arrived")
check(Bc.eval('__popup[1]') == "CIRC_INVITE" and Bc.eval('__popup[3]') == "SMITH" and "START" in Bc.eval('__popup[4]'), "Bob gets invite showing SMITH and START warning")
Bc.execute('StaticPopupDialogs.CIRC_INVITE.OnAccept(__dialog, __popup[5])')
check(Bc.eval('NS.Union:Name()') == UNION, "Bob joined via invite")
step(1, 5)
check(any("Bob joined your ledger" in str(m) for m in A.eval("__printed").values()), "inviter told Bob joined")
step(5, 30)
check(Bc.eval('NS.Records:Get("Alice-Realm") ~= nil'), "Bob received Alice's record")
check(Bc.eval('NS.Recipes:Get(990001) ~= nil'), "Bob learned an unbundled recipe definition from Alice")
rows = Bc.eval('NS.Lookup:UsedIn(2589)')
check(len(rows) >= 1 and rows[1].player == "Alice-Realm", "lookup: Linen Cloth used by Alice")
check(rows[1].price == 40, f"reagent offer = 80% of market (got {rows[1].price})")
made = Bc.eval('NS.Lookup:MadeBy(2570)')
check(len(made) == 1 and made[1].price == 198, f"finished good = (150+30)*1.1 (got {made[1].price if len(made) else None})")

# Overrides and wants propagate
A.execute('SlashCmdList.CIRC("sell Linen Cloak 5s")'); A.execute('SlashCmdList.CIRC("want Coarse Thread 20 25c")')
step(5, 30)
made = Bc.eval('NS.Lookup:MadeBy(2570)')
check(made[1].price == 500, f"sell override reached Bob (got {made[1].price})")
used = Bc.eval('NS.Lookup:UsedIn(2320)')
kinds = sorted(used[i].kind for i in range(1, len(used) + 1))
check("wants" in kinds, "buy order visible to Bob")

# Ledger: Bob pays Alice 5s for 20 linen; both report
A.execute('__tradePartner = "Bob"; __tradeMoney = {me=0, them=500}; __tradeTargetItem = nil')
Bc.execute('__tradePartner = "Alice"; __tradeMoney = {me=500, them=0}; __tradeTargetItem = nil')
for L in (A, Bc):
    L.execute('__fire("TRADE_SHOW"); __fire("TRADE_ACCEPT_UPDATE", 1, 1); __fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE)')
step(5, 10)
for nm, L in (("Alice", A), ("Bob", Bc)):
    lst = L.eval('NS.Ledger:Sorted()')
    check(len(lst) == 1 and lst[1].confirmed == True, f"{nm}'s ledger has 1 confirmed trade")
check(A.eval('select(2, NS.Ledger:Totals(7))') == 500, "circulation total = 5s")

# Third-party forged ledger report is rejected
Bc.execute("NS:Fire('Msg:LEDG', {a='Alice-Realm', b='Carol-Realm', ma=1, mb=0, ia='', ib='', t=time()}, 'Bob-Realm')")
check(Bc.eval('#NS.Ledger:Sorted()') == 1, "ledger rejects report from a non-party")

# Protection: password set triggers popup; accepting moves to successor
Bc.execute(f"__fire('CHAT_MSG_CHANNEL_NOTICE_USER', 'PASSWORD_CHANGED', 'Griefer', '', '5. {UNION}', '', '', 0, 5, '{UNION}')")
check(Bc.eval('__popup and __popup[1]') == "CIRC_TAKEOVER", "takeover popup shown")
Bc.execute('StaticPopupDialogs.CIRC_TAKEOVER.OnAccept()')
check(Bc.eval('NS.Union:Name()') == A.eval(f'NS.Union.Successor("{UNION}", 1)'), "moved to successor channel")
check(Bc.eval('NS.Records:Get("Alice-Realm") ~= nil') and Bc.eval('#NS.Ledger:Sorted()') == 1, "records and ledger kept after move")

# After two takeovers in a day Circ only explains; once the day has passed it asks again
NEXT = Bc.eval('NS.Union:Name()')
takeover = f"__fire('CHAT_MSG_CHANNEL_NOTICE_USER', 'PASSWORD_CHANGED', 'Griefer', '', '5. {NEXT}', '', '', 0, 5, '{NEXT}')"
Bc.execute('CircDB.union.takeovers = { time() - 100, time() - 50 }; __popup = nil')
Bc.execute(takeover)
check(Bc.eval('__popup') is None, "no move offered after two takeovers in a day")
Bc.execute('__advance(86400)')
Bc.execute(takeover)
check(Bc.eval('__popup and __popup[1]') == "CIRC_TAKEOVER", "takeover popup offered again a day later")
Bc.execute('StaticPopupDialogs.CIRC_TAKEOVER.OnCancel(); __popup = nil')

# Other CIRC_ channels ignored once bound
A.execute("__fire('CHAT_MSG_CHANNEL_NOTICE', 'YOU_JOINED', '', '', '6. circZZZZother', '', '', 0, 6, 'circZZZZother')")
check(A.eval('NS.Union:Name()') == UNION, "second CIRC_ channel ignored")

# Large record chunks under 255 bytes (assert in mock) and reassembles
big = "{" + ",".join(f"[{i}]=true" for i in range(5000, 5400)) + "}"
A.execute(f"NS.Comm:Send('TEST', {big}, 'UNION')")
got = []
Bc.eval("function(f) NS:Listen('Msg:TEST', function(d) f(d) end) end")(lambda d: got.append(d))
Bc.execute(f"NS.Union:Bind('{UNION}')")
step(2, 60)
check(len(got) == 1, "multi-chunk message reassembled")

# Carol arrives while Alice is offline: Bob relays Alice's record
C = client("Carol"); clients["Carol-Realm"] = C
del clients["Alice-Realm"]
step(5, 3)
Bc.execute('NS.Union:Invite("Carol")'); step(1, 5)
C.execute('StaticPopupDialogs.CIRC_INVITE.OnAccept(__dialog, __popup[5])')
step(5, 40)
check(C.eval('NS.Records:Get("Alice-Realm") ~= nil and NS.Records:Get("Alice-Realm").relayed'), "offline member's record relayed to newcomer")
check(C.eval('#NS.Lookup:MadeBy(2570)') == 1, "newcomer can look up offline crafter")
check(C.eval('NS.Recipes:Get(990001) ~= nil'), "newcomer got unbundled recipe definition via relay")
C.execute('NS.Union:Leave()'); step(5, 2)
check(C.eval('NS.Union:Name()') == "circ0000start", "leaving a union returns to START")
check(C.eval('NS.Records:Get("Alice-Realm") == nil'), "START has its own member list")
C.execute('NS.Union:Leave()')
check(C.eval('NS.Union:IsStart()') == True, "leaving START keeps you in START")
clients["Alice-Realm"] = A

print("ERRORS:", [m for L in clients.values() for m in L.eval("__printed").values() if "error" in str(m)])


# UI and misc smoke test
for L in (A, Bc):
    L.execute('''
      FauxScrollFrame_Update = function() end
      FauxScrollFrame_GetOffset = function() return 0 end
      C_Container = { GetContainerNumSlots = function(b) return b == 0 and 2 or 0 end, GetContainerItemID = function(b, s) return s == 1 and 2589 or 2320 end }
    ''')
    for tab in ["lookup", "requests", "ledger", "prices", "settings"]:
        L.execute(f'NS.UI:Show("{tab}")')
        L.execute('local f = CircFrame; f.IsShown = function() return true end; NS.UI:Refresh()')
    L.execute('NS.UI:LookupItem("Linen"); SlashCmdList.CIRC("shop Linen Cloak 2"); SlashCmdList.CIRC("status"); SlashCmdList.CIRC("help"); SlashCmdList.CIRC("find Linen Cloth")')
Bc.execute('__fire("MERCHANT_SHOW")')
print("\n".join(str(m) for m in list(Bc.eval("__printed").values())[-8:]))
print("ERRORS2:", [m for L in clients.values() for m in L.eval("__printed").values() if "error" in str(m)])
Bc.execute('__printed = {}; SlashCmdList.CIRC("shop Linen Cloak 2")')
print("\n".join(str(m) for m in Bc.eval("__printed").values()))
leaks = [m for L in (A, Bc, C) for m in L.eval("__printed").values() if __import__("re").search(r"(?i)circ_|circ[a-z0-9]{4}[a-z]{5}", str(m))]
print("CHANNEL NAME LEAKS:", leaks)

# Autocomplete, player lookup, shift-click insert, manual /leave
sug = Bc.eval('NS.Lookup:Suggest("linen", 8)')
labels = [sug[i].label for i in range(1, len(sug) + 1)]
check("Linen Cloth" in labels and all("linen" in l.lower() for l in labels), f"item autocomplete ({labels[:4]})")
sug = Bc.eval('NS.Lookup:Suggest("al", 8)')
check(sug[1].kind == "player" and sug[1].label == "Alice", "member autocomplete ranks Alice first")
prof = Bc.eval('NS.Lookup:Profile("Alice-Realm")')
kinds = set(prof[i].kind for i in range(1, len(prof) + 1))
check({"makes", "buys", "wants"} <= kinds, "player profile lists makes, buys and wants")
Bc.execute('NS.UI:Show("lookup"); CircFrame.IsShown = function() return true end; NS.UI:LookupPlayer("Alice-Realm")')
Bc.execute('ChatEdit_InsertLink("|cffffffff|Hitem:2589::|h[Linen Cloth]|h|r")')
check(Bc.eval('CircSearchBox:GetText()') == "Linen Cloth", "shift-click puts the item name in the search box")
check(Bc.eval('#NS.Lookup:UsedIn(2589)') >= 1, "shift-clicked item is looked up")
Bc.execute(f"__fire('CHAT_MSG_CHANNEL_NOTICE', 'YOU_LEFT', '', '', '5. {Bc.eval('NS.Union:Name()')}', '', '', 0, 5, '{Bc.eval('NS.Union:Name()')}')")
Bc.execute("__channels[NS.Union:Name()] = nil")
step(1, 3)
check(Bc.eval('NS.Union:IsStart()') == True, "manual /leave of the union channel returns to START")
print("ERRORS3:", [m for L in (A, Bc) for m in L.eval("__printed").values() if "error" in str(m)])

# My prices tab: settings rows and per-item editing
A.execute('NS.UI:Show("prices"); CircFrame.IsShown = function() return true end; NS.UI:Refresh()')
data = A.eval('NS.UI.data')
rowsl = [data[i] for i in range(1, len(data) + 1)]
sells = [r for r in rowsl if r.money]
prices = [r.money.copper for r in sells]
first_sell = prices[:sum(1 for r in rowsl[:rowsl.index(next(r for r in rowsl if r.header and "Materials" in str(r.left)))] if r.money)]
check(first_sell == sorted(first_sell, reverse=True) and len(first_sell) >= 2, f"crafts sorted by price, highest first ({first_sell})")
edit = [r for r in rowsl if r.money and "Bolt of Linen" in (r.left or "")]
check(len(edit) == 2 and edit[0].money.gray == True, "Bolt of Linen Cloth has gold/silver/copper boxes (gray = auto) as product and reagent")
edit[0].money.fn(200)
check(A.eval('CircDB.overrides.sell[2996]') == 200, "typing a price saves the override")
A.execute('NS.UI:Refresh()')
data = A.eval('NS.UI.data'); rowsl = [data[i] for i in range(1, len(data) + 1)]
check(not any(r.action for r in rowsl if r.money), "no Reset/Clear buttons on prices")
order1 = [str(r.left) for r in rowsl if r.money]
edit = [r for r in rowsl if r.money and "Bolt of Linen" in (r.left or "")]
edit[0].money.fn(0)
check(A.eval('CircDB.overrides.sell[2996]') is None, "bringing a price to zero clears it")
edit[0].money.fn(99999)
A.execute('NS.UI:Refresh()')
data = A.eval('NS.UI.data'); order2 = [str(data[i].left) for i in range(1, len(data) + 1) if data[i].money]
check(order1 == order2, "row order stays put while editing")
edit[0].money.fn(0)
# Wheel on a box steps by 1
A.execute('''
  local m = NS.MoneyInput.Money(CreateFrame("Frame"), function(c) __wheel = c end)
  m:SetCopper(10203)
  m.boxes[2].scripts.OnMouseWheel(m.boxes[2], 1)
  m.boxes[3].scripts.OnMouseWheel(m.boxes[3], -1)
''')
check(A.eval('__wheel') == 10302, "mouse wheel steps silver up and copper down by 1")
A.execute('NS.UI:Show("settings"); NS.UI:Refresh()')
data = A.eval('NS.UI.data'); rowsl = [data[i] for i in range(1, len(data) + 1)]
pct = [r for r in rowsl if "Materials: 80%" in (r.left or "")][0]
pct.action.fn(); A.execute('__popup[4].save("70")')
check(A.eval('CircDB.settings.buyPct') == 70, "reagent percentage editable from Settings")
mm = [r for r in rowsl if "Minimap button" in (r.left or "")][0]
mm.check.fn(False)
check(A.eval('CircDB.settings.minimap') == False, "minimap button can be turned off")
# Client without recipe links (Classic Era): recipes matched by item made, and I see myself
D = client("Dana")
D.execute('''
  GetTradeSkillRecipeLink = nil
  FauxScrollFrame_Update = function() end
  FauxScrollFrame_GetOffset = function() return 0 end
  __trade = { { name = "Alchemy", kind = "header" },
    { name = "Elixir of Firepower", kind = "easy", product = 6373, reagents = { { 3356, 1 }, { 3372, 1 }, { 6371, 2 } } } }
  GetTradeSkillLine = function() return "Alchemy", 120, 150 end
  __fire("TRADE_SKILL_SHOW")
''')
for L in (D,): L.execute("__advance(10)")
check(D.eval('#NS:CharDB().professions.Alchemy.recipes') == 1, "recipe recognized without a recipe link")
D.execute('NS.Union:Create("TESTY"); StaticPopupDialogs.CIRC_SWITCH.OnAccept(nil, __popup[4]); __advance(10)')
used = D.eval('NS.Lookup:UsedIn(3356)')
check(len(used) >= 1 and used[1].player == "Dana-Realm", "I show up under Used in for Kingsblood after switching unions")
D.execute('NS.UI:Show("prices"); CircFrame.IsShown = function() return true end; NS.UI:Refresh()')
data = D.eval('NS.UI.data'); rowsl = [str(data[i].left) for i in range(1, len(data) + 1)]
check(any("Elixir of Firepower" in r or "6373" in r for r in rowsl) and any("3356" in r or "Kingsblood" in r for r in rowsl), "Prices tab lists the elixir and its reagents")
# Show-me setting, Requests tab, Prices filter, stack split
D.execute('CircDB.settings.showSelf = false')
check(len(D.eval('NS.Lookup:UsedIn(3356)')) == 0, "turning off 'Show me in lookups' hides me")
D.execute('CircDB.settings.showSelf = true')
D.execute('NS.UI:Show("requests"); NS.UI:Refresh()')
data = D.eval('NS.UI.data'); rq = [data[i] for i in range(1, len(data) + 1)]
req = [r for r in rq if r.action and r.action.label == "Request" and "3356" in str(r.left) or (r.action and r.action.label == "Request" and "Kingsblood" in str(r.left))]
check(len(req) == 1, "Requests tab offers Kingsblood from my recipes")
req[0].action.fn()
D.execute('CircRequestDialog.qty:SetValue(15); CircRequestDialog.price:SetCopper(1200); CircRequestDialog.ok.scripts.OnClick()')
check(D.eval('CircDB.wants[3356].qty') == 15 and D.eval('CircDB.wants[3356].price') == 1200, "request saved from the Requests tab")
D.execute('CircFilterBox:SetText("zzz"); CircFilterBox.scripts = CircFilterBox.scripts or {}')
D.execute('NS.UI:Show("prices")')
D.execute('CircFilterBox._text = "kings"')
D.execute('if CircFilterBox.scripts.OnTextChanged then CircFilterBox.scripts.OnTextChanged(CircFilterBox, true) end')
data = D.eval('NS.UI.data'); pr = [str(data[i].left) for i in range(1, len(data) + 1)]
check(any("Kingsblood" in r or "3356" in r for r in pr) and not any("6371" in r or "Stranglekelp" in r for r in pr), "Prices filter narrows the list")
# Lookup: Request button copies the item to Requests; clearing the box clears results
D.execute('NS.UI:LookupItem(3356)')
D.execute('NS.UI.modeButtons.request.scripts.OnClick()')
check(D.eval('CircFilterBox:GetText()') == "Kingsblood" and D.eval('NS.UI.data') is not None, "Lookup's Request button copies the item to the Requests tab")
D.execute('NS.UI:LookupItem(3356); CircSearchBox._text = ""; CircSearchBox.scripts.OnTextChanged(CircSearchBox, true)')
data = D.eval('NS.UI.data')
check(all(data[i].empty for i in range(1, len(data) + 1)), "clearing the search box clears the lookup")
print("ERRORS4:", [m for L in (A, Bc) for m in L.eval("__printed").values() if "error" in str(m)])
# Getting started list when nothing is looked up
D.execute('NS.UI:Show("lookup"); CircSearchBox._text = ""; CircSearchBox.scripts.OnTextChanged(CircSearchBox, true)')
# No price addon: no percentage rows
D.execute('Auctionator = nil; NS.UI:Show("settings"); NS.UI:Refresh()')
data = D.eval('NS.UI.data'); pr = [str(data[i].left) for i in range(1, len(data) + 1)]
check(not any("Suggested" in g or "Materials:" in g for g in pr), "without a price addon, no percentage settings are shown")

# Getting-started guide: fresh character
E = client("Erin")
E.execute('''
  FauxScrollFrame_Update = function() end
  FauxScrollFrame_GetOffset = function() return 0 end
  __advance(10)
  NS.UI:Show("lookup"); CircFrame.IsShown = function() return true end; NS.UI:Refresh()
''')
g = E.eval('NS.UI.guideState')
check(g.visible and g.step == 1 and "profession" in E.eval('NS.UI.GUIDE[1].text'), "guide starts at opening profession windows")
E.execute('__fire("TRADE_SKILL_SHOW"); __advance(2); NS.UI:Refresh()')
check(E.eval('NS.UI.guideState.step') == 2, "scanning a profession moves the guide to step 2")
E.execute('CircGuide.next = CircGuide.next')  # arrows exist
E.execute('NS.UI:LookupItem("Linen Cloth")')
check(E.eval('NS.UI.guideState.step') == 3, "looking up an item moves to step 3")
E.execute('NS.UI:Show("prices")')
check(E.eval('NS.UI.guideState.step') == 4, "visiting Prices moves to step 4")
E.execute('CircDB.wants[2589] = { qty = 1, price = 1 }; NS.UI:Refresh()')
check(E.eval('NS.UI.guideState.step') == 5, "posting a request moves to step 5")
E.execute('__printed = {}; NS.UI:Show("ledger")')
check(E.eval('NS.UI.guideState.visible') == False, "guide disappears when all steps are done")
check(any("finished getting started" in str(m) for m in E.eval("__printed").values()), "player told the guide is finished")

# Lookup buttons follow the search box
E.execute('CircSearchBox._text = ""; NS.UI:Show("lookup")')
en = {}
E.execute('for k, b in pairs(NS.UI.modeButtons) do b.SetEnabled = function(self, on) self._on = on end end; NS.UI:Refresh()')
check(all(E.eval(f'NS.UI.modeButtons.{k}._on') == False for k in ("used", "made", "request")), "lookup buttons disabled with an empty search box")
E.execute('CircSearchBox._text = "linen"; NS.UI:Refresh()')
check(all(E.eval(f'NS.UI.modeButtons.{k}._on') == True for k in ("used", "made", "request")), "lookup buttons enabled once something is typed")

# Requests: Enter with no suggestion opens the request for the typed item
E.execute('NS.UI:Show("requests"); CircFilterBox._text = "Coarse Thread"')
E.execute('if CircRequestDialog then CircRequestDialog.itemID = nil end')
E.execute('local s = CircFilterBox.scripts; NS.UI.data = NS.UI.data')
fired = E.eval('CircFilterBox.HookScript')
E.execute('''
  NS.UI:EditRequest(NS.Lookup:Resolve(CircFilterBox:GetText()))
''')
check(E.eval('CircRequestDialog.itemID') == 2320, "typed item opens the request dialog")

# Ledger management is advanced
E.execute('__printed = {}; SlashCmdList.CIRC("create SMITH")')
check(E.eval('NS.Union:IsStart()') == True and any("Ledger management" in str(m) for m in E.eval("__printed").values()), "/circ create needs Ledger management turned on")

# Reconnect: channel missing after an upgrade is joined again without help
F = client("Finn")
F.execute('JoinPermanentChannel = function(name) __joins = (__joins or 0) + 1; if __joins >= 3 then __channels[name] = 5 end end')
F.execute('CircDB.union = { name = "CIRC_1234_SMITH", abbrev = "SMITH", migrations = 0, takeovers = {} }; __channels = {}')
F.execute('__fire("PLAYER_LOGIN"); __advance(30)')
check(F.eval('NS.Union:Name()') == "circ1234smith", "a saved old-style ledger name is converted on login")
check(F.eval('NS.Union:ChannelID()') is not None and F.eval('__joins') == 3, f"ledger channel rejoined automatically after {F.eval('__joins')} tries")
F.execute('local n = __joins; __advance(60); __joinsAfter = __joins')
check(F.eval('__joinsAfter') == 3, "reconnect stops once connected")
E.execute('__printed = {}; SlashCmdList.CIRC("invite Bob")')
check(any("Ledger management" in str(m) for m in E.eval("__printed").values()), "/circ invite needs Ledger management turned on")
E.execute('CircDB.settings.advanced = true; __printed = {}; SlashCmdList.CIRC("invite Bob")')
check(not any("Ledger management" in str(m) for m in E.eval("__printed").values()), "/circ invite works with Ledger management on")
E.execute('__d = { SetFrameStrata = function(self, s) self.strata = s end, HookScript = function(self, _, fn) self.onHide = fn end }; StaticPopup_Show = function() return __d end; NS:ShowPopup("CIRC_SWITCH")')
check(E.eval('__d.strata') == "FULLSCREEN_DIALOG", "popups raised to the top layer")
E.execute('__d.onHide(__d)')
check(E.eval('__d.strata') == "DIALOG", "popup layer restored when it closes")

# BoE listings: Gwen sells from her bags, Hank finds her under Who has it
G, H = client("Gwen"), client("Hank")
clients.clear(); clients["Gwen-Realm"] = G; clients["Hank-Realm"] = H
G.execute('''
  __bags = { { itemID = 990002, stackCount = 2 }, { itemID = 2570, stackCount = 1, isBound = true } }
  C_Container = { GetContainerNumSlots = function(b) return b == 0 and #__bags or 0 end,
    GetContainerItemInfo = function(b, s) return __bags[s] end, GetContainerItemID = function(b, s) return __bags[s].itemID end }
  FauxScrollFrame_Update = function() end
  FauxScrollFrame_GetOffset = function() return 0 end
''')
step(5, 4)
check(G.eval('NS.Union:IsStart()') and H.eval('NS.Union:IsStart()'), "Gwen and Hank share START")
G.execute('__printed = {}')
check(G.eval('NS.Stock:Add(2570)') == False, "soulbound item can't be listed")
check(G.eval('NS.Stock:Add(990002)') == True, "BoE in bags can be listed")
G.execute('NS.Stock:SetPrice(990002, 12345)')
step(5, 20)
has = H.eval('NS.Lookup:HasIt(990002)')
check(len(has) == 1 and has[1].player == "Gwen-Realm" and has[1].qty == 2 and has[1].price == 12345, "Hank sees Gwen selling 2 at her price")
prof = H.eval('NS.Lookup:Profile("Gwen-Realm")')
check(any(prof[i].kind == "has" for i in range(1, len(prof) + 1)), "listing shows on Gwen's profile")
G.execute('NS.UI:Show("prices"); CircFrame.IsShown = function() return true end; NS.UI:Refresh()')
data = G.eval('NS.UI.data'); rowsl = [data[i] for i in range(1, len(data) + 1)]
sell = [r for r in rowsl if r.money and "Test Widget" in str(r.left)]
check(len(sell) == 1 and sell[0].action.label == "Remove" and "x2" in str(sell[0].left), "Prices tab lists the item with its count and Remove")
G.execute('__bags = { { itemID = 2570, stackCount = 1, isBound = true } }; __fire("BAG_UPDATE_DELAYED")')
step(5, 20)
check(len(H.eval('NS.Lookup:HasIt(990002)')) == 0, "listing leaves the ledger once the item leaves the bags")
check(G.eval('NS.Stock:List()[990002] ~= nil'), "listing kept locally in case the item comes back")
G.execute('__bags = { { itemID = 2589, stackCount = 5 } }; NS.UI:Show("prices"); ChatEdit_InsertLink("|cffffffff|Hitem:2589::|h[Linen Cloth]|h|r")')
check(G.eval('NS.Stock:List()[2589] ~= nil'), "shift-click on Prices lists an item from the bags")

# Requests list buttons
G.execute('NS.UI:Show("requests"); CircFrame.IsShown = function() return true end')
def headers(L):
    d = L.eval('NS.UI.data'); return [str(d[i].left) for i in range(1, len(d) + 1) if d[i].header]
G.execute('NS.UI.requestViews.mine.scripts.OnClick()')
check(headers(G) == ["Your requests"], f"Mine shows only my requests ({headers(G)})")
G.execute('NS.UI.requestViews.others.scripts.OnClick()')
check(headers(G) == ["What others want to buy"], "Others shows only others' requests")
G.execute('NS.UI.requestViews.all.scripts.OnClick()')
check(len(headers(G)) >= 2, "All shows every list")
# BoE names bundled
check(G.eval('NS.Lookup:Resolve("Arcanite Reaper")') == 12784, "bundled BoE names resolve (Arcanite Reaper)")
sug = G.eval('NS.Lookup:Suggest("lifestone", 8)')
check(len(sug) >= 1, "BoE autocomplete finds Lifestone")
# Connect from player input
G.execute('__channels = {}; NS.Union:Nudge()')
check(G.eval('NS.Union:ChannelID()') is not None, "Connect joins the ledger channel")

# Bag search: Hank's bags show up for Gwen under Who has it, kept current by diffs
H.execute('''
  __bags = { { itemID = 2453, stackCount = 7, quality = 1 }, { itemID = 3300, stackCount = 2, quality = 0 }, { itemID = 2570, stackCount = 1, isBound = true } }
  C_Container = { GetContainerNumSlots = function(b) return b == 0 and #__bags or 0 end,
    GetContainerItemInfo = function(b, s) return __bags[s] end, GetContainerItemID = function(b, s) return __bags[s].itemID end }
  __fire("BAG_UPDATE_DELAYED")
''')
step(5, 30)
rows = G.eval('NS.Lookup:HasIt(2453)')
check(len(rows) == 1 and rows[1].player == "Hank-Realm" and rows[1].kind == "bag" and rows[1].qty == 7, "Gwen finds Hank's Bruiseweed in his bags")
check(len(G.eval('NS.Lookup:HasIt(3300)')) == 0 and len(G.eval('NS.Lookup:HasIt(2570)')) == 0, "gray junk and soulbound items are not shared")
H.execute('__outbox_count = 0; __bags[1].stackCount = 4; __fire("BAG_UPDATE_DELAYED")')
step(5, 20)
check(G.eval('NS.Lookup:HasIt(2453)')[1].qty == 4, "bag change reaches Gwen as a diff")
sent = [m for m in H.eval('__printed').values() if 'queued BAGS ' in str(m)]
diffs = [m for m in H.eval('__printed').values() if 'queued BAGD' in str(m)]
check(len(diffs) >= 1, f"changes go out as BAGD diffs ({len(diffs)} diff, {len(sent)} full)")
H.execute('NS.Stock:Add(2453); NS.Stock:SetPrice(2453, 90)')
step(5, 20)
rows = G.eval('NS.Lookup:HasIt(2453)')
check(len(rows) == 1 and rows[1].kind == "has" and rows[1].price == 90, "a listed item shows as a listing, not twice")
G.execute('NS.UI:Show("lookup"); NS.UI:LookupItem(2453); NS.UI.modeButtons.has.scripts.OnClick()')
d = G.eval('NS.UI.data'); hd = [str(d[i].left) for i in range(1, len(d) + 1) if d[i].header]
check(hd == ["Listed for sale"], f"Who has it groups listings ({hd})")
H.execute('CircDB.settings.shareBags = false; NS.Bags:Update()')
step(5, 20)
check(G.eval('NS.Bags:Holders(2453)["Hank-Realm"]') is None, "turning off bag sharing removes Hank's bags")
# Prices views
G.execute('NS.UI:Show("prices"); NS.UI.priceViews.selling.scripts.OnClick()')
d = G.eval('NS.UI.data'); hd = [str(d[i].left) for i in range(1, len(d) + 1) if d[i].header]
check(hd == ["Items I'm selling"], f"Prices Selling view ({hd})")
G.execute('NS.UI.priceViews.all.scripts.OnClick()')

# Taking requests and listings off the market keeps their settings
G.execute('CircDB.wants[2589] = { qty = 12, price = 34 }; NS:Fire("DataChanged")')
step(5, 20)
check(H.eval('NS.Records:Get("Gwen-Realm").wants[2589] ~= nil'), "request on the market reaches Hank")
G.execute('NS.UI:Show("requests"); NS.UI.requestViews.mine.scripts.OnClick()')
d = G.eval('NS.UI.data'); rq = [d[i] for i in range(1, len(d) + 1) if d[i].check]
rq[0].check.fn(False)
step(5, 20)
check(H.eval('NS.Records:Get("Gwen-Realm").wants[2589] == nil') and G.eval('CircDB.wants[2589].qty') == 12, "unchecked request leaves the market but keeps its quantity")
G.execute('NS.UI:Refresh()')
d = G.eval('NS.UI.data'); rq = [d[i] for i in range(1, len(d) + 1) if d[i].check]
rq[0].check.fn(True)
step(5, 20)
check(H.eval('NS.Records:Get("Gwen-Realm").wants[2589] ~= nil and NS.Records:Get("Gwen-Realm").wants[2589].qty') == 12, "rechecked request is back on the market")
G.execute('__bags = { { itemID = 990002, stackCount = 1 } }; __fire("BAG_UPDATE_DELAYED"); CircDB.settings.shareBags = false')
step(5, 4)
G.execute('NS.Stock:List()[990002].off = true; NS:Fire("DataChanged")')
step(5, 20)
check(len([r for r in [H.eval('NS.Lookup:HasIt(990002)')[i] for i in range(1, len(H.eval('NS.Lookup:HasIt(990002)')) + 1)] if r.kind == "has"]) == 0 and G.eval('NS.Stock:List()[990002].price') == 12345, "listing off the market keeps its price")

sys.exit(1 if check.failed else 0)
