"""Builds output/investor/zanjir-investor-plan-fa-final.html / .pdf from zanjir_model_final.py."""
import os
import subprocess
import numpy as np
import zanjir_model_final as M

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.dirname(HERE)
ROOT = os.path.abspath(os.path.join(HERE, "../../.."))
FONTS = os.path.join(ROOT, "client/assets/fonts")
LOGO = os.path.join(ROOT, "client/assets/icon/icon.png")
FX = M.FX
S = M.SCEN
SN = M.SCEN_FA

res = M.main()
R = {s: M.scenario(s) for s in S}
R0 = {s: M.scenario(s, dict(no_intl=True)) for s in S}
SM = {s: res[s] for s in S}
B = SM["base"]
RB = R["base"]

# ------------------------------------------------------------------ formatting
DIG = str.maketrans("0123456789", "۰۱۲۳۴۵۶۷۸۹")


def fa(x, d=0):
    s = f"{abs(x):,.{d}f}".replace(",", "٬").replace(".", "٫")
    return s.translate(DIG)


def sg(x, d=0):                      # losses in parentheses
    x = round(x, d)
    return f"({fa(x, d)})" if x < 0 else fa(x, d)


def sz(x, d=1):                      # signed, minus sign in front
    x = round(x, d)
    return ("−" if x < 0 else "+" if x > 0 else "") + fa(x, d)


def fn(s):
    return str(s).translate(DIG)


def bn(x, d=1):                      # M toman -> B toman
    return fa(x / 1000, d)


def pct(x, d=0):
    s = fa(x * 100, d)
    if "٫" in s:
        s = s.rstrip("۰").rstrip("٫")
    return "٪" + s


MONTHS = "فروردین اردیبهشت خرداد تیر مرداد شهریور مهر آبان آذر دی بهمن اسفند".split()


def jal(m, year=True):               # model month 1 = Aban 1405
    j = 8 + (m - 1)
    y = 1405 + (j - 1) // 12
    n = MONTHS[(j - 1) % 12]
    return f"{n} {fn(y)}" if year else n


def fpm(v):                          # first-profit / payback month label
    if v is None:
        return "پس از ماه ۶۰"
    return f"ماه {fn(v)}" + ("" if v <= 36 else " (برون‌یابی)")


def ysum(a, y):
    return float(np.asarray(a)[y * 12:(y + 1) * 12].sum())


# ------------------------------------------------------------------ headline numbers
ASK_T = [1700.0, 1100.0, 1000.0]
ASK = sum(ASK_T)
CUM_STEP = np.cumsum(ASK_T)
TR_MONTH = [1, 7, 19]
peak = B["peak_need60"]
peak_m = B["peak_month"]
margin = ASK / peak - 1
cons_stop = -SM["cons"]["cum6"]
first_b = B["first_profit"]
intl_share3 = B["rev_intl"][2] / B["rev"][2]
ad_share3 = sum(SM["base"][f"ads_{k}"][2] for k in ("ir", "gp", "ase", "asf")) / B["rev"][2]
keep = M.KEEP_INTL
sens = {r["label"]: r for r in res["sens"]}
no_worst = M.summary(M.scenario("base", dict(worst=dict(
    friend_tax=0, friend_fee=0, transfer=0.05, vat=0, lag_ads=0, lag_iap=0, blackout=0,
    fee_gp_coins=0.15, lag_ir_cash=0, lag_intl_cash=0))))
unit = {s: SM[s]["unit"] for s in S}
seg_b = RB["seg"]
cost36 = {k: float(v[:36].sum()) for k, v in RB["cost"].items()}
rev36 = float(RB["rev"][:36].sum())
y5 = {s: dict(rev=[ysum(R[s]["rev"], y) for y in range(5)], cost=[ysum(R[s]["cost"]["total"], y) for y in range(5)],
              ebit=[ysum(R[s]["ebit"], y) for y in range(5)], tax=[ysum(R[s]["tax"], y) for y in range(5)],
              net=[ysum(R[s]["net"], y) for y in range(5)], cash=[ysum(R[s]["cash"], y) for y in range(5)])
      for s in S}

# KPI gates (thresholds at ~95% of the base path)
g6_inst = float(seg_b["ir"]["inst"][:6].sum())
g6_dau = float(seg_b["ir"]["dau"][5])
g12_intl_dau = float(sum(seg_b[k]["dau"][11] for k in ("gp", "ase", "asf")))
g18_rev = float(RB["rev"][17])
g18_cum = -float(RB["cum"][17])
rnd = lambda x, step: step * round(x / step)

# ------------------------------------------------------------------ charts (inline SVG, brand palette; validated)
C_IR, C_GP, C_AS = "#4C5FE0", "#16A38F", "#C97F0C"          # channel identity
C_CONS, C_BASE, C_OPT = "#C22E22", "#4C5FE0", "#16A38F"      # scenario identity
INK, MUT, LINE = "#1E1B2E", "#6B6780", "#E3DCCC"


def chart_cum():
    W, Hh, pl, pr, pt, pb = 780, 330, 150, 34, 22, 34       # left gutter = end labels at month 36
    ymin, ymax = -6000, 6000
    pw, ph = W - pl - pr, Hh - pt - pb
    X = lambda m: pl + pw - (m / 36) * pw                  # RTL: month 0 on the right
    Y = lambda v: pt + (ymax - max(min(v, ymax), ymin)) / (ymax - ymin) * ph
    g = []
    for v in range(ymin, ymax + 1, 2000):
        g.append(f'<line x1="{pl}" x2="{pl+pw}" y1="{Y(v):.1f}" y2="{Y(v):.1f}" stroke="{INK if v == 0 else LINE}" stroke-width="{1.2 if v == 0 else 1}"/>')
        g.append(f'<text x="{pl+pw+6}" y="{Y(v)+4:.1f}" class="ax" text-anchor="start">{sz(v/1000,0) if v else "۰"}</text>')
    for m in range(0, 37, 6):
        g.append(f'<text x="{X(m):.1f}" y="{Hh-pb+18}" class="ax" text-anchor="middle">{fa(m)}</text>')
    g.append(f'<text x="{pl+pw}" y="{Hh-2}" class="ax" text-anchor="end">ماه از دریافت سرمایه (راست به چپ)</text>')
    g.append(f'<text x="{W-2}" y="{pt-8}" class="ax" text-anchor="end">میلیارد تومان</text>')
    # released funding (step)
    st = []
    for m in range(0, 37):
        k = 0 if m < 7 else 1 if m < 19 else 2
        st.append((m, -CUM_STEP[k]))
    pts = []
    for i, (m, v) in enumerate(st):
        if i and v != st[i - 1][1]:
            pts.append(f"{X(m-0.5):.1f},{Y(st[i-1][1]):.1f}")
            pts.append(f"{X(m-0.5):.1f},{Y(v):.1f}")
        pts.append(f"{X(m):.1f},{Y(v):.1f}")
    g.append(f'<polyline points="{" ".join(pts)}" fill="none" stroke="{C_AS}" stroke-width="2" stroke-dasharray="6 4"/>')
    # Iran-only base
    c0 = [0] + R0["base"]["cum"][:36].tolist()
    g.append(f'<polyline points="{" ".join(f"{X(m):.1f},{Y(c0[m]):.1f}" for m in range(37))}" fill="none" stroke="{MUT}" stroke-width="2" stroke-dasharray="3 3"/>')
    ends = []
    for s, col in (("cons", C_CONS), ("base", C_BASE), ("opt", C_OPT)):
        c = [0] + R[s]["cum"][:36].tolist()
        w = 3 if s == "base" else 2
        g.append(f'<polyline points="{" ".join(f"{X(m):.1f},{Y(c[m]):.1f}" for m in range(37))}" fill="none" stroke="{col}" stroke-width="{w}" stroke-linejoin="round"/>')
        ends.append((s, col, c))
    # opt exits the frame: mark where
    co = [0] + R["opt"]["cum"][:36].tolist()
    mx = next(m for m in range(37) if co[m] > ymax)
    g.append(f'<text x="{X(mx)-8:.1f}" y="{pt+12}" class="lbl" fill="{INK}" text-anchor="end">خوش‌بینانه: از کادر بیرون می‌زند؛ ماه ۳۶ = {sz(co[36]/1000)}</text>')
    # gate marker on cons
    cc = [0] + R["cons"]["cum"][:36].tolist()
    g.append(f'<circle cx="{X(6):.1f}" cy="{Y(cc[6]):.1f}" r="5" fill="#fff" stroke="{C_CONS}" stroke-width="2"/>')
    g.append(f'<text x="{X(6)-4:.1f}" y="{Y(-4500):.1f}" class="lbl" fill="{INK}" text-anchor="middle">گیت ماه ۶ — بدبینانه اینجا</text>')
    g.append(f'<text x="{X(6)-4:.1f}" y="{Y(-4500)+14:.1f}" class="lbl" fill="{INK}" text-anchor="middle">متوقف می‌شود: {sz(cc[6]/1000)}</text>')
    g.append(f'<line x1="{X(6):.1f}" x2="{X(6):.1f}" y1="{Y(cc[6])+6:.1f}" y2="{Y(-4500)-12:.1f}" stroke="{MUT}" stroke-width="1"/>')
    # end labels in the left gutter, at the month-36 value
    lab = [("پایه", C_BASE, R["base"]["cum"][35]), ("بدبینانه، بدون توقف", C_CONS, R["cons"]["cum"][35]),
           ("پایه، فقط ایران", MUT, R0["base"]["cum"][35]), ("سرمایهٔ آزادشده", C_AS, -CUM_STEP[2])]
    lab.sort(key=lambda t: -t[2])
    ys, last = [], None
    for name, col, v in lab:
        y = Y(v) + 4
        if last is not None and y - last < 15:
            y = last + 15
        last = y
        ys.append((name, col, v, y))
    for name, col, v, y in ys:
        g.append(f'<rect x="{pl-14:.1f}" y="{y-8:.1f}" width="9" height="9" rx="2" fill="{col}"/>')
        g.append(f'<text x="{pl-18:.1f}" y="{y:.1f}" class="lbl" fill="{INK}" text-anchor="end">{name}: {sz(v/1000)}</text>')
    return f'<svg viewBox="0 0 {W} {Hh}" class="chart" direction="ltr">{"".join(g)}</svg>'


def chart_monthly():
    W, Hh, pl, pr, pt, pb = 780, 250, 14, 40, 24, 34
    ymax = 400
    pw, ph = W - pl - pr, Hh - pt - pb
    X = lambda m: pl + pw - ((m - 1) / 35) * pw
    Y = lambda v: pt + (ymax - min(v, ymax)) / ymax * ph
    a = np.array(RB["rev_ir"][:36]); b = np.array(RB["seg"]["gp"]["rev"][:36])
    c = np.array(RB["seg"]["ase"]["rev"][:36] + RB["seg"]["asf"]["rev"][:36]); cost = np.array(RB["cost"]["total"][:36])
    g = []
    for v in range(0, ymax + 1, 100):
        g.append(f'<line x1="{pl}" x2="{pl+pw}" y1="{Y(v):.1f}" y2="{Y(v):.1f}" stroke="{INK if v == 0 else LINE}"/>')
        g.append(f'<text x="{pl+pw+6}" y="{Y(v)+4:.1f}" class="ax" text-anchor="start">{fa(v)}</text>')
    for m in [1, 6, 12, 18, 24, 30, 36]:
        g.append(f'<text x="{X(m):.1f}" y="{Hh-pb+18}" class="ax" text-anchor="middle">{fa(m)}</text>')
    g.append(f'<text x="{pl+pw}" y="{Hh-2}" class="ax" text-anchor="end">ماه (راست به چپ)</text>')
    g.append(f'<text x="{W-2}" y="{pt-10}" class="ax" text-anchor="end">میلیون تومان در ماه</text>')
    ms = list(range(1, 37))
    base0 = np.zeros(36)
    for arr, col in ((a, C_IR), (b, C_GP), (c, C_AS)):
        top = base0 + arr
        poly = " ".join(f"{X(m):.1f},{Y(top[m-1]):.1f}" for m in ms) + " " + " ".join(f"{X(m):.1f},{Y(base0[m-1]):.1f}" for m in reversed(ms))
        g.append(f'<polygon points="{poly}" fill="{col}" fill-opacity=".85" stroke="#fff" stroke-width="1.5" stroke-linejoin="round"/>')
        base0 = top
    g.append(f'<polyline points="{" ".join(f"{X(m):.1f},{Y(cost[m-1]):.1f}" for m in ms)}" fill="none" stroke="{C_CONS}" stroke-width="2.4" stroke-linejoin="round"/>')
    if first_b and first_b <= 36:
        g.append(f'<line x1="{X(first_b):.1f}" x2="{X(first_b):.1f}" y1="{pt}" y2="{Y(0):.1f}" stroke="{INK}" stroke-dasharray="4 3"/>')
        g.append(f'<text x="{X(first_b)+6:.1f}" y="{pt+10}" class="lbl" fill="{INK}">ماه {fa(first_b)}: درآمد به هزینه می‌رسد</text>')
    g.append(f'<text x="{X(15):.1f}" y="{Y(cost[14])-9:.1f}" class="lbl" fill="{INK}" text-anchor="middle">هزینهٔ ماهانه</text>')
    g.append(f'<text x="{X(2)-14:.1f}" y="{Y(cost[1])+4:.1f}" class="ax" fill="{MUT}" text-anchor="end">هزینه‌های یک‌باره</text>')
    return f'<svg viewBox="0 0 {W} {Hh}" class="chart" direction="ltr">{"".join(g)}</svg>'


def chart_keep():
    w = M.WORST
    k_ir = 1 / (1 + w["vat"]) * (1 - w["blackout"])
    rows = [
        ("تبلیغ تپسل (ایران)", 100 * k_ir * (1 - w["lag_ads"])),
        ("خرید سکه در کافه‌بازار و مایکت", 100 * k_ir * (1 - w["lag_iap"]) * (1 - w["fee_bazaar"])),
        ("تبلیغ AdMob (گوگل‌پلی و اپ‌استور)", 100 * keep),
        ("خرید سکه در اپ‌استور", 100 * (1 - w["fee_apple"]) * keep),
        ("خرید سکه در گوگل‌پلی", 100 * (1 - w["fee_gp_coins"]) * keep),
    ]
    W, row_h, lab_w, pad = 780, 28, 230, 10
    Hh = row_h * len(rows) + 6
    bw = W - lab_w - pad - 40                           # room for the value at the bar end
    x0 = W - lab_w - pad                                # bars grow right-to-left from the label column
    g = []
    for i, (lab, v) in enumerate(rows):
        y = 3 + i * row_h
        L = bw * v / 100
        g.append(f'<rect x="{x0 - bw:.1f}" y="{y+6}" width="{bw:.1f}" height="15" rx="4" fill="#F0EBE0"/>')
        g.append(f'<rect x="{x0 - L:.1f}" y="{y+6}" width="{L:.1f}" height="15" rx="4" fill="{C_IR}"/>')
        g.append(f'<text x="{W-2}" y="{y+18}" class="lbl" fill="{INK}" text-anchor="end">{lab}</text>')
        g.append(f'<text x="{x0 - L - 6:.1f}" y="{y+18}" class="lbl" fill="{INK}" text-anchor="end">{fa(v)}</text>')
    g.append(f'<text x="{x0 - bw:.1f}" y="{Hh-1}" class="ax" text-anchor="start">مقیاس: ۱۰۰ = کل درآمد ناخالص</text>')
    return f'<svg viewBox="0 0 {W} {Hh+8}" class="chart" direction="ltr">{"".join(g)}</svg>'


def chart_tornado():
    base3 = sens["سناریوی پایه (بدون تغییر)"]["ebit3"]
    pairs = [
        ("نصب ارگانیک گوگل‌پلی و اپ‌استور", "نصب ارگانیک گوگل‌پلی و اپ‌استور نصف", "نصب ارگانیک گوگل‌پلی و اپ‌استور دو برابر", "نصف", "دو برابر"),
        ("eCPM تپسل", "eCPM تپسل نصف (۱۳۰ هزار تومان)", "eCPM تپسل دو برابر (۵۲۰ هزار تومان)", "نصف", "دو برابر"),
        ("نصب ارگانیک ایرانی", "نصب ارگانیک ایرانی نصف", "نصب ارگانیک ایرانی دو برابر", "نصف", "دو برابر"),
        ("شرایط همکار خارجی", None, "دوست در کشوری بدون مالیات (مثلاً امارات) و بدون سهم", "", "بی‌مالیات، بی‌سهم"),
        ("ماندگاری ایرانی", "ماندگاری ایرانی یک پله بدتر (٪۳۰ / ٪۹ / ٪۴)", None, "یک پله بدتر", ""),
        ("حقوق مؤسس", "حقوق مؤسس ۷۰ میلیون (به‌جای ۴۵)", None, "۷۰ میلیون", ""),
        ("قطعی اینترنت و تورم", None, "بدون اختلال قطعی اینترنت و با تعدیل به‌موقع نرخ تپسل", "", "بی‌اثر"),
        ("انسداد حساب گوگل/اپل", "حساب گوگل/اپل در ماه ۱۸ مسدود شود", None, "ماه ۱۸", ""),
        ("تأخیر انتشار خارجی", "نسخهٔ بین‌المللی ۳ ماه دیرتر منتشر شود", None, "۳ ماه", ""),
    ]
    vals = []
    for name, lo, hi, llo, lhi in pairs:
        dl = sens[lo]["ebit3"] - base3 if lo else 0
        dh = sens[hi]["ebit3"] - base3 if hi else 0
        vals.append((name, dl, dh, llo, lhi))
    vals.sort(key=lambda t: -(abs(t[1]) + abs(t[2])))
    W, rh, lab_w = 780, 27, 170
    Hh = rh * len(vals) + 40
    span = 1000
    cx = (W - lab_w) / 2
    sc = (W - lab_w - 40) / 2 / span
    g = [f'<line x1="{cx:.1f}" x2="{cx:.1f}" y1="14" y2="{Hh-20}" stroke="{INK}"/>',
         f'<text x="{cx:.1f}" y="10" class="ax" text-anchor="middle">پایه: {sg(base3)} میلیون</text>']
    for v in (-1000, -500, 500, 1000):
        g.append(f'<text x="{cx + v*sc:.1f}" y="{Hh-6}" class="ax" text-anchor="middle">{sz(v,0)}</text>')
        g.append(f'<line x1="{cx + v*sc:.1f}" x2="{cx + v*sc:.1f}" y1="14" y2="{Hh-20}" stroke="{LINE}"/>')
    for i, (name, dl, dh, llo, lhi) in enumerate(vals):
        y = 18 + i * rh
        for d, col, lb in ((dl, C_CONS, llo), (dh, C_OPT, lhi)):
            if d == 0:
                continue
            x = cx + min(d, 0) * sc
            wdt = abs(d) * sc
            g.append(f'<rect x="{x:.1f}" y="{y+4}" width="{wdt:.1f}" height="16" rx="4" fill="{col}"/>')
            tx = cx + d * sc + (6 if d > 0 else -6)
            g.append(f'<text x="{tx:.1f}" y="{y+16}" class="ax" fill="{INK}" text-anchor="{"start" if d > 0 else "end"}">{sz(d,0)} · {lb}</text>')
        g.append(f'<text x="{W-4}" y="{y+16}" class="lbl" fill="{INK}" text-anchor="end">{name}</text>')
    return f'<svg viewBox="0 0 {W} {Hh}" class="chart" direction="ltr">{"".join(g)}</svg>'


# ------------------------------------------------------------------ tables
def tbl(head, rows, cls="", widths=None):
    cg = "".join(f'<col style="width:{w}">' for w in widths) if widths else ""
    h = "".join(f"<th>{c}</th>" for c in head)
    body = ""
    for r in rows:
        if isinstance(r, dict):
            body += f'<tr class="{r.get("cls","")}">' + "".join(f"<td>{c}</td>" for c in r["c"]) + "</tr>"
        else:
            body += "<tr>" + "".join(f"<td>{c}</td>" for c in r) + "</tr>"
    return f'<div class="tw"><table class="{cls}"><colgroup>{cg}</colgroup><thead><tr>{h}</tr></thead><tbody>{body}</tbody></table></div>'


def neg(x, d=0):
    v = sg(x, d)
    return f'<span class="neg">{v}</span>' if round(x, d) < 0 else f'<span class="pos">{v}</span>'


def summary_table():
    head = ["شاخص", SN["cons"], SN["base"], SN["opt"]]
    gate = lambda s: f"{bn(cons_stop)} میلیارد (توقف ماه ۶)" if s == "cons" else "—"
    rows = [
        ["مجموع نصب ۳۶ ماه (چهار فروشگاه)"] + [fa(sum(SM[s]["inst"])) for s in S],
        ["کاربر فعال روزانه (DAU) پایان سال ۳"] + [fa(SM[s]["dau"][2]) for s in S],
        ["درآمد سال ۳ (میلیون تومان)"] + [fa(SM[s]["rev"][2]) for s in S],
        ["سهم گوگل‌پلی و اپ‌استور از درآمد سال ۳"] + [pct(SM[s]["rev_intl"][2] / SM[s]["rev"][2]) for s in S],
        ["سود (زیان) عملیاتی سال ۳ (میلیون تومان)"] + [neg(SM[s]["ebit"][2]) for s in S],
        ["مانده نقدی تجمعی ماه ۳۶ (میلیون تومان)"] + [neg(SM[s]["cum36"]) for s in S],
        ["اوج نیاز نقدی تا ماه ۶۰ (میلیون تومان)"] + [fa(SM[s]["peak_need60"]) + ("*" if s == "cons" else "") for s in S],
        {"cls": "hl", "c": ["اولین ماه سودده (۳ ماه پیاپی)"] + [fpm(SM[s]["first_profit"]) if SM[s]["first_profit"] else "ندارد" for s in S]},
        ["بازگشت کامل سرمایه (مانده نقدی به صفر برمی‌گردد)"] + [fpm(SM[s]["payback"]) if s != "cons" else "ندارد" for s in S],
        {"cls": "hl", "c": ["زیان سرمایه‌گذار با اجرای گیت ماه ۶"] + [gate(s) for s in S]},
    ]
    return tbl(head, rows, "num sum", ["40%", "20%", "20%", "20%"])


def worst_table():
    w = M.WORST
    rows = [
        ["کارمزد کافه‌بازار و مایکت", "بازار از ۱۴۰۰ برای فروش زیر ۱ میلیارد تومان در سال ٪۱۵ می‌گیرد؛ تداوم آن و نرخ مایکت را تأیید نکرده‌ایم", f"{pct(w['fee_bazaar'])} از هر خرید"],
        ["مالیات بر ارزش افزوده", "نرخ ۱۴۰۵ ٪۱۲ است؛ اینکه از سهم ما کسر شود یا روی قیمت بیاید روشن نیست", f"{pct(w['vat'])} از کل درآمد ایرانی (تبلیغ و خرید) کسر می‌شود"],
        ["تورم", "تورم سالانهٔ ۱۴۰۴ حدود ٪۵۱ و تورم نقطه‌به‌نقطهٔ بهار و تابستان ۱۴۰۵ بالای ٪۸۰ گزارش شده؛ نرخ تپسل با تأخیر تعدیل می‌شود", f"درآمد تبلیغ ایرانی {pct(w['lag_ads'])} و خرید {pct(w['lag_iap'])} زیر قیمت ثابت"],
        ["قطعی اینترنت", "در ۱۴۰۴–۱۴۰۵ حدود ۴ ماه اینترنت بین‌الملل قطع بود؛ شبکهٔ داخلی (بازار، تپسل، سرور ایران) کار کرد", "هر سال ۲ ماه با نصف درآمد ایرانی؛ کاربران داخل ایرانِ اپ‌استور ۳ ماه در سال قطع"],
        ["کارمزد گوگل‌پلی", "ساختار جدید ۲۰۲۶ برای آمریکا، بریتانیا و اروپا: ٪۲۰ برای کالای اثرگذار در بازی + ٪۵ هزینهٔ پرداخت", f"سکه {pct(w['fee_gp_coins'])}، اشتراک {pct(w['fee_gp_subs'])}"],
        ["کارمزد اپل", "برنامهٔ کسب‌وکار کوچک اپل (زیر ۱ میلیون دلار) مستند است", f"{pct(w['fee_apple'])} برای سکه و اشتراک"],
        ["سهم همکار خارجی", "قرارداد هنوز امضا نشده", f"{pct(w['friend_fee'])} از دریافتی فروشگاه‌ها"],
        ["مالیات کشور محل اقامت همکار", "کشور و وضعیت مالیاتی او در مدل مشخص نیست", f"{pct(w['friend_tax'])} از کل دریافتی، بدون کسر هزینه"],
        ["انتقال دلار به ایران", "کارمزد صرافی‌ها متغیر است", f"{pct(w['transfer'])} از مبلغ"],
        ["پرداخت هزینه‌های دلاری از ایران", "خرید دلار و حواله برای سرور و حساب‌ها", f"{pct(w['usd_cost_premium'])} اضافه روی همهٔ هزینه‌های دلاری"],
        ["زمان رسیدن پول", "تسویهٔ بازار و تپسل ماهانه است؛ گوگل، اپل و ادموب ماه بعد پرداخت می‌کنند", f"درآمد ایرانی {fn(w['lag_ir_cash'])} ماه و خارجی {fn(w['lag_intl_cash'])} ماه دیرتر به حساب می‌رسد"],
        ["نسخهٔ بین‌المللی", "هنوز ساخته نشده (فرهنگ لغت انگلیسی، ورود با گوگل/اپل، AdMob، پرداخت فروشگاه، سرور خارجی)", f"ساخت در ۴ ماه؛ گوگل‌پلی ماه {fn(M.LAUNCH['gp'])} ({jal(M.LAUNCH['gp'])})، اپ‌استور ماه {fn(M.LAUNCH['ase'])} ({jal(M.LAUNCH['ase'])})"],
        ["کاربران آیفون داخل ایران", "ادموب در ایران تبلیغ نشان نمی‌دهد و خرید با اپل‌آیدی خارجی دشوار است", f"درآمد صفر از آن‌ها؛ فقط {pct(M.ASF_DIASPORA)} کاربران فارسیِ اپ‌استور (مهاجران) درآمد دارند"],
        ["تجهیزات iOS", "ساخت نسخهٔ آیفون مک و گوشی آیفون لازم دارد", f"خرید مک و آیفون دست‌دوم: {fa(M.ONE_OFF['ios_kit'][1])} میلیون تومان"],
        ["مالیات بر درآمد ایران", "معافیت‌ها (مثلاً دانش‌بنیان) قطعی نیست", f"{pct(w['tax_ir'])} سود هر سال سودده، بدون انتقال زیان سال‌های قبل"],
        ["مجوز فرهنگ لغت", "منابع فهرست فارسی (Hunspell، ویکی‌واژه، OpenSubtitles) ممکن است ذکر منبع و انتشار آزاد خود فهرست را بخواهند", "منبع ذکر و فهرست کلمات آزاد منتشر می‌شود (کد بازی اختصاصی می‌ماند)؛ انگلیسی از فهرست‌های مالکیت عمومی (ENABLE، 12dicts)"],
        ["تبلیغ پولی برای جذب کاربر", "هزینهٔ جذب و ارزش عمر کاربر اندازه‌گیری نشده؛ در فرض پایه هر کاربر کمتر از هزینهٔ جذبش درآمد دارد", "فقط ۶ ماه آزمون در ایران و ۴ ماه در گوگل‌پلی؛ ادامه فقط اگر ارزش عمر کاربر از هزینهٔ جذب بیشتر شود"],
    ]
    return tbl(["موضوع", "چه چیزی معلوم نیست", "فرض این سند"], rows, "txt worst", ["20%", "45%", "35%"])


def competitors_table():
    rows = [
        ["آمیرزا", "کافه‌بازار", "ساختن کلمه از حروف، مرحله‌ای؛ رقابت آنلاین", "۳۰ میلیون نصب فعال · ۴٫۸ از ۲٫۲ میلیون رأی", "بازار بازی کلمه‌ای فارسی بزرگ است؛ آمیرزا مرحله‌ای است، زنجیر رقابتی"],
        ["کوییز آف کینگز", "کافه‌بازار", "مسابقهٔ اطلاعات عمومی ۱ به ۱", "۸٫۴ میلیون نصب فعال · ۴٫۷", "ایرانی‌ها پای رقابت ۱ به ۱ هم‌زمان می‌مانند و پول می‌دهند؛ اقتصاد سکهٔ زنجیر از همین الگو است"],
        ["شهرزاد", "کافه‌بازار", "جدول کلمات + رقابت آنلاین قدرتی و سرعتی", "۸۷۰ هزار نصب · ۴٫۷ از ۵۴ هزار رأی · برندهٔ جشنوارهٔ بازی‌های ایران", "نزدیک‌ترین رقیب آنلاین؛ کاربرانش از تبلیغ اجباری گله دارند — زنجیر فقط تبلیغ انتخابی دارد"],
        ["فندق، حاجی بادوم، کلمچین، کلماتیک، جدول‌سرا و …", "کافه‌بازار", "حدس کلمه، جدول، کلمه‌سازی", "—", "در فهرست بازی‌های کلمه‌ای کافه‌بازار، بازی زنجیرهٔ حرف آخر با رقابت ۱ به ۱ هم‌زمان پیدا نکردیم"],
        ["آقای سیبیل، چهار تصویر یک کلمه، سرهمی", "اپ‌استور", "بازی کلمه‌ای فارسی", "—", "انتشار بازی کلمه‌ای فارسی در اپ‌استور سابقه دارد"],
        ["Word Chain (Tribom Games)", "گوگل‌پلی", "کلمه‌های مرکب؛ نه حرف آخر", "۱ میلیون نصب · ۴٫۷ از ۱۹٫۶ هزار نظر · رتبهٔ ۶۷ پرفروش بازی‌های کلمه‌ای (اسفند ۱۴۰۴)", "عبارت «Word Chain» در گوگل‌پلی جست‌وجو دارد و درآمدزاست"],
        ["WordChain: Last Letter Game، Word Chain – Word Game", "اپ‌استور", "زنجیرهٔ حرف آخر، آنلاین یا با ربات", "کوچک؛ آمار عمومی ندارند", "ژانر در انگلیسی پراکنده است: رقیب بزرگی نیست، ولی تقاضای اثبات‌شده هم نیست — نصب ارگانیک انگلیسی را کم فرض کرده‌ایم"],
    ]
    return tbl(["بازی", "فروشگاه", "سازوکار", "اندازه", "معنا برای زنجیر"], rows, "txt comp", ["16%", "9%", "20%", "24%", "31%"])


def streams_table():
    rows = [
        ["تبلیغ جایزه‌ای", "تپسل؛ eCPM پایه ۲۶۰ هزار تومان", f"AdMob؛ eCPM آمیخته {fa(M.GP['base']['ecpm'],2)} دلار", f"AdMob؛ انگلیسی {fa(M.ASE['base']['ecpm'],2)} دلار؛ فارسی {fa(M.ASF['base']['ecpm_diaspora'],0)} دلار فقط برای ٪۲۵ مهاجر (مؤثر {fa(M.ASF['base']['ecpm'],1)})", "بازیکن برای ۲۰ سکه یا ادامهٔ بازی، خودش تبلیغ را انتخاب می‌کند"],
        ["بستهٔ سکه", "۱۰۰ سکه ۹٬۰۰۰ · ۳۵۰ سکه ۲۵٬۰۰۰ · ۱٬۵۰۰ سکه ۷۹٬۰۰۰ تومان", "۰٫۹۹ · ۲٫۹۹ · ۷٫۹۹ دلار", "۰٫۹۹ · ۲٫۹۹ · ۷٫۹۹ دلار", "کمک‌کننده‌ها، ادامهٔ بازی، چالش روزانهٔ دوم، ورودی مسابقهٔ ۱ به ۱"],
        ["اشتراک پریمیوم", "ماهانه ۱۹٬۰۰۰ تومان", "۲٫۹۹ دلار در ماه", "۲٫۹۹ دلار در ماه", "پیام‌های کنایه، ۱۶ آواتار، نشان تاج — فقط ظاهری و اجتماعی"],
        ["ورودی مسابقه ۱ به ۱", "۲۰ سکه از هر بازیکن، برنده همه را می‌برد", "همان", "همان", "مصرف سکه و انگیزهٔ خرید؛ مسابقه با هوش مصنوعی رایگان است"],
    ]
    return tbl(["جریان", "ایران (بازار و مایکت)", "گوگل‌پلی", "اپ‌استور", "چه می‌خرد"], rows, "txt streams", ["13%", "22%", "17%", "22%", "26%"])


def unit_table():
    names = [("ir", "ایران — بازار و مایکت"), ("gp", "گوگل‌پلی — انگلیسی"), ("ase", "اپ‌استور — انگلیسی"), ("asf", "اپ‌استور — فارسی")]
    rows = []
    for k, n in names:
        cells = [n]
        for s in S:
            u = unit[s][k]
            cells.append(f"{fa(u['arpdau'])} <span class='mut'>({fa(u['parts'][0])} / {fa(u['parts'][1]+u['parts'][2])})</span>")
        cells.append(" · ".join(fa(unit[s][k]["ltv_cpi"], 2) for s in S))
        rows.append(cells)
    return tbl(["بخش", f"ARPDAU {SN['cons']}", f"ARPDAU {SN['base']}", f"ARPDAU {SN['opt']}", "ارزش عمر ÷ هزینهٔ جذب (سه سناریو)"],
               rows, "num unit", ["25%", "17%", "17%", "17%", "24%"])


def assump_ir():
    E = M.IR
    r = lambda lab, f: [lab] + [f(E[s]) for s in S]
    rows = [
        r("نصب ارگانیک ماه اول (رشد ٪۴ در ماه تا ماه ۱۲، سپس ٪۲)", lambda e: fa(e["O"])),
        r("هزینهٔ جذب هر نصب پولی (تومان)", lambda e: fa(e["CPI"])),
        r("نصب اضافه به‌ازای هر نصب پولی (دعوت)", lambda e: fa(e["viral"], 2)),
        r("نصب دهان‌به‌دهان در ماه (٪ نصب‌های تجمعی، ۳ ماه تأخیر)", lambda e: pct(e["w"], 1)),
        r("ماندگاری روز ۱ / ۷ / ۳۰", lambda e: " / ".join(pct(x) for x in e["ret"])),
        r("نمایش تبلیغ جایزه‌ای به‌ازای هر کاربر فعال در روز", lambda e: fa(e["imps"], 1)),
        r("eCPM تپسل (تومان، پیش از کسورات بخش ۲)", lambda e: fa(e["ecpm"])),
        r("خریداران سکه (٪ کاربران ماهانه) / خرج ماهانهٔ هر خریدار (تومان)", lambda e: f"{pct(e['buy'],1)} / {fa(e['spend'])}"),
        r("مشترک پریمیوم (٪ کاربران ماهانه)", lambda e: pct(e["prem"], 1)),
        ["بودجهٔ تبلیغ جذب (میلیون تومان در ماه)", "۴۰ در ماه ۱ تا ۶، سپس صفر", "۴۰ در ماه ۱ تا ۶، سپس صفر", "۴۰ تا ماه ۴، ۱۲۰ در ماه ۵، سپس ۲۰۰ (ارزش عمر از هزینهٔ جذب بیشتر است)"],
    ]
    return tbl(["فرض — ایران (کافه‌بازار و مایکت)", SN["cons"], SN["base"], SN["opt"]], rows, "num as", ["40%", "20%", "20%", "20%"])


def assump_intl():
    G, A, F = M.GP, M.ASE, M.ASF
    r3 = lambda lab, f: [lab] + [f(s) for s in S]
    rows = [
        r3("نصب ارگانیک ماه اول: گوگل‌پلی / اپ‌استور انگلیسی / اپ‌استور فارسی", lambda s: f"{fa(G[s]['O'])} / {fa(A[s]['O'])} / {fa(F[s]['O'])}"),
        r3("ماندگاری روز ۱ / ۷ / ۳۰ — انگلیسی (هر دو فروشگاه)", lambda s: " / ".join(pct(x, 1 if (x * 1000) % 10 else 0) for x in G[s]["ret"])),
        r3("ماندگاری روز ۱ / ۷ / ۳۰ — فارسیِ اپ‌استور (٪۹۰ ایران؛ استخر بازیکن جدا)", lambda s: " / ".join(pct(x, 1) for x in F[s]["ret"])),
        r3("eCPM آمیخته (دلار): گوگل‌پلی / اپ‌استور انگلیسی", lambda s: f"{fa(G[s]['ecpm'],2)} / {fa(A[s]['ecpm'],2)}"),
        r3("eCPM فارسیِ اپ‌استور (دلار): مهاجران × سهم ٪۲۵ = مؤثر", lambda s: f"{fa(F[s]['ecpm_diaspora'],1)} × ٪۲۵ = {fa(F[s]['ecpm'],2)}"),
        r3("نمایش تبلیغ به‌ازای هر کاربر فعال در روز", lambda s: fa(G[s]["imps"], 1)),
        r3("خریداران سکه / خرج ماهانهٔ هر خریدار (دلار)", lambda s: f"{pct(G[s]['buy'],1)} / {fa(G[s]['spend'])}"),
        r3("مشترک پریمیوم با ۲٫۹۹ دلار (٪ کاربران ماهانه)", lambda s: pct(G[s]["prem"], 2)),
        r3("هزینهٔ جذب هر نصب (دلار): گوگل‌پلی / اپ‌استور", lambda s: f"{fa(G[s]['CPI'],2)} / {fa(A[s]['CPI'],2)}"),
        ["تبلیغ جذب", "۱۵ میلیون تومان در ماه، ۴ ماه آزمون گوگل‌پلی؛ اپ‌استور صفر", "همان", "همان"],
    ]
    return tbl(["فرض — گوگل‌پلی و اپ‌استور", SN["cons"], SN["base"], SN["opt"]], rows, "num as", ["40%", "20%", "20%", "20%"])


def geo_table():
    rows = []
    for key, nm in (("gp", "گوگل‌پلی"), ("ase", "اپ‌استور")):
        mix = M.GEO[key]["base"]
        for lab, sh, e in mix:
            rows.append([nm if lab == mix[0][0] else "", lab, pct(sh), fa(e, 2), fa(sh * e, 2)])
        rows.append({"cls": "tot", "c": ["", "جمع (پایه)", "٪۱۰۰", "", fa(M.blend(mix), 2)]})
    return tbl(["فروشگاه", "کشورها", "سهم از نمایش", "eCPM (دلار)", "سهم از eCPM"], rows, "num geo", ["14%", "38%", "16%", "16%", "16%"])


def annual_table():
    rows = []
    for s in S:
        m = SM[s]
        for y in range(3):
            rows.append({"cls": "first" if y == 0 else "", "c": [
                SN[s] if y == 0 else "", f"سال {fa(y+1)}",
                fa(m["inst"][y]), fa(m["dau"][y]), fa(m["rev_ir"][y]), fa(m["rev_gp"][y]), fa(m["rev_ase"][y] + m["rev_asf"][y]),
                fa(m["cost"][y]), neg(m["ebit"][y])]})
    return tbl(["سناریو", "سال", "نصب", "DAU پایان سال", "درآمد ایران", "درآمد گوگل‌پلی", "درآمد اپ‌استور", "هزینه", "سود (زیان) عملیاتی"],
               rows, "num ann", ["11%", "7%", "11%", "11%", "11%", "12%", "11%", "9%", "17%"])


def pnl_table():
    s = "base"
    r = R[s]
    sg_ = r["seg"]
    yr = lambda a: [ysum(a, y) for y in range(5)]
    line = lambda lab, arr, cls="": {"cls": cls, "c": [lab] + [neg(v) if cls in ("tot", "hl") else sg(v) for v in arr]}
    C = r["cost"]
    rows = [
        line("تبلیغ — ایران", yr(sg_["ir"]["ads"])),
        line("سکه و پریمیوم — ایران", yr(sg_["ir"]["iap"] + sg_["ir"]["prem"])),
        line("گوگل‌پلی — انگلیسی", yr(sg_["gp"]["rev"])),
        line("اپ‌استور — انگلیسی", yr(sg_["ase"]["rev"])),
        line("اپ‌استور — فارسی", yr(sg_["asf"]["rev"])),
        line("درآمد خالص (پس از همهٔ کسورات بخش ۲)", yr(r["rev"]), "tot"),
        line("مؤسس", yr(-C["founder"])),
        line("خدمات بیرونی ایران (طراحی، محتوا، حسابداری، حقوقی)", yr(-C["outsource_ir"])),
        line("سرور، پیامک، دامنه و اعلان — ایران", yr(-C["infra_ir"])),
        line("تبلیغ جذب کاربر (ایران و گوگل‌پلی)", yr(-(C["ua_ir"] + C["intl_ua"]))),
        line("سرور خارجی، حساب‌ها و خدمات انگلیسی", yr(-(C["intl_host"] + C["intl_outsource"] + C["intl_accounts"]))),
        line("هزینه‌های یک‌باره (قرارداد، ساخت بین‌المللی، تجهیزات iOS)", yr(-C["one_off"])),
        line("سود (زیان) عملیاتی", yr(r["ebit"]), "hl"),
        line("مالیات بر درآمد (٪۲۵ سال‌های سودده)", yr(-r["tax"])),
        line("سود (زیان) خالص", yr(r["net"]), "tot"),
        line("جریان نقد سال (با تأخیر دریافت و پرداخت مالیات)", yr(r["cash"])),
        line("مانده نقدی تجمعی پایان سال", [float(r["cum"][12 * y + 11]) for y in range(5)], "tot"),
    ]
    return tbl(["سناریوی پایه، میلیون تومان", "سال ۱", "سال ۲", "سال ۳", "سال ۴*", "سال ۵*"], rows, "num pnl",
               ["40%", "12%", "12%", "12%", "12%", "12%"])


def y1_table():
    r = RB
    rows = []
    bal = 0.0
    for m in range(1, 13):
        t = m - 1
        inj = ASK_T[TR_MONTH.index(m)] if m in TR_MONTH else 0.0
        bal += inj + r["cash"][t]
        ri = r["rev_ir"][t]
        rx = r["rev_intl"][t]
        rows.append([f"{fa(m)} · {jal(m, False)}", fa(ri), fa(rx), fa(r["cost"]["total"][t]), sg(r["cash"][t]),
                     sg(r["cum"][t]), fa(inj) if inj else "—", fa(bal)])
    return tbl(["ماه", "درآمد ایران", "درآمد خارجی", "هزینه", "جریان نقد", "تجمعی", "قسط سرمایه", "موجودی نقد"],
               rows, "num y1", ["15%", "11%", "11%", "11%", "12%", "12%", "13%", "15%"])


def uses_table():
    C = cost36
    items = [
        ("مؤسس (۱ نفر فول‌استک، ۴۵ میلیون در ماه + ۵ در سال)", C["founder"]),
        ("خدمات بیرونی ایران", C["outsource_ir"]),
        ("سرور خارجی، حساب‌های گوگل و اپل، خدمات انگلیسی", C["intl_host"] + C["intl_outsource"] + C["intl_accounts"]),
        ("هزینه‌های یک‌باره (قرارداد، ساخت بین‌المللی، مک و آیفون)", C["one_off"]),
        ("سرور، پیامک، دامنه و اعلان — ایران", C["infra_ir"]),
        ("تبلیغ جذب کاربر (آزمون‌ها)", C["ua_ir"] + C["intl_ua"]),
    ]
    tot = C["total"]
    rows = []
    for n, v in items:
        bar = f'<div class="mini"><i style="width:{v/items[0][1]*100:.0f}%"></i></div>'
        rows.append([n, fa(v), pct(v / tot), bar])
    rows.append({"cls": "tot", "c": ["جمع هزینهٔ ۳۶ ماه", fa(tot), "٪۱۰۰", ""]})
    rows.append(["منهای درآمد ۳۶ ماه", f"({fa(rev36)})", "", ""])
    rows.append({"cls": "tot", "c": ["کسری ۳۶ ماه که سرمایه پوشش می‌دهد", fa(tot - rev36), "", ""]})
    return tbl(["مصرف سرمایه (سناریوی پایه، ۳۶ ماه)", "میلیون تومان", "سهم", ""], rows, "num uses", ["52%", "16%", "10%", "22%"])


def sens_table():
    rows = []
    for i, r in enumerate(res["sens"]):
        over = lambda v: f'<span class="neg">{fa(v)}</span>' if v > ASK else fa(v)
        rows.append({"cls": "hl" if i == 0 else "", "c": [r["label"], fa(r["rev3"]), neg(r["ebit3"]), fpm(r["first"]) if r["first"] else "ندارد",
                                                        over(r["peak"]), over(r["peak60"]), fpm(r["payback"]) if r["payback"] else "پس از ماه ۶۰"]})
    return tbl(["تغییر نسبت به سناریوی پایه", "درآمد سال ۳", "سود (زیان) سال ۳", "اولین ماه سودده", "اوج نیاز ۳۶ ماه", "اوج نیاز ۶۰ ماه", "بازگشت سرمایه"],
               rows, "num sens", ["33%", "9%", "10%", "13%", "10%", "10%", "15%"])


def risk_table():
    s18 = sens["حساب گوگل/اپل در ماه ۱۸ مسدود شود"]
    snr = sens["درآمد دلاری هرگز به ایران نرسد؛ توقف در ماه ۱۲"]
    rows = [
        ["انسداد حساب گوگل، اپل یا ادموب به‌خاطر ارتباط با ایران", f"درآمد خارجی قطع می‌شود؛ اگر در ماه ۱۸ رخ دهد اوج نیاز ۳۶ ماهه {bn(s18['peak'],2)} میلیارد است (زیر سقف) ولی سودآوری تا ماه ۵۸ عقب می‌رود", "ناشر واقعی همکار مقیم خارج است؛ نسخهٔ بین‌المللی هیچ اتصالی به سرور، پرداخت یا تبلیغ ایرانی ندارد؛ همکار شهروند یا مقیم آمریکا نیست؛ مشاورهٔ حقوقی در کشور او در ماه ۱ (در بودجه)"],
        ["پول دلاری به ایران نرسد", f"اگر هیچ پولی منتقل نشود و بخش خارجی در ماه ۱۲ بسته شود، اوج نیاز ۳۶ ماهه {bn(snr['peak'],2)} میلیارد است", "گیت ماه ۱۲: اولین پرداخت واقعی باید به حساب ایران رسیده باشد، وگرنه بخش خارجی بسته می‌شود"],
        ["قطعی دوباره اینترنت یا بحران", "کاربران و درآمد ایرانی افت می‌کنند؛ دسترسی مؤسس به کنسول‌ها قطع می‌شود", "پشتهٔ داخلی روی شبکهٔ ملی کار می‌کند؛ کار فروشگاه‌های خارجی با همکار است؛ اثر ۲ ماه در سال در پایه لحاظ شده"],
        ["تورم و ارز", "هزینه‌های تومانی بالا می‌روند و نرخ تبلیغ دیر تعدیل می‌شود", "قیمت‌گذاری فصلی بسته‌ها؛ درآمد دلاری پوشش طبیعی است؛ بودجه در هر گیت بازبینی می‌شود"],
        ["تیم یک‌نفره", "بیماری یا خستگی مؤسس کار را متوقف می‌کند", "کد مستند و آزمون‌دار؛ خدمات بیرونی در بودجه؛ نفر دوم در گیت ماه ۱۸ اگر درآمد اجازه دهد"],
        ["وابستگی به تبلیغ", f"{pct(ad_share3)} درآمد سال ۳ پایه از تبلیغ جایزه‌ای است", "دو شبکهٔ مستقل (تپسل و ادموب)؛ رشد خرید و پریمیوم"],
        ["شروع سرد رقابت ۱ به ۱", "تا کاربر هم‌زمان کافی نباشد، رقیب انسانی پیدا نمی‌شود", "هوش مصنوعی جایگزین، حالت تک‌نفره و چالش روزانه؛ در نرخ خرید پایین فرض شده"],
        ["کپی‌شدن بازی", "سازوکار ساده است", "فرهنگ لغت پالایش‌شده، حلقه‌های اجتماعی (دوستان، چالش، جدول)، سرعت اجرا"],
        ["خطای پیش‌بینی", "هیچ عددی هنوز از بازار واقعی نیامده", "سرمایه سه قسطی و مشروط به داده؛ بیشترین زیان سرمایه‌گذار قسط اول است"],
    ]
    return tbl(["ریسک", "اثر", "کاهش"], rows, "txt risk", ["22%", "36%", "42%"])


# ------------------------------------------------------------------ distribution diagram (HTML)
def stack_diagram():
    return f"""
<div class="stacks">
  <div class="stack ir">
    <div class="st-h"><span class="dot" style="background:{C_IR}"></span>پشتهٔ داخلی — فارسی، اندروید</div>
    <div class="flow">
      <div class="node">کافه‌بازار و مایکت</div><div class="arr">←</div>
      <div class="node">سرور ایران</div><div class="arr">←</div>
      <div class="node">تپسل + پرداخت بازار/مایکت</div><div class="arr">←</div>
      <div class="node acc">حساب زنجیر در ایران</div>
    </div>
    <p>از ماه ۱. روی شبکهٔ ملی اطلاعات کار می‌کند، پس قطعی اینترنت بین‌الملل آن را از کار نمی‌اندازد و به تحریم خارجی وابسته نیست.</p>
  </div>
  <div class="stack intl">
    <div class="st-h"><span class="dot" style="background:{C_GP}"></span><span class="dot" style="background:{C_AS}"></span>پشتهٔ بین‌المللی — انگلیسی + فارسیِ آیفون</div>
    <div class="flow">
      <div class="node">گوگل‌پلی و اپ‌استور (حساب همکار)</div><div class="arr">←</div>
      <div class="node">سرور خارج</div><div class="arr">←</div>
      <div class="node">AdMob + پرداخت گوگل/اپل</div><div class="arr">←</div>
      <div class="node">حساب همکار</div><div class="arr">←</div><div class="node">صرافی</div><div class="arr">←</div>
      <div class="node acc">حساب زنجیر در ایران</div>
    </div>
    <p>گوگل‌پلی از ماه {fn(M.LAUNCH['gp'])} و اپ‌استور از ماه {fn(M.LAUNCH['ase'])}. درآمد دلاری در برابر تورم ریال پوشش است و کاربران خارج از ایران از قطعی اینترنت ایران اثر نمی‌گیرند. این نسخه عمداً به سرور ایران وصل نمی‌شود تا حساب ناشر در معرض تعلیق نباشد؛ بنابراین بازیکنان فارسیِ آیفون استخر رقابت جدایی دارند.</p>
  </div>
</div>"""


# ------------------------------------------------------------------ page scaffolding
PAGES = []


def page(body, n):
    PAGES.append(f'<section class="page"><div class="pg">{body}</div><footer><span>زنجیر · طرح درآمدی و پیش‌بینی مالی</span><span>{fa(n)}</span></footer></section>')


def H(n, title, sub=""):
    s = f'<p class="lead">{sub}</p>' if sub else ""
    return f'<div class="sec"><span class="badge">{fa(n)}</span><h2>{title}</h2></div>{s}'


def kpi(val, lab, col):
    return f'<div class="kpi"><b style="color:{col}">{val}</b><span>{lab}</span></div>'


# ---- page 1: cover + executive summary
sh_intl = pct(intl_share3)
page(f"""
<div class="hero">
  <div class="hero-txt">
    <div class="eyebrow">طرح درآمدی و پیش‌بینی مالی · سند نهایی برای سرمایه‌گذار</div>
    <h1>زنجیر</h1>
    <div class="tag">بازی رقابتی زنجیرهٔ کلمات — کافه‌بازار، مایکت، گوگل‌پلی و اپ‌استور</div>
    <div class="meta">مهر ۱۴۰۵ · افق ۳۶ ماه از دریافت سرمایه (ماه ۱ = {jal(1)}) · مبالغ به تومان و قیمت ثابت مهر ۱۴۰۵ · هر دلار ۲۶۶٬۰۰۰ تومان</div>
  </div>
  <img class="logo" src="file://{LOGO}">
</div>
<div class="kpis">
  {kpi(f"{bn(ASK)} میلیارد تومان", f"سرمایهٔ درخواستی در سه قسط مشروط (≈{fa(ASK*1e6/FX/1000,1)} هزار دلار)", C_IR)}
  {kpi(f"ماه {fa(first_b)}", "اولین ماه سودده در سناریوی پایه، با فرض بدترین حالت در همهٔ مجهولات", C_GP)}
  {kpi(f"{sh_intl}", "سهم گوگل‌پلی و اپ‌استور از درآمد سال سوم (پایه)", C_AS)}
  {kpi(f"{bn(ASK_T[0])} میلیارد", "سقف ریسک سرمایه‌گذار در بدترین سناریو: فقط قسط اول، با توقف در گیت ماه ۶", C_CONS)}
</div>
{H(1, "خلاصهٔ اجرایی")}
<p>زنجیر بازی رقابتی زنجیرهٔ کلمات است: هر بازیکن کلمه‌ای می‌گوید که با حرف آخر کلمهٔ قبلی شروع شود. محصول ساخته شده و روی سرور واقعی کار می‌کند — تک‌نفره، مقابل هوش مصنوعی در سه سطح، رقابت آنلاین ۱ به ۱ روی یک زنجیرهٔ مشترک و چالش روزانه با جدول امتیاز. این سند برنامهٔ درآمدی و پیش‌بینی مالی ۳۶ ماهه را برای انتشار در چهار فروشگاه ارائه می‌دهد: کافه‌بازار و مایکت برای اندروید ایران، و گوگل‌پلی و اپ‌استور — از طریق یک همکار ایرانیِ مورد اعتماد مقیم خارج — برای نسخهٔ انگلیسی جهانی و کاربران فارسی‌زبان آیفون.</p>
<p><b>درخواست: {bn(ASK)} میلیارد تومان در سه قسط.</b> قسط اول {bn(ASK_T[0])} میلیارد برای ماه ۱ تا ۶ است؛ قسط دوم ({bn(ASK_T[1])} میلیارد، ماه ۷) و سوم ({bn(ASK_T[2])} میلیارد، ماه ۱۹) فقط وقتی پرداخت می‌شوند که داده‌های واقعی بازار به اهداف گیت برسند (بخش ۹).</p>
{summary_table()}
<p class="note">اعداد داخل پرانتز زیان است؛ مبالغ به میلیون تومان. * در سناریوی بدبینانه اگر برخلاف قاعدهٔ گیت ادامه دهیم؛ با توقف در ماه ۶ زیان {bn(cons_stop)} میلیارد است. «سودده» یعنی سه ماه پیاپی درآمد ≥ هزینه.</p>
<ul class="keys">
  <li><b>همهٔ مجهولات در بدترین حالت‌اند.</b> کارمزد کامل فروشگاه‌ها، ٪۱۲ مالیات بر ارزش افزوده، اثر تورم و قطعی اینترنت، سهم و مالیات همکار خارجی و هزینهٔ انتقال پول؛ از هر دلار درآمد تبلیغ خارجی فقط {fa(keep*100)} سنت و از هر دلار خرید ۳۵ تا ۴۰ سنت به ایران می‌رسد (بخش ۲ و ۵).</li>
  <li><b>سناریوی پایه با همین فرض‌ها از ماه {fa(first_b)} سودده است</b>؛ اوج نیاز نقدی {bn(peak,2)} میلیارد تومان در ماه {fa(peak_m)} است و {bn(ASK)} میلیارد حدود {pct(margin)} حاشیهٔ اطمینان دارد.</li>
  <li><b>بازارهای خارجی بیش از نیمی از درآمد سال سوم را می‌سازند</b> ({sh_intl}) و درآمد دلاری در برابر تورم و قطعی اینترنت ایران پوشش طبیعی است.</li>
  <li><b>در سناریوی خوش‌بینانه سرمایه در ماه {fa(SM['opt']['payback'])} برمی‌گردد</b> و مانده نقدی ماه ۳۶ به {sz(SM['opt']['cum36']/1000)} میلیارد تومان می‌رسد.</li>
</ul>
""", 1)

# ---- page 2: worst-case principle
nw = no_worst
page(f"""
{H(2, "قاعدهٔ این سند: بدترین حالت", "بازی هنوز در هیچ فروشگاهی دادهٔ واقعی ندارد؛ پس این سند پیش‌بینی است، نه گزارش عملکرد. برای اینکه پیش‌بینی خوش‌خیالانه نباشد، یک قاعده را همه‌جا اجرا کرده‌ایم: <b>هر چیزی که دربارهٔ آن داده نداریم یا ابهام دارد، با بدترین مقدار معقول وارد مدل شده است.</b> عدم قطعیت خود بازار — نصب، ماندگاری و درآمد تبلیغ — جداگانه با سه سناریو پوشش داده می‌شود (بخش ۶).")}
{worst_table()}
<div class="box good"><b>این قاعده چقدر خرج دارد؟</b> اگر هیچ‌یک از فرض‌های ساختاری بالا رخ ندهد (همکار بدون سهم و مالیات، انتقال با ٪۵، بدون مالیات بر ارزش افزوده، بدون اثر تورم و قطعی، کارمزد سکهٔ گوگل ٪۱۵ و پرداخت بی‌تأخیر)، سناریوی پایه از <b>ماه {fa(nw['first_profit'])}</b> سودده می‌شد، اوج نیاز نقدی <b>{bn(nw['peak_need60'],2)} میلیارد</b> بود و درآمد سال سوم <b>{fa(nw['rev'][2])}</b> میلیون تومان. این سند عمداً ماه {fa(first_b)}، {bn(peak,2)} میلیارد و {fa(B['rev'][2])} میلیون را مبنا گذاشته است؛ هر فرضی که در عمل بهتر از آب درآید، مستقیماً به نفع سرمایه‌گذار است.</div>
""", 2)

# ---- page 3: product, team, distribution
CHAIN = [("زنجیر", "c1"), ("رنگ", "c2"), ("گلاب", "c3"), ("باران", "c4"), ("نارنج", "c1"), ("جنگل", "c2")]
chain_html = ""
for i, (w_, c_) in enumerate(CHAIN):
    if i:
        chain_html += f'<span class="lk">{w_[0]}</span>'
    chain_html += f'<span class="wt {c_}">{w_}</span>'
page(f"""
{H(3, "محصول، تیم و ساختار انتشار")}
<div class="chainbox"><div class="chain">{chain_html}</div>
<p>هر کلمه با حرف آخر کلمهٔ قبلی شروع می‌شود؛ کلمه باید در فرهنگ لغت باشد، تکراری نباشد و دست‌کم ۳ حرف داشته باشد. هر نوبت ۱۵ ثانیه وقت دارد و امتیاز با طول کلمه، سرعت و پشت‌سرهم بودن پاسخ‌های درست بالا می‌رود. در رقابت آنلاین، دو بازیکن نوبتی روی یک زنجیرهٔ مشترک بازی می‌کنند و اولین اشتباه می‌بازد.</p></div>
<div class="cols2">
  <div class="card">
    <h3>ساخته و اجراشده</h3>
    <ul>
      <li>اپ Flutter با طراحی کامل فارسی و راست‌به‌چپ، حالت روز و شب، ارقام فارسی و تقویم شمسی.</li>
      <li>چهار حالت: تک‌نفره (۲ جان)، مقابل هوش مصنوعی (آسان، متوسط، سخت)، رقابت آنلاین ۱ به ۱ با زنجیرهٔ مشترک، چالش روزانه.</li>
      <li>فرهنگ لغت ۲۱٬۵۲۷ کلمه‌ای فارسیِ دستی‌پالایش‌شده؛ اعتبارسنجی آفلاین روی گوشی و اعتبارسنجی مرجع روی سرور.</li>
      <li>سرور Go با WebSocket، PostgreSQL و Redis، روی سرور تولید فعال؛ ورود با شماره موبایل و رمز یک‌بارمصرف، و حالت مهمان.</li>
      <li>حلقه‌های ماندگاری: استریک روزانه، جدول امتیاز هفتگی و همیشگی، دوستان و چالش دوستانه، صندوق جوایز، کد دعوت، سطح و امتیاز تجربه.</li>
      <li>اقتصاد سکه، کمک‌کننده‌ها، ورودی سکه‌ای مسابقه، تبلیغ جایزه‌ای تپسل و مزایای پریمیوم (پیام کنایه، ۱۶ آواتار، نشان).</li>
    </ul>
  </div>
  <div class="card">
    <h3>با این سرمایه ساخته می‌شود</h3>
    <ul>
      <li><b>ماه ۱–۲:</b> پرداخت کافه‌بازار و مایکت، پیامک واقعی کاوه‌نگار، دامنه و TLS، اتصال زندهٔ تپسل؛ انتشار در بازار و مایکت.</li>
      <li><b>ماه ۱–۴:</b> نسخهٔ بین‌المللی: فرهنگ لغت انگلیسی، رابط انگلیسی، ورود با گوگل و اپل، AdMob، پرداخت گوگل و اپل، سرور خارج.</li>
      <li><b>ماه {fn(M.LAUNCH['gp'])}–{fn(M.LAUNCH['ase'])}:</b> انتشار در گوگل‌پلی و اپ‌استور از حساب همکار.</li>
      <li><b>ماه ۷ به بعد:</b> دست‌های «بهترین از ۵»، نشان‌ها، آواتار در فهرست دوستان، محتوای فصلی و بهینه‌سازی صفحهٔ فروشگاه‌ها.</li>
    </ul>
    <h3>تیم</h3>
    <p>یک مؤسس و توسعه‌دهندهٔ فول‌استک (محصول، کلاینت، سرور، انتشار و بازاریابی) با حقوق ۴۵ میلیون تومان در ماه؛ طراحی، محتوا، حسابداری و حقوقی برون‌سپاری می‌شود. <b>همکار خارجی</b> — ایرانیِ مقیم خارج و مورد اعتماد مؤسس — حساب‌های گوگل‌پلی، اپل و ادموب را به نام خود باز می‌کند، بازی را منتشر می‌کند و پرداخت‌ها را دریافت و به ایران منتقل می‌کند. قرارداد کتبی (مالکیت بازی برای زنجیر، سهم او و شرایط انتقال) در ماه ۱ امضا می‌شود.</p>
  </div>
</div>
<h3 class="mt">دو پشتهٔ مستقل انتشار</h3>
{stack_diagram()}
""", 3)

# ---- page 4: market & competitors
page(f"""
{H(4, "بازار و رقبا")}
<div class="stats">
  <div class="stat"><b>۵۵٫۸ میلیون</b><span>کاربر ثبت‌نامی کافه‌بازار (گزارش سالانهٔ ۱۴۰۲)</span></div>
  <div class="stat"><b>۷٫۸ میلیون</b><span>نصب روزانه از کافه‌بازار؛ ۴۶٫۲ میلیون نصب در سال از تبلیغات</span></div>
  <div class="stat"><b>۵٫۵ میلیون</b><span>خریدار در کافه‌بازار؛ ۲ هزار میلیارد تومان فروش محتوای دیجیتال در ۱۴۰۲</span></div>
  <div class="stat"><b>۶ تا ۷ میلیون</b><span>کاربر آیفون در ایران (برآورد قدیمی، ٪۱۰ تا ٪۱۵ کاربران موبایل؛ آمار رسمی نیست)</span></div>
  <div class="stat"><b>۴ میلیون</b><span>ایرانیان خارج از کشور (برآورد رسمی ۱۴۰۰): ٪۴۷ آمریکا، ٪۲۹ اروپا</span></div>
  <div class="stat"><b>۱۹٫۶ / ۱۶٫۵ دلار</b><span>eCPM تبلیغ جایزه‌ای آمریکا در iOS / اندروید (Appodeal، زمستان ۲۰۲۴)</span></div>
</div>
<h3>رقبا</h3>
{competitors_table()}
<div class="box"><b>جایگاه زنجیر.</b> در ایران، بازار بازی کلمه‌ای و رقابت ۱ به ۱ با آمیرزا (۳۰ میلیون نصب فعال) و کوییز آف کینگز (۸٫۴ میلیون) ثابت شده، ولی ترکیب «زنجیرهٔ کلمات + رقابت آنلاین هم‌زمان» خالی است. سهم فرض‌شدهٔ ما کوچک است: کاربر فعال روزانهٔ پایه در پایان سال سوم ({fa(B['dau_ir'][2])} نفر در ایران) حدود یک‌صدم درصدِ کاربران ثبت‌نامی کافه‌بازار است. در انگلیسی رقیب بزرگ زنجیرهٔ حرف آخر نیست، ولی تقاضای ثابت‌شده هم نیست؛ پس نصب ارگانیک انگلیسی را عمداً پایین گرفته‌ایم.</div>
""", 4)

# ---- page 5: revenue model
page(f"""
{H(5, "مدل درآمدی", "همهٔ جریان‌ها اختیاری‌اند: تبلیغ اجباری، بنر یا تبلیغ میان‌بازی نداریم — فقط تبلیغ جایزه‌ای که خود بازیکن انتخاب می‌کند — و هیچ برتری‌ای در رقابت آنلاین فروخته نمی‌شود؛ پریمیوم فقط ظاهری و اجتماعی است.")}
{streams_table()}
<h3>از هر ۱۰۰ واحد درآمد ناخالص، چقدر به حساب زنجیر در ایران می‌رسد؟</h3>
{chart_keep()}
<p class="note">پس از همهٔ کسورات بخش ۲: کارمزد فروشگاه، مالیات بر ارزش افزوده، اثر تورم و قطعی (ایران)؛ مالیات و سهم همکار و هزینهٔ انتقال (خارج). eCPM ادموب و تپسل از قبل خالص سهم شبکه است.</p>
<h3>درآمد روزانهٔ هر کاربر فعال (ARPDAU، تومان، خالص) و نسبت ارزش عمر به هزینهٔ جذب</h3>
{unit_table()}
<p class="note">داخل پرانتز: تبلیغ / خرید و اشتراک. ارزش عمر = درآمد خالص ۳۶۵ روز اول هر نصب. وقتی این نسبت زیر ۱ است، تبلیغ پولی برای جذب کاربر زیان‌ده است؛ برای همین در سناریوی پایه جذب پولی فقط آزمون است و رشد از نصب ارگانیک، دعوت و دهان‌به‌دهان می‌آید. هر کاربر انگلیسی اپ‌استور حدود {fa(unit['base']['ase']['arpdau']/unit['base']['ir']['arpdau'],1)} برابر کاربر ایرانی درآمد خالص دارد.</p>
<h3>آمیختهٔ کشورها پشت eCPM خارجی (سناریوی پایه)</h3>
{geo_table()}
<p class="note">eCPM یعنی درآمد ناشر به‌ازای هر ۱٬۰۰۰ نمایش تبلیغ پس از سهم شبکه. اعداد کشورها پایین‌تر از گزارش‌های عمومی گذاشته شده‌اند (آمریکا در گزارش Appodeal بالای ۱۶ دلار است). سهم کشورهای پردرآمد است که eCPM را تعیین می‌کند؛ اگر بیشتر بازیکنان انگلیسی از هند و فیلیپین باشند، eCPM گوگل‌پلی به حدود ۱ دلار می‌افتد — این حالت در سناریوی بدبینانه آمده است. نسبت کاربر فعال روزانه به ماهانه در همه‌جا ۰٫۲۲ است.</p>
""", 5)

# ---- page 6: assumptions
page(f"""
{H(6, "مفروضات بازار در سه سناریو", "مدل ماهانه است و هر فروشگاه را جدا می‌سنجد: نصب (ارگانیک، پولی، دعوت و دهان‌به‌دهان) → ماندگاری → کاربر فعال → درآمد. هیچ‌کدام از این اعداد هنوز اندازه‌گیری نشده؛ شش ماه اول دقیقاً برای اندازه‌گیری آن‌هاست.")}
{assump_ir()}
{assump_intl()}
""", 6)

# ---- page 7: forecast — cumulative cash + annual table
page(f"""
{H(7, "پیش‌بینی مالی سه‌ساله")}
<div class="card chartcard">
  <div class="ct">مانده نقدی تجمعی: سناریوی پایه زیر سرمایهٔ آزادشده می‌ماند و از ماه {fa(peak_m)} رو به بالا برمی‌گردد</div>
  {chart_cum()}
  <p class="note">میلیارد تومان، قیمت ثابت مهر ۱۴۰۵، با تأخیر دریافت پول. خط‌چین نارنجی: سرمایهٔ آزادشده پس از هر قسط ({bn(CUM_STEP[0])}، {bn(CUM_STEP[1])} و {bn(CUM_STEP[2])} میلیارد). خط‌چین خاکستری: همان سناریوی پایه بدون گوگل‌پلی و اپ‌استور. اوج نیاز پایه در ماه {fa(peak_m)} ({bn(peak,2)} میلیارد) کمی پس از کادر است.</p>
</div>
<h3>نتایج سالانه (میلیون تومان)</h3>
{annual_table()}
<p class="note">درآمدها خالص و پس از همهٔ کسورات بخش ۲ است. «هزینه» همهٔ هزینه‌های ایران و خارج، از جمله هزینه‌های یک‌بارهٔ سال اول ({fa(cost36['one_off'])} میلیون) را در بر دارد. سود عملیاتی پیش از مالیات بر درآمد است.</p>
<div class="box"><b>چرا گوگل‌پلی و اپ‌استور، با وجود اینکه نیمی از هر دلار در راه می‌ماند؟</b> در سناریوی پایه، بخش خارجی تا ماه ۳۶ حدود {bn(R0['base']['cum'][35]-RB['cum'][35],2)} میلیارد به نیاز نقدی اضافه می‌کند (هزینه‌های یک‌باره و ثابت دلاری)، ولی سربه‌سر کل کسب‌وکار را از ماه {fa(SM['base']['ir_only']['first_profit'])} به ماه {fa(first_b)} جلو می‌آورد و سود عملیاتی سال پنجم را از {sg(ysum(R0['base']['ebit'],4))} به {sg(y5['base']['ebit'][4])} میلیون تومان می‌رساند. در سناریوی خوش‌بینانه سهم آن از مانده نقدی ماه ۳۶ حدود {bn(SM['opt']['cum36']-SM['opt']['ir_only']['cum36'],1)} میلیارد است. مهم‌تر: درآمد دلاری با تورم ریال کوچک نمی‌شود و کاربرانش با قطعی اینترنت ایران از دست نمی‌روند.</div>
""", 7)

# ---- page 8: P&L + monthly chart
page(f"""
{H(8, "صورت سود و زیان و جریان نقد — سناریوی پایه")}
{pnl_table()}
<p class="note">* سال‌های ۴ و ۵ برون‌یابی همان مدل بدون هیچ سرمایه‌گذاری تازه یا ویژگی جدید است. مالیات بر درآمد ٪۲۵ روی سود هر سال سودده، بدون انتقال زیان سال‌های قبل (بدترین حالت).</p>
<div class="card chartcard">
  <div class="ct">درآمد ماهانه به تفکیک فروشگاه در برابر هزینهٔ ماهانه</div>
  <div class="legend"><span><i style="background:{C_IR}"></i>ایران (بازار و مایکت)</span><span><i style="background:{C_GP}"></i>گوگل‌پلی</span><span><i style="background:{C_AS}"></i>اپ‌استور</span><span><i class="ln" style="background:{C_CONS}"></i>هزینهٔ ماهانه</span></div>
  {chart_monthly()}
  <p class="note">سناریوی پایه، میلیون تومان در ماه. جهش‌های هزینه در ماه‌های ۱ تا ۴ هزینه‌های یک‌باره و در ماه‌های ۶، ۱۸ و ۳۰ حق عضویت سالانهٔ اپل است.</p>
</div>
""", 8)

# ---- page 9: year-1 monthly + uses
page(f"""
{H(9, "سرمایه: مصرف، اقساط و گیت‌ها")}
<div class="tranches">
  <div class="tr t1"><div class="tr-h">قسط ۱ · {bn(ASK_T[0])} میلیارد</div><div class="tr-m">ماه ۱ تا ۶ · {jal(1)} تا {jal(6)}</div><p>انتشار در بازار و مایکت، ساخت نسخهٔ بین‌المللی و انتشار در گوگل‌پلی و اپ‌استور، آزمون جذب. حتی زیان سناریوی بدبینانه تا ماه ۶ ({bn(cons_stop,2)} میلیارد) را پوشش می‌دهد.</p></div>
  <div class="tr t2"><div class="tr-h">قسط ۲ · {bn(ASK_T[1])} میلیارد</div><div class="tr-m">ماه ۷ تا ۱۸ · پس از گیت ماه ۶</div><p>رشد ارگانیک، ویژگی‌های ماندگاری، تصمیم دربارهٔ بخش خارجی در ماه ۱۲. نیاز پایه تا ماه ۱۸: {bn(-RB['cum'][17],2)} میلیارد.</p></div>
  <div class="tr t3"><div class="tr-h">قسط ۳ · {bn(ASK_T[2])} میلیارد</div><div class="tr-m">ماه ۱۹ تا ۳۶ · پس از گیت ماه ۱۸</div><p>رسیدن به سودآوری ماهانه (پایه: ماه {fa(first_b)}) و پوشش اوج نیاز {bn(peak,2)} میلیارد در ماه {fa(peak_m)} با {pct(margin)} حاشیه.</p></div>
</div>
<div class="gates">
  <div class="gate"><div class="g-h">گیت ماه ۶ · {jal(6)} — شرط قسط ۲</div><ul>
    <li>ایران: ≥ {fa(rnd(g6_inst*0.95,1000))} نصب و ≥ {fa(rnd(g6_dau*0.95,100))} کاربر فعال روزانه؛ ماندگاری روز ۱ / ۷ / ۳۰ ≥ ٪۳۵ / ٪۱۲ / ٪۵.</li>
    <li>درآمد خالص هر کاربر فعال ایرانی ≥ ۳۰۰ تومان در روز، با درآمد واقعی تپسل و خرید واقعی بازار و مایکت.</li>
    <li>نسخهٔ بین‌المللی در گوگل‌پلی و اپ‌استور منتشر شده باشد؛ نتیجهٔ آزمون جذب (هزینهٔ هر نصب و ارزش عمر) گزارش شود.</li>
    <li>اگر نرسید: توقف یا ادامه با هزینهٔ کمتر؛ باقی‌ماندهٔ قسط ۱ برمی‌گردد یا با توافق خرج می‌شود.</li></ul></div>
  <div class="gate"><div class="g-h">گیت ماه ۱۲ · {jal(12)} — تصمیم بخش خارجی</div><ul>
    <li>اولین پرداخت واقعی گوگل، اپل یا ادموب به حساب زنجیر در ایران رسیده باشد.</li>
    <li>≥ {fa(rnd(g12_intl_dau*0.9,50))} کاربر فعال روزانه در دو فروشگاه خارجی؛ eCPM واقعی ≥ دو سوم فرض پایه.</li>
    <li>اگر نرسید: بخش خارجی بسته می‌شود و حدود ۴۵ میلیون تومان در ماه صرفه‌جویی می‌شود.</li></ul></div>
  <div class="gate"><div class="g-h">گیت ماه ۱۸ · {jal(18)} — شرط قسط ۳</div><ul>
    <li>درآمد خالص ماهانه ≥ {fa(rnd(g18_rev*0.95,5))} میلیون تومان و رو به رشد.</li>
    <li>زیان تجمعی ≤ {bn(g18_cum*1.05,1)} میلیارد تومان.</li>
    <li>اگر ارزش عمر کاربر از هزینهٔ جذب بیشتر شد، بودجهٔ جذب پولی از همین قسط باز می‌شود.</li></ul></div>
</div>
{uses_table()}
""", 9)

# ---- page 10: year-1 monthly table
page(f"""
<h3 class="first">سال اول ماه‌به‌ماه — سناریوی پایه (میلیون تومان)</h3>
{y1_table()}
<p class="note">درآمدها در ماهِ ایجاد نشان داده شده‌اند؛ «جریان نقد» تأخیر یک‌ماههٔ تسویهٔ ایران و دوماههٔ پرداخت خارجی را دارد. موجودی نقد = اقساط دریافتی + جریان نقد تجمعی؛ در هیچ ماهی منفی نمی‌شود.</p>
{H(10, "حساسیت: کدام فرض بیشتر اثر دارد؟", "هر بار یک متغیر را در سناریوی پایه عوض کرده‌ایم. نمودار، تغییر سود (زیان) عملیاتی سال سوم را نشان می‌دهد (میلیون تومان).")}
<div class="card chartcard">
  <div class="legend"><span><i style="background:{C_CONS}"></i>بدتر از پایه</span><span><i style="background:{C_OPT}"></i>بهتر از پایه</span></div>
  {chart_tornado()}
</div>
""", 10)

# ---- page 11: sensitivity table + takeaways
s_best = sens["دوست در کشوری بدون مالیات (مثلاً امارات) و بدون سهم"]
s_e2 = sens["eCPM تپسل دو برابر (۵۲۰ هزار تومان)"]
s_o2 = sens["نصب ارگانیک ایرانی دو برابر"]
s_i2 = sens["نصب ارگانیک گوگل‌پلی و اپ‌استور دو برابر"]
s_ih = sens["نصب ارگانیک گوگل‌پلی و اپ‌استور نصف"]
s_ir = sens["فقط ایران: بدون گوگل‌پلی و اپ‌استور"]
s_blk = sens["حساب گوگل/اپل در ماه ۱۸ مسدود شود"]
s_nr = sens["درآمد دلاری هرگز به ایران نرسد؛ توقف در ماه ۱۲"]
s_ihg = sens["همان، با بستن بخش خارجی در گیت ماه ۱۲"]
s_eh = sens["eCPM تپسل نصف (۱۳۰ هزار تومان)"]
s_oh = sens["نصب ارگانیک ایرانی نصف"]
s_ihg_dau = rnd(M.summary(M.scenario("base", dict(gp=dict(O=1000), ase=dict(O=400), asf=dict(O=500))))["dau12_intl"], 10)
page(f"""
{sens_table()}
<p class="note">اعداد قرمز در ستون‌های اوج نیاز از سقف {bn(ASK)} میلیارد بیشترند. سال‌های ۴ و ۵ برون‌یابی است.</p>
<div class="box"><b>برداشت.</b>
(۱) <b>هر یک از سه اهرم اصلی اگر دو برابر شود</b> — نصب ارگانیک ایرانی، eCPM تپسل یا نصب ارگانیک خارجی — سودآوری از ماه {fa(first_b)} به ماه {fa(min(s_o2['first'], s_e2['first'], s_i2['first']))} تا {fa(max(s_o2['first'], s_e2['first'], s_i2['first']))} می‌آید و سرمایه پیش از ماه ۶۰ برمی‌گردد.
(۲) <b>شرایط همکار خارجی تنها اهرم بزرگی است که در اختیار خودمان است:</b> اگر او در کشوری بی‌مالیات (مثلاً امارات) باشد و سهمی نگیرد، سودآوری به ماه {fa(s_best['first'])} و اوج نیاز به {bn(s_best['peak60'],2)} میلیارد می‌رسد؛ قرارداد ماه ۱ برای نزدیک شدن به همین حالت مذاکره می‌شود.
(۳) <b>بخش خارجی ارزش دارد:</b> بدون آن، سناریوی پایه تا ماه {fa(s_ir['first'])} سودده نمی‌شود؛ با آن، از ماه {fa(first_b)}. اگر حساب ناشر مسدود شود یا پول به ایران نرسد، اوج نیاز در افق ۳۶ ماهه {bn(min(s_blk['peak'], s_nr['peak']),2)} تا {bn(max(s_blk['peak'], s_nr['peak']),2)} میلیارد و زیر سقف است، ولی سودآوری تا ماه ۵۸ عقب می‌رود.
(۴) <b>گیت‌ها سقف را نگه می‌دارند.</b> نصف شدن نصب ارگانیک خارجی بدون گیت نیاز ۶۰ ماهه را به {bn(s_ih['peak60'],1)} میلیارد می‌برد؛ با بستن بخش خارجی در گیت ماه ۱۲ (کاربر فعال خارجی {fa(s_ihg_dau)} به‌جای حداقل {fa(rnd(g12_intl_dau*0.9,50))}) نیاز ۳۶ ماهه {bn(s_ihg['peak'],2)} میلیارد می‌ماند. ضربه‌های ایرانی (eCPM تپسل یا نصب ارگانیک نصف) نیاز ۳۶ ماهه را به حدود {bn(max(s_eh['peak'], s_oh['peak']),1)} میلیارد می‌رسانند — هنوز در سقف — و درآمد ماه ۱۸ را به حدود ۶۵ میلیون می‌آورند؛ گیت ماه ۱۸ (حداقل {fa(rnd(g18_rev*0.95,5))} میلیون) پیش از قسط سوم کاهش هزینه را فعال می‌کند.</div>
""", 11)

# ---- page 12: roadmap + risks
page(f"""
{H(11, "نقشهٔ راه و ریسک‌ها")}
<div class="road">
  <div class="ph p1"><div class="ph-h">۱. راه‌اندازی و آزمون</div><div class="ph-m">ماه ۱–۶ · {jal(1)} تا {jal(6)}</div><ul><li>پرداخت، پیامک، TLS، تپسل زنده</li><li>انتشار بازار و مایکت (ماه ۱)</li><li>نسخهٔ بین‌المللی (ماه ۱–۴)</li><li>گوگل‌پلی ({jal(M.LAUNCH['gp'],False)})، اپ‌استور ({jal(M.LAUNCH['ase'],False)})</li><li>آزمون جذب ۶ ماهه</li></ul></div>
  <div class="gt">گیت<br>ماه ۶</div>
  <div class="ph p2"><div class="ph-h">۲. رشد</div><div class="ph-m">ماه ۷–۱۸ · تا {jal(18)}</div><ul><li>دست‌های «بهترین از ۵»، نشان‌ها</li><li>بهینه‌سازی صفحهٔ فروشگاه‌ها</li><li>تصمیم بخش خارجی (ماه ۱۲)</li><li>بازنگری فصلی قیمت‌ها</li></ul></div>
  <div class="gt">گیت<br>ماه ۱۸</div>
  <div class="ph p3"><div class="ph-h">۳. سودآوری</div><div class="ph-m">ماه ۱۹–۳۶ · تا {jal(36)}</div><ul><li>سودآوری ماهانه (پایه: {jal(first_b)})</li><li>جذب پولی اگر بصرفد</li><li>نفر دوم اگر درآمد اجازه دهد</li></ul></div>
</div>
{risk_table()}
""", 12)

# ---- page 13: appendix
page(f"""
{H(12, "پیوست: روش، تعریف‌ها و منابع")}
<div class="cols2">
<div class="card"><h3>روش مدل</h3>
<p>مدل ماهانه و کوهورتی است و چهار بخش (بازار و مایکت، گوگل‌پلی، اپ‌استور انگلیسی و فارسی) را جدا شبیه‌سازی می‌کند. نصب ماهانه = ارگانیک (رشد ٪۴ در ماه تا یک سال پس از انتشار، سپس ٪۲) + نصب پولی (بودجه ÷ هزینهٔ هر نصب × ضریب دعوت) + دهان‌به‌دهان (درصدی از نصب‌های تجمعی با ۳ ماه تأخیر). ماندگاری از روز ۱ و ۷ و ۳۰ درون‌یابی و پس از روز ۳۰ با دم توانی ادامه می‌یابد. کاربر فعال روزانه = جمع کوهورت‌ها × ماندگاری. درآمد = کاربر فعال × ۳۰ × درآمد روزانهٔ هر کاربر، پس از کسورات بخش ۲. هزینهٔ سرور ایران ≈ ۱۰ میلیون ثابت + ۰٫۳۳ به‌ازای هر ۱٬۰۰۰ کاربر فعال + ۰٫۱۹ به‌ازای هر ۱٬۰۰۰ نصب (پیامک). همهٔ مبالغ با قیمت ثابت مهر ۱۴۰۵ و دلار ۲۶۶٬۰۰۰ تومان (بازار آزاد، ۱۶ مهر ۱۴۰۵) است؛ تورم با کسورات بخش ۲ لحاظ شده، نه با افزایش اسمی.</p>
<p>هر عدد این سند مستقیماً از اجرای مدل می‌آید. جدول ماه‌به‌ماه ۶۰ ماههٔ هر سه سناریو (نصب، کاربر فعال و درآمد هر فروشگاه، اقلام هزینه، سود و جریان نقد) در فایل همراه <span class="ltr">zanjir-forecast-monthly.xlsx</span> آمده است.</p></div>
<div class="card"><h3>تعریف‌ها</h3>
<dl>
<dt>DAU / MAU</dt><dd>کاربر فعال روزانه / ماهانه.</dd>
<dt>ARPDAU</dt><dd>درآمد خالص روزانه به‌ازای هر کاربر فعال.</dd>
<dt>ماندگاری روز ۱ / ۷ / ۳۰</dt><dd>درصد نصب‌کنندگانی که در آن روز بازی می‌کنند.</dd>
<dt>هزینهٔ جذب (CPI)</dt><dd>هزینهٔ تبلیغ برای هر نصب.</dd>
<dt>ارزش عمر (LTV)</dt><dd>درآمد خالص یک نصب در ۳۶۵ روز اول.</dd>
<dt>eCPM</dt><dd>درآمد ناشر به‌ازای هر ۱٬۰۰۰ نمایش تبلیغ.</dd>
<dt>گیت</dt><dd>نقطهٔ تصمیم با شاخص‌های عددی؛ قسط بعدی فقط با رسیدن به آن‌ها پرداخت می‌شود.</dd>
<dt>سودده</dt><dd>سه ماه پیاپی درآمد خالص ≥ هزینه.</dd>
</dl></div>
</div>
<div class="card src"><h3>منابع</h3><ul>
<li>کافه‌بازار، گزارش سالانهٔ ۱۴۰۲ (زومیت)؛ کاهش کمیسیون بازار به ٪۱۵ برای فروش زیر ۱ میلیارد تومان از خرداد ۱۴۰۰ (زومیت). صفحه‌های آمیرزا، کوییز آف کینگز و شهرزاد در کافه‌بازار (مهر ۱۴۰۵).</li>
<li>نرخ مالیات بر ارزش افزودهٔ ۱۴۰۵: ٪۱۲ (زرین‌پال، رده). تورم ایران ۲۰۲۶: مرکز آمار به نقل Intellinews و NST؛ IMF.</li>
<li>قطعی اینترنت ایران در ۲۰۲۶ (دی و اسفند ۱۴۰۴ تا خرداد ۱۴۰۵): ویکی‌پدیا، Filterwatch، ASL19.</li>
<li>کاربران آیفون در ایران: اقتصادنیوز و گجت‌نیوز (برآورد، بدون آمار رسمی). ایرانیان خارج از کشور: برآورد رسمی ۱۴۰۰ به نقل ویکی‌پدیا.</li>
<li>کارمزد گوگل‌پلی ۲۰۲۶ پس از توافق با Epic: MacRumors، The Verge. برنامهٔ کسب‌وکار کوچک اپل: developer.apple.com.</li>
<li>eCPM: Appodeal Quarterly eCPM Report Q4 2024؛ playio.co؛ Global Games Forum. هزینهٔ جذب بازی پازل: click-vision، mapendo (۲۰۲۵). ماندگاری: AppsFlyer.</li>
<li>Word Chain (Tribom): apppricinglab؛ بازی‌های زنجیرهٔ حرف آخر در اپ‌استور: apps.apple.com. حذف برنامه‌های ایرانی از اپ‌استور به‌خاطر تحریم: ۱۳۹۶ (CNBC و دیگران).</li>
<li>نرخ دلار: بازار آزاد، ۱۶ مهر ۱۴۰۵ (اقتصادآنلاین). همهٔ پیش‌بینی‌ها محاسبهٔ داخلی بر پایهٔ مفروضات بخش‌های ۲ و ۶ است و تضمین عملکرد نیست.</li>
</ul></div>
""", 13)

# ------------------------------------------------------------------ CSS
CSS = f"""
@font-face {{ font-family:Vazirmatn; font-weight:400; src:url('file://{FONTS}/Vazirmatn-Regular.ttf'); }}
@font-face {{ font-family:Vazirmatn; font-weight:500; src:url('file://{FONTS}/Vazirmatn-Medium.ttf'); }}
@font-face {{ font-family:Vazirmatn; font-weight:600; src:url('file://{FONTS}/Vazirmatn-SemiBold.ttf'); }}
@font-face {{ font-family:Vazirmatn; font-weight:700; src:url('file://{FONTS}/Vazirmatn-Bold.ttf'); }}
@font-face {{ font-family:Vazirmatn; font-weight:800; src:url('file://{FONTS}/Vazirmatn-ExtraBold.ttf'); }}
@font-face {{ font-family:Vazirmatn; font-weight:900; src:url('file://{FONTS}/Vazirmatn-Black.ttf'); }}
:root {{ --paper:#F6F1E7; --surface:#FFFFFF; --line:#E3DCCC; --wash:#F0EBE0; --ink:#1E1B2E; --ink60:#6B6780; --ink40:#8B8798;
  --indigo:#4C5FE0; --indigoDeep:#3546B8; --teal:#16A38F; --tealDeep:#0E8071; --amber:#F5A524; --amberDeep:#C97F0C;
  --coral:#EF4B3C; --coralDeep:#C22E22; --tI:#E7EAFD; --tT:#E1F4F0; --tC:#FDEAE7; --tA:#FDF1DC; }}
@page {{ size:210mm 297mm; margin:0; }}
* {{ box-sizing:border-box; -webkit-print-color-adjust:exact; print-color-adjust:exact; }}
html {{ direction:rtl; }}
body {{ margin:0; font-family:Vazirmatn,sans-serif; color:var(--ink); font-size:9pt; line-height:1.7; background:var(--paper); }}
.page {{ width:210mm; height:296.8mm; background:var(--paper); position:relative; overflow:hidden; page-break-after:always; }}
.page:last-child {{ page-break-after:auto; }}
.pg {{ padding:11mm 12mm 0; }}
footer {{ position:absolute; bottom:6mm; left:12mm; right:12mm; display:flex; justify-content:space-between; font-size:7pt; color:var(--ink40); border-top:1px solid var(--line); padding-top:2mm; }}
.ltr {{ direction:ltr; unicode-bidi:isolate; white-space:nowrap; }}
p {{ margin:3px 0 5px; text-align:justify; }}
.lead {{ margin:0 0 7px; }}
b {{ font-weight:700; }}
.hero {{ background:var(--ink); color:#fff; border-radius:18px; padding:20px 24px; display:flex; align-items:center; justify-content:space-between; gap:18px; position:relative; overflow:hidden; box-shadow:0 4px 0 var(--indigoDeep); }}
.hero:before {{ content:""; position:absolute; width:210px; height:210px; border-radius:50%; background:var(--indigo); opacity:.35; left:-60px; top:-90px; }}
.hero:after {{ content:""; position:absolute; width:160px; height:160px; border-radius:50%; background:var(--teal); opacity:.28; left:120px; bottom:-110px; }}
.hero-txt {{ position:relative; z-index:1; }}
.eyebrow {{ font-size:8.4pt; color:#C9D0FA; font-weight:600; }}
h1 {{ font-size:40pt; font-weight:900; margin:2px 0 0; line-height:1.15; }}
.tag {{ font-size:12pt; font-weight:600; margin-top:2px; }}
.meta {{ font-size:7.6pt; color:#9F9BB0; margin-top:8px; }}
.logo {{ width:112px; height:112px; border-radius:24px; position:relative; z-index:1; box-shadow:0 4px 0 #0C0A16; flex:none; }}
.kpis {{ display:grid; grid-template-columns:repeat(4,1fr); gap:9px; margin:12px 0 10px; }}
.kpi {{ background:var(--surface); border:1px solid var(--line); border-radius:12px; padding:8px 11px; box-shadow:0 3px 0 var(--line); }}
.kpi b {{ display:block; font-size:14pt; font-weight:900; line-height:1.35; }}
.kpi span {{ font-size:7.3pt; color:var(--ink60); line-height:1.5; display:block; }}
.sec {{ display:flex; align-items:center; gap:9px; margin:8px 0 6px; }}
.badge {{ background:var(--indigo); color:#fff; width:26px; height:26px; border-radius:8px; display:inline-flex; align-items:center; justify-content:center; font-weight:800; font-size:11pt; box-shadow:0 3px 0 var(--indigoDeep); flex:none; }}
h2 {{ font-size:16pt; font-weight:900; margin:0; }}
h3 {{ font-size:9.8pt; font-weight:800; margin:9px 0 4px; color:var(--indigoDeep); }}
h3.first {{ margin-top:0; }}
h3.mt {{ margin-top:10px; }}
.tw {{ background:var(--surface); border:1px solid var(--line); border-radius:12px; overflow:hidden; margin:5px 0 6px; box-shadow:0 3px 0 var(--line); }}
table {{ width:100%; border-collapse:collapse; font-size:7.9pt; table-layout:fixed; }}
th {{ background:var(--ink); color:#fff; font-weight:600; padding:5px 7px; text-align:right; line-height:1.45; }}
td {{ padding:3.6px 7px; border-top:1px solid var(--line); vertical-align:top; line-height:1.55; }}
tr:nth-child(even) td {{ background:#FBF8F2; }}
table.num td:not(:first-child), table.num th:not(:first-child) {{ text-align:center; }}
tr.tot td {{ font-weight:800; background:var(--wash) !important; }}
tr.hl td {{ font-weight:800; background:var(--tI) !important; }}
tr.first td {{ border-top:2px solid var(--ink40); }}
table.ann td:nth-child(1) {{ font-weight:800; }}
.neg {{ color:var(--coralDeep); font-weight:700; }}
.pos {{ color:var(--tealDeep); font-weight:700; }}
.mut {{ color:var(--ink40); font-size:6.9pt; }}
table.worst td:first-child, table.comp td:first-child, table.risk td:first-child, table.streams td:first-child {{ font-weight:700; }}
table.worst td:last-child {{ font-weight:600; color:var(--indigoDeep); }}
table.txt td {{ font-size:7.5pt; }}
.note {{ font-size:7pt; color:var(--ink60); line-height:1.55; margin:2px 0 6px; }}
.box {{ background:var(--surface); border:1px solid var(--line); border-right:5px solid var(--indigo); border-radius:10px; padding:7px 11px; margin:7px 0; font-size:8.2pt; box-shadow:0 3px 0 var(--line); text-align:justify; }}
.box.good {{ border-right-color:var(--teal); background:var(--tT); }}
.keys {{ margin:6px 0 0; padding-right:16px; }}
.keys li {{ margin:3px 0; }}
ul {{ margin:3px 0; padding-right:15px; }} li {{ margin:2px 0; }}
.cols2 {{ display:grid; grid-template-columns:1fr 1fr; gap:10px; }}
.card {{ background:var(--surface); border:1px solid var(--line); border-radius:12px; padding:8px 12px; box-shadow:0 3px 0 var(--line); }}
.card h3 {{ margin-top:2px; }}
.card ul li {{ font-size:8pt; }}
.stacks {{ display:grid; grid-template-columns:1fr; gap:8px; }}
.stack {{ background:var(--surface); border:1px solid var(--line); border-radius:12px; padding:8px 12px; box-shadow:0 3px 0 var(--line); }}
.stack.ir {{ border-right:5px solid var(--indigo); }}
.stack.intl {{ border-right:5px solid var(--teal); }}
.st-h {{ font-weight:800; font-size:9pt; margin-bottom:5px; display:flex; align-items:center; gap:5px; }}
.dot {{ width:10px; height:10px; border-radius:3px; display:inline-block; }}
.flow {{ display:flex; align-items:center; gap:5px; flex-wrap:wrap; margin-bottom:4px; }}
.node {{ background:var(--wash); border:1px solid var(--line); border-radius:8px; padding:3px 9px; font-size:7.8pt; font-weight:600; }}
.node.acc {{ background:var(--ink); color:#fff; border-color:var(--ink); }}
.arr {{ color:var(--ink40); font-weight:800; }}
.stack p {{ font-size:7.8pt; margin:2px 0 0; }}
.stats {{ display:grid; grid-template-columns:repeat(3,1fr); gap:8px; margin:4px 0 6px; }}
.stat {{ background:var(--surface); border:1px solid var(--line); border-radius:12px; padding:7px 11px; box-shadow:0 3px 0 var(--line); }}
.stat b {{ display:block; font-size:13pt; font-weight:900; color:var(--indigoDeep); line-height:1.4; }}
.stat:nth-child(3n+2) b {{ color:var(--tealDeep); }}
.stat:nth-child(3n) b {{ color:var(--amberDeep); }}
.stat span {{ font-size:7.2pt; color:var(--ink60); line-height:1.45; display:block; }}
.chart {{ width:100%; height:auto; display:block; }}
.chart .ax {{ font-size:10px; fill:var(--ink60); font-family:Vazirmatn; }}
.chart .lbl {{ font-size:10.5px; font-weight:700; font-family:Vazirmatn; }}
.chartcard {{ padding:8px 12px 2px; margin:4px 0 6px; }}
.ct {{ font-weight:800; font-size:9pt; margin-bottom:2px; }}
.legend {{ display:flex; gap:14px; font-size:7.6pt; color:var(--ink60); margin:2px 0; flex-wrap:wrap; }}
.legend i {{ display:inline-block; width:10px; height:10px; border-radius:3px; margin-left:4px; vertical-align:-1px; }}
.legend i.ln {{ height:3px; width:14px; vertical-align:2px; }}
.tranches {{ display:grid; grid-template-columns:repeat(3,1fr); gap:9px; margin:2px 0 8px; }}
.tr {{ background:var(--surface); border:1px solid var(--line); border-radius:12px; padding:8px 11px; box-shadow:0 3px 0 var(--line); border-top:5px solid var(--indigo); }}
.tr.t2 {{ border-top-color:var(--teal); }} .tr.t3 {{ border-top-color:var(--amberDeep); }}
.tr-h {{ font-weight:900; font-size:11pt; }}
.tr-m {{ font-size:7.4pt; color:var(--ink60); font-weight:600; }}
.tr p {{ font-size:7.7pt; margin:4px 0 0; }}
.gates {{ display:grid; grid-template-columns:repeat(3,1fr); gap:9px; margin-bottom:6px; }}
.gate {{ background:var(--tI); border:1px solid #C9D0FA; border-radius:12px; padding:7px 10px; }}
.g-h {{ font-weight:800; font-size:8.4pt; color:var(--indigoDeep); margin-bottom:2px; }}
.gate li {{ font-size:7.4pt; line-height:1.5; }}
.mini {{ background:var(--wash); border-radius:4px; height:9px; margin-top:4px; }}
.mini i {{ display:block; height:9px; background:var(--indigo); border-radius:4px; }}
.road {{ display:flex; align-items:stretch; gap:6px; margin:4px 0 8px; }}
.ph {{ flex:1; background:var(--surface); border:1px solid var(--line); border-radius:12px; padding:8px 11px; box-shadow:0 3px 0 var(--line); border-top:5px solid var(--indigo); }}
.ph.p2 {{ border-top-color:var(--teal); }} .ph.p3 {{ border-top-color:var(--amberDeep); }}
.ph-h {{ font-weight:900; font-size:10pt; }}
.ph-m {{ font-size:7.3pt; color:var(--ink60); font-weight:600; }}
.ph li {{ font-size:7.6pt; }}
.gt {{ align-self:center; background:var(--ink); color:#fff; border-radius:10px; padding:6px 7px; font-size:7.4pt; font-weight:800; text-align:center; line-height:1.4; }}
dl {{ margin:0; font-size:7.8pt; }} dt {{ font-weight:800; float:right; margin-left:6px; }} dd {{ margin:0 0 3px; }}
.src li {{ font-size:7.5pt; }}
.chainbox {{ background:var(--surface); border:1px solid var(--line); border-radius:12px; padding:10px 14px 6px; box-shadow:0 3px 0 var(--line); margin-bottom:9px; }}
.chain {{ display:flex; justify-content:center; align-items:center; margin:2px 0 6px; }}
.wt {{ color:#fff; font-weight:900; font-size:13pt; padding:3px 15px 5px; border-radius:11px; border:2px solid var(--ink); box-shadow:0 3px 0 var(--ink); }}
.wt.c1 {{ background:var(--indigo); }} .wt.c2 {{ background:var(--teal); }} .wt.c3 {{ background:var(--amber); color:var(--ink); }} .wt.c4 {{ background:var(--coral); }}
.lk {{ background:#F6E7C8; border:2px solid var(--ink); border-radius:12px; font-weight:900; font-size:9pt; min-width:30px; height:22px; display:inline-flex; align-items:center; justify-content:center; margin:0 -5px; position:relative; z-index:2; }}
.chainbox p {{ font-size:8.2pt; margin:0; text-align:center; color:var(--ink60); }}
"""

html = f"""<!doctype html><html lang="fa" dir="rtl"><head><meta charset="utf-8">
<title>زنجیر — طرح درآمدی و پیش‌بینی مالی</title><style>{CSS}</style></head><body>{"".join(PAGES)}
<script>window.addEventListener('load',()=>{{document.querySelectorAll('.page').forEach(p=>{{const g=p.querySelector('.pg').getBoundingClientRect();const f=p.querySelector('footer').getBoundingClientRect();p.setAttribute('data-fill',Math.round((g.bottom-g.top)/(f.top-g.top-4)*100));}});}});</script></body></html>"""

html_path = os.path.join(OUT, "zanjir-investor-plan-fa-final.html")
open(html_path, "w").write(html)
pdf_path = os.path.join(OUT, "zanjir-investor-plan-fa-final.pdf")
subprocess.run(["google-chrome", "--headless=new", "--no-sandbox", "--disable-gpu", "--allow-file-access-from-files",
                "--no-pdf-header-footer", f"--print-to-pdf={pdf_path}", "file://" + html_path], check=True,
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
print("wrote", pdf_path, "pages:", len(PAGES))
