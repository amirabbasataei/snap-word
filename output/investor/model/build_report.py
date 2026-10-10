"""Builds zanjir-investor-plan-fa-v2.html / .pdf from the model (run zanjir_model.py first or let this import it)."""
import os, subprocess, json
import zanjir_model as M

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.dirname(HERE)
FONTS = os.path.abspath(os.path.join(HERE, "../../../client/assets/fonts"))

res = M.main()
FX = M.FX
S = M.SCEN
FA_NAME = M.SCEN_FA

# ------------------------------------------------------------------ formatting
DIG = str.maketrans("0123456789", "۰۱۲۳۴۵۶۷۸۹")


def fa(x, d=0):
    s = f"{abs(x):,.{d}f}".replace(",", "٬").replace(".", "٫")
    return s.translate(DIG)


def sg(x, d=0):          # accounting style: losses in parentheses
    x = round(x, d)
    return f"({fa(x, d)})" if x < 0 else fa(x, d)


def fn(s):               # plain text digits -> Persian digits
    return str(s).translate(DIG)


def bn(x, d=1):          # million toman -> billion toman
    return fa(x / 1000, d)


def usd(mt, d=0):        # million toman -> USD string
    return fa(mt * 1e6 / FX, d)


LTR = lambda s: f'<bdi class="ltr">{s}</bdi>'

# ------------------------------------------------------------------ data pulls
R = {s: M.scenario(s) for s in S}
R0 = {s: M.scenario(s, en_on=False) for s in S}
SM = {s: res[s] for s in S}
V1 = M.V1
# v1 published extras (from the PDF)
V1X = {
    "cons": dict(inst36=281679, dau3=3755, rev3=187, net3=-1468, cum36=-4376, first="ندارد"),
    "base": dict(inst36=500581, dau3=9619, rev3=1385, net3=-305, cum36=-2061, first="ماه ۳۹ (برون‌یابی)"),
    "opt": dict(inst36=1889032, dau3=51960, rev3=16602, net3=12749, cum36=21427, first="ماه ۶"),
}
b = SM["base"]
fa_inst6 = float(R["base"]["fa"]["inst"][:6].sum())
en_inst6 = float(R["base"]["en"]["inst"][:6].sum())
fa_dau6 = float(R["base"]["fa"]["dau"][5])
en_dau6 = float(R["base"]["en"]["dau"][5])
cum6 = -b["cum6"]
peak = b["peak_need"]
ASK_STAGE1 = 1400.0
ASK_TOTAL = 2600.0
ASK_STAGE2 = ASK_TOTAL - ASK_STAGE1
en_share3 = b["rev_en"][2] / b["rev"][2] * 100
fp = lambda v: ("ندارد" if v is None else (f"ماه {fn(v)}" if v <= 36 else f"ماه {fn(v)} (برون‌یابی)"))

# ------------------------------------------------------------------ SVG charts
def zf(x, d=0):          # signed number, minus in front, for LTR contexts
    return ("\u2212" if round(x, d) < 0 else "") + fa(x, d)


def chart_cash():
    W, H_, pl, pr, pt, pb = 760, 290, 50, 14, 14, 30
    ymin, ymax = -8000, 6000
    pw, ph = W - pl - pr, H_ - pt - pb
    X = lambda m: W - pr - (m / 36) * pw           # RTL: month 0 at the right
    Y = lambda v: pt + (ymax - max(min(v, ymax), ymin)) / (ymax - ymin) * ph
    g = []
    for v in range(-8000, 7000, 2000):
        g.append(f'<line x1="{pl}" x2="{W-pr}" y1="{Y(v):.1f}" y2="{Y(v):.1f}" class="grid{" zero" if v==0 else ""}"/>')
        g.append(f'<text x="{pl-8}" y="{Y(v)+4:.1f}" class="ax" text-anchor="end">{zf(v/1000)}</text>')
    for m in range(0, 37, 6):
        g.append(f'<text x="{X(m):.1f}" y="{H_-pb+16}" class="ax" text-anchor="middle">{fa(m)}</text>')
    g.append(f'<line x1="{pl}" x2="{W-pr}" y1="{Y(-ASK_TOTAL):.1f}" y2="{Y(-ASK_TOTAL):.1f}" class="ask"/>')
    cols = {"cons": "var(--c3)", "base": "var(--c1)", "opt": "var(--c2)"}
    for s_ in S:
        cum = [0] + SM[s_]["series"]["cum"][:36]
        pts = " ".join(f"{X(m):.1f},{Y(cum[m]):.1f}" for m in range(37))
        g.append(f'<polyline points="{pts}" class="ln" style="stroke:{cols[s_]}"/>')
    cum0 = [0] + SM["base"]["series"]["cum_fa_only"][:36]
    pts = " ".join(f"{X(m):.1f},{Y(cum0[m]):.1f}" for m in range(37))
    g.append(f'<polyline points="{pts}" class="ln dash" style="stroke:var(--mut)"/>')
    svg = f'<svg viewBox="0 0 {W} {H_}" class="chart" direction="ltr">{"".join(g)}</svg>'
    def sw(color, label, val, dash=False):
        st = f"background:{color}" if not dash else f"border-top:3px dashed {color};height:0"
        return f'<span class="lg"><i style="{st}"></i>{label}: <b>{LTR(val)}</b></span>'
    leg = '<div class="legend">' + "".join([
        sw("var(--c3)", "محافظه‌کارانه", zf(SM["cons"]["cum36"] / 1000, 1)),
        sw("var(--c1)", "پایه", zf(SM["base"]["cum36"] / 1000, 1)),
        sw("var(--c2)", "خوش‌بینانه (ادامه تا بالاتر از کادر)", "+" + fa(SM["opt"]["cum36"] / 1000, 1)),
        sw("var(--mut)", "پایه، فقط ایرانی", zf(SM["base"]["fa_only"]["cum36"] / 1000, 1), True),
        sw("var(--c4)", "سقف سرمایهٔ درخواستی", "\u2212" + fa(ASK_TOTAL / 1000, 1), True),
    ]) + '</div>'
    return leg + svg


def chart_monthly():
    W, H_, pl, pr, pt, pb = 760, 270, 54, 20, 14, 40
    ymax = 320
    pw, ph = W - pl - pr, H_ - pt - pb
    X = lambda m: W - pr - ((m - 1) / 35) * pw
    Y = lambda v: pt + (ymax - min(v, ymax)) / ymax * ph
    se = SM["base"]["series"]
    fa_r, en_r, cost = se["rev_fa"][:36], se["rev_en"][:36], se["cost"][:36]
    g = []
    for v in range(0, 321, 80):
        g.append(f'<line x1="{pl}" x2="{W-pr}" y1="{Y(v):.1f}" y2="{Y(v):.1f}" class="grid"/>')
        g.append(f'<text x="{pl-8}" y="{Y(v)+4:.1f}" class="ax" text-anchor="end">{fa(v)}</text>')
    for m in [1, 6, 12, 18, 24, 30, 36]:
        g.append(f'<text x="{X(m):.1f}" y="{H_-pb+18}" class="ax" text-anchor="middle">{fa(m)}</text>')
    # stacked area: persian bottom, english top
    top = [fa_r[i] + en_r[i] for i in range(36)]
    ms = list(range(1, 37))
    p1 = " ".join(f"{X(m):.1f},{Y(fa_r[m-1]):.1f}" for m in ms) + f" {X(36):.1f},{Y(0):.1f} {X(1):.1f},{Y(0):.1f}"
    p2 = " ".join(f"{X(m):.1f},{Y(top[m-1]):.1f}" for m in ms) + " " + " ".join(f"{X(m):.1f},{Y(fa_r[m-1]):.1f}" for m in reversed(ms))
    g.append(f'<polygon points="{p1}" style="fill:var(--c1);opacity:.55"/>')
    g.append(f'<polygon points="{p2}" style="fill:var(--c4);opacity:.65"/>')
    pc = " ".join(f"{X(m):.1f},{Y(cost[m-1]):.1f}" for m in ms)
    g.append(f'<polyline points="{pc}" class="ln" style="stroke:var(--c3)"/>')
    fp_m = SM["base"]["first_profit"]
    if fp_m:
        g.append(f'<line x1="{X(fp_m):.1f}" x2="{X(fp_m):.1f}" y1="{pt}" y2="{H_-pb}" class="ask"/>')
        g.append(f'<text x="{X(fp_m)-6:.1f}" y="{pt+12}" class="lbl" text-anchor="end">اولین ماه سودده: ماه {fa(fp_m)}</text>')
    g.append(f'<text x="{X(34):.1f}" y="{Y(cost[34])-8:.1f}" class="lbl" fill="var(--c3)">هزینهٔ ماهانه</text>')
    g.append(f'<text x="{X(12):.1f}" y="{Y(top[11])-10:.1f}" class="lbl" fill="var(--c4)">درآمد انگلیسی (گوگل‌پلی)</text>')
    g.append(f'<text x="{X(10):.1f}" y="{Y(fa_r[9]/2):.1f}" class="lbl" fill="var(--c1)">درآمد ایرانی</text>')
    g.append(f'<text x="{W-pr}" y="{H_-4}" class="ax" text-anchor="end">ماه (راست به چپ)</text>')
    return f'<svg viewBox="0 0 {W} {H_}" class="chart" direction="ltr">{"".join(g)}</svg>'


# ------------------------------------------------------------------ tables
def tbl(head, rows, cls="", first_left=False):
    h = "".join(f"<th>{c}</th>" for c in head)
    body = ""
    for r in rows:
        if isinstance(r, dict):
            body += f'<tr class="{r["cls"]}">' + "".join(f"<td>{c}</td>" for c in r["c"]) + "</tr>"
        else:
            body += "<tr>" + "".join(f"<td>{c}</td>" for c in r) + "</tr>"
    return f'<table class="{cls}"><thead><tr>{h}</tr></thead><tbody>{body}</tbody></table>'


def summary_table():
    head = ["شاخص (۳۶ ماه)", "محافظه‌کارانه", "پایه", "خوش‌بینانه"]
    def row(label, f_v1, f_v2):
        return [
            {"cls": "v1", "c": [f"{label} — نسخهٔ ۱ (فقط ایرانی)"] + [f_v1(s) for s in S]},
            {"cls": "v2", "c": [f"{label} — نسخهٔ ۲ (ایرانی + انگلیسی)"] + [f_v2(s) for s in S]},
        ]
    rows = []
    rows += row("مجموع نصب", lambda s: fa(V1X[s]["inst36"]), lambda s: fa(sum(SM[s]["inst"])))
    rows += row("DAU پایان سال ۳", lambda s: fa(V1X[s]["dau3"]), lambda s: fa(SM[s]["dau_end"][2]))
    rows += row("درآمد سال ۳ (میلیون تومان)", lambda s: fa(V1X[s]["rev3"]), lambda s: fa(SM[s]["rev"][2]))
    rows += row("خالص سال ۳ (میلیون تومان)", lambda s: sg(V1X[s]["net3"]), lambda s: sg(SM[s]["net"][2]))
    rows += row("مانده نقدی تجمعی ماه ۳۶ (میلیون)", lambda s: sg(V1X[s]["cum36"]), lambda s: sg(SM[s]["cum36"]))
    rows += row("اولین ماه سودده", lambda s: V1X[s]["first"], lambda s: fp(SM[s]["first_profit"]))
    return tbl(head, rows, "sum")


def annual_table():
    head = ["سناریو", "سال", "نصب (ایرانی / انگلیسی)", "DAU پایان سال (ایرانی / انگلیسی)", "درآمد ایرانی", "درآمد انگلیسی", "هزینهٔ کل", "خالص"]
    rows = []
    for s in S:
        m = SM[s]
        for y in range(3):
            rows.append([FA_NAME[s] if y == 0 else "", f"سال {fa(y+1)}",
                         f"{fa(m['inst_fa'][y])} / {fa(m['inst_en'][y])}",
                         f"{fa(m['dau_fa'][y])} / {fa(m['dau_en'][y])}",
                         fa(m["rev_fa"][y]), fa(m["rev_en"][y]), fa(m["cost"][y]), sg(m["net"][y])])
    return tbl(head, rows, "ann")


def arpdau_table():
    head = ["", "ایرانی (تپسل + بازار/مایکت)", "انگلیسی (ادموب + گوگل‌پلی)"]
    rows = []
    for s in S:
        m = SM[s]
        fa_p, en_p = m["fa_arpdau_parts"], m["en_arpdau_parts"]
        rows.append([f"{FA_NAME[s]} — ARPDAU (تومان)", f"{fa(m['fa_arpdau'])} (≈ {fa(m['fa_arpdau']/FX,4)} دلار)",
                     f"{fa(m['en_arpdau'])} (≈ {fa(m['en_arpdau']/FX,4)} دلار)"])
        rows.append([f"&nbsp;&nbsp;تبلیغ / خرید / اشتراک", f"{fa(fa_p[0])} / {fa(fa_p[1])} / {fa(fa_p[2])}",
                     f"{fa(en_p[0])} / {fa(en_p[1])} / {fa(en_p[2])}"])
        rows.append([f"&nbsp;&nbsp;LTV ۳۶۵ روزه ÷ CPI", f"{fa(m['fa_ltv_cpi'],2)}", f"{fa(m['en_ltv_cpi'],2)}"])
    return tbl(head, rows, "ar")


def geo_table():
    head = ["بازار تبلیغ‌شونده", "سهم از نمایش", "eCPM تبلیغ جایزه‌ای (دلار)", "سهم از eCPM"]
    out = ""
    for s in S:
        rows = []
        tot = 0
        for name, sh, e in M.EN_GEO[s]:
            rows.append([name, f"٪{fa(sh*100)}", fa(e, 2), fa(sh * e, 2)])
            tot += sh * e
        rows.append({"cls": "tot", "c": [f"جمع — {FA_NAME[s]}", "٪۱۰۰", "", fa(tot, 2)]})
        out += tbl(head, rows, "geo") if s == "base" else ""
    return out


def assumptions_table():
    head = ["فرض (نسخهٔ انگلیسی)", "محافظه‌کارانه", "پایه", "خوش‌بینانه"]
    E = M.EN
    def r(label, f): return [label] + [f(E[s]) for s in S]
    rows = [
        r("نصب ارگانیک ماه اول (رشد ٪۴ در ماه تا ماه ۱۲، سپس ٪۲)", lambda e: fa(e["O"])),
        r("هزینهٔ جذب هر نصب پولی (CPI)، دلار (معادل تومان)", lambda e: f"{fa(e['CPI'],2)} ({fa(e['CPI']*FX)})"),
        r("نصب اضافه به‌ازای هر نصب پولی (دعوت)", lambda e: fa(e["viral"], 2)),
        r("نصب دهان‌به‌دهان در ماه (٪ از نصب‌های تجمعی، با ۳ ماه تأخیر)", lambda e: f"٪{fa(e['w']*100,2)}"),
        r("ماندگاری روز ۱ / ۷ / ۳۰", lambda e: " / ".join("٪" + fa(x * 100, 1 if x * 100 % 1 else 0) for x in e["ret"])),
        r("نمایش تبلیغ جایزه‌ای به‌ازای هر DAU در روز", lambda e: fa(e["imps"], 1)),
        r("eCPM ادموب (جایزه‌ای)، دلار — با آمیختهٔ جغرافیایی جدول بعد", lambda e: fa(e["ecpm"], 2)),
        r("خریداران سکه (٪ از MAU در ماه) / خرج هر خریدار، دلار", lambda e: f"٪{fa(e['buy']*100,1)} / {fa(e['spend'],0)}"),
        r("مشترک پریمیوم (٪ از MAU) با قیمت ۲٫۹۹ دلار در ماه", lambda e: f"٪{fa(e['prem']*100,2)}"),
    ]
    rows += [["کارمزد گوگل‌پلی (خرید و اشتراک)", "٪۱۵", "٪۱۵", "٪۱۵"],
             ["کاهش هنگام انتقال دلار به تومان (فرض، تأییدنشده)", "٪۵", "٪۵", "٪۵"],
             ["شروع درآمد خرید درون‌برنامه‌ای", "ماه ۳", "ماه ۳", "ماه ۳"],
             ["نسبت DAU به MAU", "۰٫۲۲", "۰٫۲۲", "۰٫۲۲"]]
    return tbl(head, rows, "as")


def sens_table():
    head = ["تغییر نسبت به سناریوی پایهٔ ترکیبی", "خالص سال ۳", "خالص ماه ۳۶", "اولین ماه سودده", "اوج نیاز نقدی"]
    rows = []
    for i, r in enumerate(res["sens"]):
        rows.append({"cls": "tot" if i == 0 else "", "c": [r["label"], sg(r["net3"]), sg(r["net_m36"]), fp(r["first"]), fa(r["peak"])]})
    return tbl(head, rows, "sens")


def cost_table():
    c = SM["base"]["cost_split24"]
    tot = c["total"]
    rev24 = SM["base"]["rev24"]
    en_rev24 = float(R["base"]["en"]["rev"][:24].sum())
    items = [
        ("مؤسس (۱ نفر فول‌استک)", c["founder"], "ایرانی + مشترک"),
        ("خدمات بیرونی — ایرانی (طراحی، محتوا، حسابداری، حقوقی)", c["outsource_fa"], "ایرانی"),
        ("جذب کاربر — ایرانی", c["ua_fa"], "ایرانی"),
        ("سرور، دامنه، پیامک و اعلان — ایرانی", c["infra_fa"], "ایرانی"),
        ("شرکت/حساب خارجی: نگهداری، حسابداری، بانک (≈۱۰۰ دلار در ماه)", c["en_entity"], "انگلیسی"),
        ("میزبانی خارجی + بار متغیر (≈۶۰ دلار در ماه + سهم DAU)", c["en_hosting"], "انگلیسی"),
        ("خدمات بیرونی — انگلیسی (ASO، متن استور، جامعه، پشتیبانی؛ ≈۱۵۰ دلار)", c["en_outsource"], "انگلیسی"),
        ("جذب کاربر انگلیسی: آزمایش ۶ ماهه برای سنجش LTV/CPI (≈۹۵ دلار در ماه)", c["en_ua"], "انگلیسی"),
    ]
    rows = [[n, fa(v), f"٪{fa(v/tot*100)}"] for n, v, _ in items]
    rows.append({"cls": "tot", "c": ["جمع هزینه (۲۴ ماه اول، پایه)", fa(tot), "٪۱۰۰"]})
    rows.append(["درآمد در همین مدت (ایرانی + انگلیسی)", fa(rev24), ""])
    rows.append(["&nbsp;&nbsp;که انگلیسی", fa(en_rev24), ""])
    rows.append({"cls": "tot", "c": ["نیاز نقدی خالص از سرمایه‌گذار تا ماه ۲۴", fa(tot - rev24), ""]})
    return tbl(["هزینه (۲۴ ماه اول، سناریوی پایه)", "میلیون تومان", "سهم"], rows, "cost")


# ------------------------------------------------------------------ reconcile table
def reconcile_table():
    head = ["سناریو", "شاخص", "نسخهٔ ۱ (منتشرشده)", "بازسازی در نسخهٔ ۲", "اختلاف"]
    rows = []
    rc = res["reconcile"]
    for s in S:
        v, a = V1[s], rc[s]
        for key, lab in (("inst", "نصب سال ۳"), ("dau", "DAU پایان سال ۳"), ("rev", "درآمد سال ۳"), ("cost", "هزینهٔ سال ۳")):
            idx = 2
            rows.append([FA_NAME[s] if key == "inst" else "", lab, fa(v[key][idx]), fa(a[key][idx]), f"{'+' if a[key][idx] >= v[key][idx] else '−'}٪{fa(abs(a[key][idx]/v[key][idx]-1)*100)}"])
        rows.append(["", "مانده نقدی تجمعی ماه ۳۶", sg(V1X[s]["cum36"]), sg(a["cum36"]), ""])
    return tbl(head, rows, "rec")


# ------------------------------------------------------------------ HTML
fa_only = SM["base"]["fa_only"]
head_comb = SM["base"]
en_cost_extra_y1 = SM["base"]["cost"][0] - fa_only["cost"][0]
sens = {r["label"]: r for r in res["sens"]}
S_PUB = sens["انتشار از طریق ناشر خارجی (٪۳۰ سهم ناشر، بدون شرکت و میزبان خارجی)"]
S_BLOCK = sens["انتقال درآمد دلاری ممکن نشد: ۶ ماه هزینه، بدون درآمد، توقف"]
S_BOTH = sens["هر دو ضربه: eCPM انگلیسی نصف و ارگانیک انگلیسی نصف"]
S_SETUP = sens["راه‌اندازی انگلیسی هنوز انجام نشده: شرکت خارجی و حساب‌ها (+۲٬۰۰۰ دلار)"]
S_ADS = sens["انگلیسی فقط با تبلیغ (بدون خرید درون‌برنامه‌ای)"]
S_UA = sens["تبلیغ پولی انگلیسی ۴۰ میلیون در ماه، همیشگی"]
S_ECPM2 = sens["eCPM انگلیسی دو برابر (۶ دلار)"]
S_ORG2 = sens["نصب ارگانیک انگلیسی دو برابر"]
S_ECPMH = sens["eCPM انگلیسی نصف (۱٫۵ دلار)"]
S_ORGH = sens["نصب ارگانیک انگلیسی نصف"]

CSS = f"""
@font-face {{ font-family:Vazirmatn; font-weight:400; src:url('file://{FONTS}/Vazirmatn-Regular.ttf'); }}
@font-face {{ font-family:Vazirmatn; font-weight:500; src:url('file://{FONTS}/Vazirmatn-Medium.ttf'); }}
@font-face {{ font-family:Vazirmatn; font-weight:600; src:url('file://{FONTS}/Vazirmatn-SemiBold.ttf'); }}
@font-face {{ font-family:Vazirmatn; font-weight:700; src:url('file://{FONTS}/Vazirmatn-Bold.ttf'); }}
@font-face {{ font-family:Vazirmatn; font-weight:900; src:url('file://{FONTS}/Vazirmatn-Black.ttf'); }}
:root {{ --ink:#1c2230; --mut:#6b7385; --line:#dde1ea; --bg:#fff; --soft:#f4f6fa; --c1:#2f6fed; --c2:#1f9d6b; --c3:#d9593d; --c4:#e0a21b; --acc:#2f6fed; }}
@page {{ size:A4; margin:10mm 11mm 11mm; }}
* {{ box-sizing:border-box; }}
html {{ direction:rtl; }}
body {{ font-family:Vazirmatn,sans-serif; color:var(--ink); background:var(--bg); font-size:9pt; line-height:1.65; margin:0; }}
.ltr {{ unicode-bidi:isolate; direction:ltr; font-family:Vazirmatn,sans-serif; }}
.page {{ page-break-after:always; }}
.page:last-child {{ page-break-after:auto; }}
header.top {{ display:flex; justify-content:space-between; font-size:7.5pt; color:var(--mut); border-bottom:1px solid var(--line); padding-bottom:3px; margin-bottom:8px; }}
h1 {{ font-size:24pt; font-weight:900; margin:6px 0 0; line-height:1.3; }}
.sub {{ font-size:12pt; color:var(--mut); margin:0 0 4px; }}
.ver {{ display:inline-block; background:var(--acc); color:#fff; border-radius:5px; padding:0 8px; font-size:9pt; font-weight:700; }}
h2 {{ font-size:13.5pt; font-weight:800; margin:0 0 6px; display:flex; justify-content:space-between; align-items:baseline; border-bottom:2px solid var(--ink); padding-bottom:3px; }}
h2 .n {{ color:var(--mut); font-size:12pt; font-weight:600; }}
h3 {{ font-size:10pt; font-weight:700; margin:9px 0 3px; }}
p {{ margin:4px 0; text-align:justify; }}
.kpis {{ display:grid; grid-template-columns:repeat(4,1fr); gap:8px; margin:12px 0; }}
.kpi {{ border:1px solid var(--line); border-radius:8px; padding:8px 10px; background:var(--soft); }}
.kpi b {{ display:block; font-size:13pt; font-weight:800; line-height:1.4; }}
.kpi span {{ font-size:7.6pt; color:var(--mut); line-height:1.5; display:block; }}
table {{ width:100%; border-collapse:collapse; font-size:7.8pt; margin:4px 0 7px; }}
tr {{ page-break-inside:avoid; }}
th {{ background:var(--ink); color:#fff; font-weight:600; padding:3px 5px; text-align:right; }}
td {{ padding:2px 5px; border-bottom:1px solid var(--line); vertical-align:top; }}
tr.tot td {{ font-weight:700; background:var(--soft); }}
tr.v1 td {{ color:var(--mut); }}
tr.v2 td {{ font-weight:700; background:#eef3ff; }}
table.sum td:not(:first-child), table.ann td:not(:first-child):not(:nth-child(2)), table.as td:not(:first-child), table.ar td:not(:first-child), table.cost td:not(:first-child), table.rec td, table.sens td:not(:first-child), table.geo td:not(:first-child) {{ text-align:left; direction:ltr; unicode-bidi:plaintext; }}
table.sum th:not(:first-child), table.as th:not(:first-child), table.ar th:not(:first-child), table.sens th:not(:first-child) {{ text-align:center; }}
table.sum td:not(:first-child), table.as td:not(:first-child), table.ar td:not(:first-child), table.sens td:not(:first-child) {{ text-align:center; direction:rtl; }}
table.ann td, table.rec td, table.cost td {{ direction:rtl; }}
table.ann td:nth-child(n+3), table.cost td:nth-child(n+2), table.rec td:nth-child(n+3), table.geo td:nth-child(n+2) {{ text-align:center; direction:rtl; }}
.box {{ border-right:4px solid var(--acc); background:var(--soft); padding:4px 10px; margin:6px 0; font-size:8.6pt; border-radius:4px; }}
.warn {{ border-right-color:var(--c3); background:#fdf1ee; }}
.good {{ border-right-color:var(--c2); background:#edf8f2; }}
.note {{ font-size:7.6pt; color:var(--mut); }}
ul {{ margin:4px 0; padding-right:18px; }} li {{ margin:2px 0; }}
.chart {{ width:100%; height:auto; direction:ltr; }}
.chart .grid {{ stroke:var(--line); stroke-width:1; }} .chart .grid.zero {{ stroke:var(--ink); stroke-width:1.2; }}
.chart .ax {{ font-size:10px; fill:var(--mut); font-family:Vazirmatn; }}
.chart .lbl {{ font-size:11px; font-weight:600; font-family:Vazirmatn; }}
.chart .ln {{ fill:none; stroke-width:2.4; stroke-linejoin:round; }} .chart .ln.dash {{ stroke-dasharray:5 4; stroke-width:1.8; }}
.chart .ask {{ stroke:var(--c4); stroke-width:1.6; stroke-dasharray:6 4; }} .chart .ask-t {{ fill:var(--c4); }}
.legend {{ display:flex; flex-wrap:wrap; gap:3px 14px; font-size:8pt; margin:2px 0 4px; }}
.lg i {{ display:inline-block; width:16px; height:8px; border-radius:2px; vertical-align:middle; margin-left:5px; }}
.two {{ display:grid; grid-template-columns:1fr 1fr; gap:12px; }}
.stage {{ border:1px solid var(--line); border-radius:8px; padding:8px 12px; }}
.stage b.big {{ font-size:13pt; display:block; }}
.rm {{ display:grid; grid-template-columns:repeat(3,1fr); gap:8px; }}
.rm div {{ border:1px solid var(--line); border-radius:8px; padding:6px 8px; font-size:8pt; }}
.rm b {{ display:block; font-size:10.5pt; }}
"""

html = f"""<!doctype html><html lang="fa" dir="rtl"><head><meta charset="utf-8"><title>زنجیر — طرح درآمدی و پیش‌بینی مالی (ویرایش ۲)</title><style>{CSS}</style></head><body>

<!-- ============================ 1 ============================ -->
<section class="page">
<header class="top"><span>طرح درآمدی و پیش‌بینی مالی · سند ویژهٔ سرمایه‌گذار</span><span>ویرایش ۲ · {fn("۱۸ مهر ۱۴۰۵")}</span></header>
<p class="sub"><span class="ver">ویرایش ۲</span> &nbsp;نسخهٔ انگلیسی در {LTR("Google Play")} با تبلیغات {LTR("AdMob")} اضافه شد</p>
<h1>زنجیر</h1>
<p class="sub">بازی زنجیرهٔ کلمات برای اندروید — فارسی (کافه‌بازار، مایکت) و انگلیسی ({LTR("Google Play")})</p>
<p class="note">{fn("۱۸ مهر ۱۴۰۵ (برابر ۱۰ اکتبر ۲۰۲۶)")} · قیمت‌ها ثابت و به تومان · نرخ تبدیل: هر دلار {fa(FX)} تومان · جایگزین ویرایش ۱ ({fn("۱۷")} مهر)</p>

<div class="kpis">
 <div class="kpi"><b>{bn(ASK_TOTAL)} میلیارد تومان</b><span>سرمایهٔ درخواستی (ویرایش ۱: ۲٫۵) · حدود {fa(ASK_TOTAL*1e6/FX/1000,1)} هزار دلار</span></div>
 <div class="kpi"><b>{fp(b["first_profit"])}</b><span>اولین ماه سودده، سناریوی پایه (ویرایش ۱: ماه ۳۹ با برون‌یابی)</span></div>
 <div class="kpi"><b>٪{fa(en_share3)}</b><span>سهم نسخهٔ انگلیسی از درآمد سال سوم (پایه)؛ با ٪{fa(b["dau_en"][2]/b["dau_end"][2]*100)} از DAU</span></div>
 <div class="kpi"><b>{bn(b["peak_need"],2)} میلیارد</b><span>اوج نیاز نقدی پایه، ماه {fa(b["peak_month"])} (ویرایش ۱: ۲٫۰۷ در ماه ۳۸)</span></div>
</div>

<h2>خلاصهٔ اجرایی <span class="n">۱</span></h2>
<p>فرض این ویرایش: <b>نسخهٔ انگلیسی بازی ساخته و در {LTR("Google Play")} با تبلیغ جایزه‌ایِ {LTR("AdMob")} منتشر شده است</b> و همزمان با تأمین سرمایه، در ماه ۱ مدل، زنده است. هزینهٔ ساخت و انتشار آن سرمایهٔ سوخته (قبل از این دور) حساب شده؛ آنچه به مدل اضافه شده <b>هزینهٔ جاری</b> (شرکت/حساب خارجی، میزبانی خارجی، متن و پشتیبانی انگلیسی، آزمایش جذب) و <b>درآمد</b> انگلیسی است. بقیهٔ فرض‌های ایرانی از ویرایش ۱ حفظ شده (بازسازی آن‌ها در پیوست الف، با اختلاف چند درصد).</p>

{summary_table()}
<p class="note">اعداد داخل پرانتز زیان‌اند. مبالغ به میلیون تومان و قیمت ثابت مهر ۱۴۰۵. ستون «نسخهٔ ۱» اعداد منتشرشدهٔ ویرایش قبل است.</p>

<div class="box good"><b>چه عوض شد؟</b> در سناریوی پایه درآمد سال سوم از {fa(V1X["base"]["rev3"])} به {fa(b["rev"][2])} میلیون تومان می‌رسد و سال سوم از زیان ({fa(abs(V1X["base"]["net3"]))}) به سود ({fa(b["net"][2])}) می‌رود؛ سربه‌سر ماهانه حدود {fa(39-b["first_profit"])} ماه زودتر می‌شود. دلیل: هر کاربر انگلیسی در روز حدود {fa(b["en_arpdau"]/b["fa_arpdau"],1)} برابر کاربر ایرانی درآمد دارد ({fa(b["en_arpdau"])} در برابر {fa(b["fa_arpdau"])} تومان)، چون هر نمایش تبلیغ در ادموب با آمیختهٔ جهانی حدود {fa(M.EN["base"]["ecpm"]/(M.FA["base"]["ecpm"]/FX),1)} برابر تپسل می‌دهد.</div>
<div class="box warn"><b>چه نشد؟</b> (۱) جذب پولی انگلیسی نمی‌صرفد: ارزش عمر هر نصب در پایه فقط {fa(b["en_ltv_cpi"],2)} برابر هزینهٔ جذب است (ایرانی: {fa(b["fa_ltv_cpi"],2)})؛ بنابراین رشد انگلیسی تقریباً کاملاً ارگانیک فرض شده و بودجهٔ پولی آن فقط یک آزمایش ۶ ماهه است. (۲) هزینهٔ ثابت انگلیسی (≈{usd(M.usd(M.EN_ENTITY_USD)+M.usd(M.EN_HOSTING_USD)+M.usd(M.EN_OUTSOURCE_USD))} دلار در ماه) به دلار است و در برابر هزینه‌های تومانی ایرانی بزرگ؛ سال اول {fa(en_cost_extra_y1)} میلیون تومان به هزینه اضافه می‌کند و زیان ماه ۶ را از {fa(-fa_only["cum6"])} به {fa(cum6)} میلیون می‌رساند. (۳) <b>همهٔ اعداد انگلیسی فرض‌اند</b> و بزرگ‌ترین ریسک، امکان‌پذیری حقوقی دریافت درآمد دلاری برای تیم ایرانی است (بخش ۸).</div>
</section>

<!-- ============================ 2 ============================ -->
<section class="page">
<header class="top"><span>طرح درآمدی و پیش‌بینی مالی</span><span>ویرایش ۲</span></header>
<h2>محصول، تیم و وضعیت فعلی <span class="n">۲</span></h2>
<p>بازیکن کلمه‌ای می‌نویسد که با آخرین حرف کلمهٔ قبلی شروع شود؛ کلمه باید در فرهنگ لغت باشد و تکراری نباشد. محصول از نظر فنی ساخته شده است؛ <b>هنوز داده‌ی واقعی بازار (نصب، نگهداشت، درآمد) از هیچ‌یک از دو نسخه ندارد.</b></p>
<h3>تغییرات این ویرایش در فرض‌های وضعیت</h3>
{tbl(["", "ویرایش ۱", "ویرایش ۲ (این سند)"], [
 ["بازار", "اندروید ایران: کافه‌بازار و مایکت", "ایران + اندروید جهانی انگلیسی‌زبان از طریق " + LTR("Google Play")],
 ["تبلیغ", "تپسل (جایزه‌ای)", "تپسل (ایران) + " + LTR("AdMob") + " (جایزه‌ای، انگلیسی)؛ باز هم هیچ تبلیغ اجباری یا میان‌بازی نداریم"],
 ["پرداخت", "کافه‌بازار و مایکت (از ماه ۱ تا ۲، درآمد از ماه ۳)", "همان + " + LTR("Google Play Billing") + " برای نسخهٔ انگلیسی (درآمد از ماه ۳)"],
 ["ورود کاربر", "شمارهٔ موبایل + پیامک کاوه‌نگار", "فرض: نسخهٔ انگلیسی با ورود مهمان/حساب گوگل کار می‌کند؛ پیامک بین‌المللی هزینه‌ای ندارد"],
 ["سرور", "یک میزبان ایرانی", "برای نسخهٔ انگلیسی میزبان خارجی لازم است (میزبان ایرانی به گوگل دسترسی ندارد و تأخیر جهانی بالاست)"],
 ["فرهنگ لغت", "۲۱٬۵۲۷ کلمهٔ فارسی پالایش‌شده", "فرض: فرهنگ لغت انگلیسی با مجوز تجاری آماده است (بررسی نشده)"],
 ["مؤسس", "۱ نفر؛ ۴۵ میلیون تومان در ماه (≈۱۷۰ دلار)", "همان؛ <b>بدون حقوق اضافه</b> برای نسخهٔ انگلیسی — ریسک تقسیم توجه (بخش ۸)"],
], "as")}
<h3>ساخته و اجراشده (تکرار از ویرایش ۱)</h3>
<ul>
<li>اپ {LTR("Flutter")} با طراحی کامل فارسی/راست‌به‌چپ؛ حالت‌ها: تک‌نفره، مقابل هوش مصنوعی، رقابت آنلاین ۱ در ۱ با زنجیرهٔ مشترک، چالش روزانه.</li>
<li>سرور {LTR("Go")} با {LTR("WebSocket, PostgreSQL, Redis")}؛ حلقه‌های نگهداشت: استریک روزانه، جدول امتیاز، دوستان و چالش دوستانه، جوایز، کد دعوت؛ اقتصاد سکه و اشتراک پریمیوم (فقط ظاهری/اجتماعی).</li>
</ul>
<h3>با سرمایه ساخته می‌شود</h3>
<ul>
<li>پرداخت کافه‌بازار و مایکت، پیامک و {LTR("TLS")} واقعی، اتصال واقعی تپسل، کمپین آزمایشی ایرانی.</li>
<li><b>جدید:</b> اندازه‌گیری واقعی {LTR("eCPM")} ادموب به تفکیک کشور، تأیید اولین پرداخت دلاری و انتقال آن به تومان، {LTR("ASO")} انگلیسی، و تصمیم دربارهٔ ادامه یا توقف بخش انگلیسی در گیت ماه ۶.</li>
<li>ویژگی‌های نگهداشت: دست‌های «بهترین از ۵»، نشان‌ها، نمایش آواتار و نشان در لیست‌ها.</li>
</ul>
<div class="box"><b>ریسک ساختاری انگلیسی که هنوز در محصول نیست:</b> بازی ۱ در ۱ هم‌زمان به بازیکن آنلاین هم‌زمان نیاز دارد. در ابتدا (چند ده‌ DAU) رقیب انسانی پیدا نمی‌شود و بازیکن همیشه با هوش مصنوعی بازی می‌کند؛ بنابراین حلقهٔ «ورودی ۲۰ سکه‌ای مسابقه ۱ در ۱» عملاً دیرتر از نسخهٔ ایرانی روشن می‌شود. این اثر در مدل جداگانه لحاظ نشده و در نرخ خریداران پایین (٪{fa(M.EN["base"]["buy"]*100,1)} در برابر ٪{fa(M.FA["base"]["buy"]*100,1)} ایرانی) جذب شده است.</div>
</section>

<!-- ============================ 3 ============================ -->
<section class="page">
<header class="top"><span>طرح درآمدی و پیش‌بینی مالی</span><span>ویرایش ۲</span></header>
<h2>بازار و مخاطب <span class="n">۳</span></h2>
<h3>بازار ایران (بدون تغییر از ویرایش ۱)</h3>
<p>گیمرهای اندروید ایرانی در کافه‌بازار/مایکت: ≈۳۰ میلیون کاربر ماهانه و ≈۶٫۶ میلیون روزانهٔ کافه‌بازار (گزارش {LTR("Game Dev Reports")}، ۲۰۲۰–۲۰۲۱ — قدیمی و پیش از تضعیف ریال)؛ بازار بازی ایران حدود ۸۵۵ میلیون دلار ({LTR("IMARC")}، ۲۰۲۵). سهم سناریوی پایه از DAU کافه‌بازار در سال سوم حدود ٪۰٫۱۵ است.</p>
<h3>بازار انگلیسی / {LTR("Google Play")} (جدید)</h3>
<p>مخاطب: بازیکنان اندرویدِ بازی‌های کلمه‌ای کژوال در کشورهای انگلیسی‌زبان و کشورهایی که انگلیسی را زبان دوم بازی می‌کنند. جذابیت: بازار بسیار بزرگ‌تر و درآمد به‌ازای هر نمایش تبلیغ چند برابر ایران. ضعف: رقابت بسیار شدید، و بازی «زنجیرهٔ کلمات» در انگلیسی ژانری کوچک‌تر از {LTR("Wordle")}‌ها و کلمه‌چینی‌ها است. <b>هیچ دادهٔ معتبری برای اندازهٔ ژانر زنجیرهٔ کلمات در گوگل‌پلی پیدا نشد</b>؛ نصب ارگانیک انگلیسی در مدل (۳٬۰۰۰ در ماه اول) یک فرض مدیریتی است و حساس‌ترین ورودی مدل است (بخش ۶).</p>
{tbl(["شاخص مرجع", "مقدار", "منبع و قید"], [
 ["eCPM تبلیغ جایزه‌ای، اندروید آمریکا", "≈۱۶ دلار (۲۰۲۵)", "مقالهٔ " + LTR("tuapppara.com") + "؛ تخمین ثانویه"],
 ["همان، اروپای غربی (iOS)", "۵ تا ۱۲ دلار", "تخمین‌های " + LTR("playio.co") + "؛ بدون منبع اصلی"],
 ["همان، برزیل (اندروید) / هند (اندروید)", "۱ تا ۳ / ۰٫۳ تا ۱ دلار", "همان تخمین‌ها"],
 ["دامنهٔ منتشرشده برای آمریکا (چند منبع)", "۱۳ تا ۳۰ دلار", "اختلاف بیش از دو برابر بین منابع (" + LTR("Global Games Forum") + ")"],
 ["CPI بازی پازل/کژوال اندروید (میانگین جهانی)", "۰٫۸۰ تا ۲٫۰۰ دلار", LTR("Admiral Media") + "، ۲۰۲۵ — بدون تفکیک کشور"],
 ["ماندگاری بازی پازل (روز ۱ / ۷ / ۳۰)", "٪۳۲ / ٪۱۲ / ٪۵٫۳", LTR("AppsFlyer") + "، سه‌ماهه سوم ۲۰۲۲؛ قدیمی و غیرتفکیکی"],
 ["کارمزد گوگل‌پلی", "٪۱۵ تا سقف ۱ میلیون دلار در سال و برای اشتراک‌ها؛ ٪۳۰ بالاتر", "صفحهٔ پشتیبانی گوگل؛ نرخ‌های جدید ۲۰۲۶ برای آمریکا/بریتانیا/اروپا متفاوت‌اند و اینجا لحاظ نشده‌اند"],
], "as")}
<p class="note">این جدول فقط دامنه‌های مرجع است. تقریباً هیچ‌یک از منابع تفکیکِ «بازی کلمه‌ای، اندروید، کشور» ندارند و همه یا قدیمی‌اند یا تخمین ثانویه. اعداد مدل از همین دامنه‌ها انتخاب شده‌اند، نه اینکه از اندازه‌گیری آمده باشند؛ شش ماه اول دقیقاً برای اندازه‌گیری‌شان است.</p>
<h3>آمیختهٔ جغرافیایی پشت eCPM انگلیسی (سناریوی پایه)</h3>
{geo_table()}
<p class="note">eCPM یعنی درآمدی که ادموب به ناشر پرداخت می‌کند به‌ازای هر ۱٬۰۰۰ نمایش (پس از سهم خود ادموب). سناریوها: محافظه‌کارانه {fa(M.EN["cons"]["ecpm"],2)}، پایه {fa(M.EN["base"]["ecpm"],2)}، خوش‌بینانه {fa(M.EN["opt"]["ecpm"],2)} دلار. سهم کشورهای پردرآمد (۸ تا ۲۵٪ از نمایش‌ها) است که eCPM را تعیین می‌کند — اگر آنلاین‌ترین بازیکنان انگلیسی از هند و فیلیپین باشند، eCPM نزدیک ۱ دلار می‌شود، نه ۳.</p>
<h3>باز است: تحلیل رقبا</h3>
<p>نه بازی‌های کلمه‌ای فارسی در کافه‌بازار/مایکت و نه بازی‌های «زنجیرهٔ کلمات»/«شیریتوری» انگلیسی در گوگل‌پلی (نصب، امتیاز، مدل درآمدی) بررسی نشده‌اند و باید پیش از ارائه به سرمایه‌گذار تکمیل شوند.</p>
</section>

<!-- ============================ 4 ============================ -->
<section class="page">
<header class="top"><span>طرح درآمدی و پیش‌بینی مالی</span><span>ویرایش ۲</span></header>
<h2>مدل درآمدی <span class="n">۴</span></h2>
<p>سیاست محصول بدون تغییر است: همهٔ جریان‌ها اختیاری‌اند، تبلیغ اجباری یا میان‌بازی نداریم (در نسخهٔ انگلیسی هم فقط تبلیغ جایزه‌ایِ آغازشده با بازیکن؛ بنر و تمام‌صفحه‌ای عمداً خارج از مدل است و می‌تواند صعود احتمالی باشد) و هیچ برتری مسابقه‌ای فروخته نمی‌شود. در سناریوی پایهٔ سال سوم، از {sg(b["rev"][2])} میلیون تومان درآمد: ایرانی {fa(b["rev_fa"][2])} (٪{fa(b["rev_fa"][2]/b["rev"][2]*100)}) و انگلیسی {fa(b["rev_en"][2])} (٪{fa(en_share3)}).</p>
{tbl(["جریان", "بازار", "شبکه/فروشگاه", "قیمت واحد", "چطور پول درمی‌آید", "وضعیت"], [
 ["تبلیغ جایزه‌ای", "ایران", "تپسل", "eCPM ≈ ۲۶۰٬۰۰۰ تومان (≈۰٫۹۸ دلار)", "بازیکن برای ۲۰ سکه یا ادامهٔ بازی تبلیغ می‌بیند", "اجراشده؛ نرخ واقعی دریافت نشده"],
 ["تبلیغ جایزه‌ای", "انگلیسی", LTR("AdMob"), f"eCPM آمیخته ≈ {fa(M.EN['base']['ecpm'],2)} دلار (≈{fa(M.EN['base']['ecpm']*FX)} تومان)", "همان رفتار", "فرض: منتشرشده؛ نرخ واقعی هنوز سنجیده نشده"],
 ["سکه", "ایران", "کافه‌بازار / مایکت", "۱۰۰ سکه ۹٬۰۰۰ · ۳۵۰ سکه ۲۵٬۰۰۰ · ۱٬۵۰۰ سکه ۷۹٬۰۰۰ تومان", "کمک‌کننده‌ها، ادامه، ورودی مسابقه ۱ در ۱", "منطق ساخته شده؛ پرداخت ماه ۱ تا ۲"],
 ["سکه", "انگلیسی", LTR("Google Play Billing"), "فرض: ۰٫۹۹ / ۲٫۹۹ / ۷٫۹۹ دلار؛ میانگین خرج هر خریدار ≈۴ دلار در ماه", "همان", "فرض؛ قیمت‌ها هنوز در محصول نیست"],
 ["پریمیوم", "ایران", "کافه‌بازار / مایکت", "ماهانه ۱۹٬۰۰۰ · هفتگی ۷٬۰۰۰ تومان", "تانت، آواتار، نشان (ظاهری)", "کد ساخته شده؛ خرید واقعی نه"],
 ["پریمیوم", "انگلیسی", LTR("Google Play"), "فرض: ۲٫۹۹ دلار در ماه", "همان", "فرض"],
 ["حذف تبلیغ", "هر دو", "—", "۱۵٬۰۰۰ تومان", "یک‌باره", "در مدل لحاظ نشده"],
], "as")}
<h3>درآمد هر کاربر فعال روزانه ({LTR("ARPDAU")}) و نسبت {LTR("LTV/CPI")}</h3>
{arpdau_table()}
<div class="box"><b>جملهٔ کلیدی ویرایش ۲:</b> درآمد هر کاربر انگلیسی چند برابر ایرانی است ولی <i>هزینهٔ جذب هر نصب انگلیسی</i> (۰٫۴۰ تا ۱٫۲۰ دلار) حدود ۱۳ تا ۱۸ برابر ایرانی (۰٫۰۳ تا ۰٫۰۷۵ دلار) است. نتیجه: <b>نسخهٔ انگلیسی فقط از مسیر ارگانیک سودده است؛ جذب پولی انگلیسی در هیچ‌یک از سه سناریو به {LTR("LTV/CPI")} بالای ۱ نمی‌رسد</b> (محافظه‌کارانه {fa(SM["cons"]["en_ltv_cpi"],2)}، پایه {fa(b["en_ltv_cpi"],2)}، خوش‌بینانه {fa(SM["opt"]["en_ltv_cpi"],2)}). بنابراین گیت جذب پولی انگلیسی در مدل باز نمی‌شود؛ فقط ۶ ماه آزمایش حدود ۲۵ میلیون تومان (≈۹۵ دلار) در ماه برای سنجش واقعی نسبت.</div>
<p>سهم تبلیغ از درآمد سال سوم (پایه): ایرانی ٪{fa(M.year(R["base"]["fa"]["ads"],2)/M.year(R["base"]["fa"]["rev"],2)*100)} تبلیغ و بقیه خرید؛ انگلیسی ٪{fa(M.year(R["base"]["en"]["ads"],2)/M.year(R["base"]["en"]["rev"],2)*100)} تبلیغ و ٪{fa(100-M.year(R["base"]["en"]["ads"],2)/M.year(R["base"]["en"]["rev"],2)*100)} خرید/اشتراک. ترکیبی: ٪{fa((res["base"]["rev_split3"]["fa_ads"]+res["base"]["rev_split3"]["en_ads"])/b["rev"][2]*100)} تبلیغ در برابر ٪{fa((res["base"]["rev_split3"]["fa_iap"]+res["base"]["rev_split3"]["en_iap"])/b["rev"][2]*100)} خرید؛ یعنی وابستگی به تبلیغ از ٪۸۴ (ویرایش ۱) کمتر شده و روی دو شبکه (تپسل و ادموب) پخش می‌شود.</p>
<p class="note">کارمزد کافه‌بازار/مایکت ٪۳۰ (تأییدنشده)، کارمزد گوگل‌پلی ٪۱۵، و ٪۵ کاهش هنگام انتقال دلار به تومان (فرض). مالیات بر ارزش افزوده و مالیات شرکت خارجی در مدل نیست.</p>
</section>

<!-- ============================ 5 ============================ -->
<section class="page">
<header class="top"><span>طرح درآمدی و پیش‌بینی مالی</span><span>ویرایش ۲</span></header>
<h2>مفروضات نسخهٔ انگلیسی <span class="n">۵</span></h2>
<p>مدل ماهانه است، ۳۶ ماه را در سه سناریو می‌سنجد و برای نسخهٔ انگلیسی بخشی جدا (با ماندگاری و DAU جدا) دارد که با بخش ایرانی جمع می‌شود. مفروضات ایرانی همان جدول بخش ۵ ویرایش ۱ است (CPI ۲۰٬۰۰۰ / ۱۲٬۰۰۰ / ۸٬۰۰۰ تومان، ارگانیک ۳٬۰۰۰ / ۵٬۰۰۰ / ۸٬۰۰۰، eCPM تپسل ۱۲۰ / ۲۶۰ / ۴۵۰ هزار تومان و …). <b>هیچ‌کدام از ستون‌ها داده‌ی واقعی نیستند.</b></p>
{assumptions_table()}
<p><b>چرا ماندگاری انگلیسی کمی پایین‌تر از ایرانی است؟</b> بازار ایران برای این ژانر رقیب کمتر دارد و در فروشگاه‌های داخلی رقابت برای توجه کمتر است؛ در گوگل‌پلی روز ۱ را کمی پایین‌تر (٪{fa(M.EN["base"]["ret"][0]*100)} در برابر ٪{fa(M.FA["base"]["ret"][0]*100)}) گذاشته‌ام. این هم فرض است.</p>
<p><b>چرا اثر دعوت و دهان‌به‌دهان انگلیسی کمتر است؟</b> زنجیرهٔ مشترک و دعوت دوست در ایران با کد دعوت، جوایز و رقابت دوستانه قوی است؛ در انگلیسی گراف اجتماعی و کد دعوت هنوز ثابت نشده (۰٫۱۵ در برابر ۰٫۳۰ نصب اضافه به‌ازای هر نصب پولی در پایه).</p>
<h3>هزینه‌های جاری اضافه (دلار → تومان)</h3>
{tbl(["قلم", "دلار در ماه", "میلیون تومان در ماه", "چرا لازم است"], [
 ["نگهداری شرکت/حساب خارجی (ثبت، حسابداری، بانک)", fa(M.EN_ENTITY_USD), fa(M.usd(M.EN_ENTITY_USD),1), "نگه‌داشتن حساب گوگل‌پلی/ادموب و دریافت دلار (بخش ۸)"],
 ["میزبانی خارجی", fa(M.EN_HOSTING_USD) + " + بار متغیر", fa(M.usd(M.EN_HOSTING_USD),1) + " + ۰٫۳۳ به‌ازای هر ۱٬۰۰۰ DAU", "میزبان ایرانی به گوگل دسترسی ندارد؛ تأخیر برای بازیکن خارجی"],
 ["خدمات بیرونی انگلیسی (ASO، متن، جامعه، پشتیبانی)", fa(M.EN_OUTSOURCE_USD), fa(M.usd(M.EN_OUTSOURCE_USD),1), "انتشار ارگانیک بدون تبلیغ پولی وابسته به رتبه و نقد در استور است"],
 ["آزمایش جذب پولی (۶ ماه)", "≈۹۵", fa(M.EN_UA_TEST), "فقط برای سنجش LTV/CPI؛ بعد از ماه ۶ صفر مگر نسبت از ۱ بگذرد"],
 ["جمع جاری انگلیسی (۶ ماه اول / بعد از آن)", "≈" + fa(M.EN_ENTITY_USD+M.EN_HOSTING_USD+M.EN_OUTSOURCE_USD+M.EN_UA_TEST*1e6/FX) + " / ≈" + fa(M.EN_ENTITY_USD+M.EN_HOSTING_USD+M.EN_OUTSOURCE_USD), fa(M.usd(M.EN_ENTITY_USD+M.EN_HOSTING_USD+M.EN_OUTSOURCE_USD)+M.EN_UA_TEST,1) + " / " + fa(M.usd(M.EN_ENTITY_USD+M.EN_HOSTING_USD+M.EN_OUTSOURCE_USD),1), ""],
], "as")}
<p class="note">یک‌باره (سرمایهٔ سوخته، در مدل نیست): ≈{fa(M.EN_SETUP_USD)} دلار برای ثبت شرکت خارجی، حساب توسعه‌دهندهٔ گوگل ({fa(25)} دلار)، سیاست حریم خصوصی و شرایط استفاده. اگر این کارها هنوز انجام نشده، {fa(M.usd(M.EN_SETUP_USD))} میلیون تومان به نیاز نقدی اضافه می‌شود (بخش ۶، جدول حساسیت).</p>
</section>

<!-- ============================ 6 ============================ -->
<section class="page">
<header class="top"><span>طرح درآمدی و پیش‌بینی مالی</span><span>ویرایش ۲</span></header>
<h2>پیش‌بینی مالی ۳ ساله <span class="n">۶</span></h2>
<p><b>در سناریوی پایه، زیان انباشته به {bn(b["peak_need"],2)} میلیارد در ماه {fa(b["peak_month"])} می‌رسد، سپس برمی‌گردد و ماه ۳۶ را روی {sg(b["cum36"]/1000,2)} میلیارد می‌بندد.</b> در ویرایش ۱ (فقط ایرانی) همین سناریو تا ماه ۴۰ هم‌چنان در حال زیان‌انباشتن بود ({bn(fa_only["peak_need"],2)} میلیارد).</p>
{chart_cash()}
<p class="note">مانده نقدی تجمعی ۳۶ ماه، میلیارد تومان، قیمت ثابت مهر ۱۴۰۵. خط‌چین خاکستری: همان سناریوی پایه بدون نسخهٔ انگلیسی. خط‌چین نارنجی: سقف سرمایهٔ درخواستی. مدل داخلی بر پایهٔ مفروضات بخش ۵ و ۵ ویرایش ۱.</p>
<h3>نتایج سالانه (میلیون تومان؛ داخل پرانتز زیان)</h3>
{annual_table()}
<p class="note">بخش ایرانی بازسازی‌شده از ویرایش ۱ است و در اکثر ارقام با ویرایش ۱ در چند درصد می‌خواند (پیوست الف). «هزینهٔ کل» هر دو بازار و هزینهٔ مشترک مؤسس را در بر می‌گیرد.</p>
</section>

<!-- ============================ 7 ============================ -->
<section class="page">
<header class="top"><span>طرح درآمدی و پیش‌بینی مالی</span><span>ویرایش ۲</span></header>
<h2>درآمد در برابر هزینه و حساسیت <span class="n">۷</span></h2>
<p>درآمد ماهانهٔ ترکیبی در سناریوی پایه در {fp(b["first_profit"])} از هزینهٔ ماهانه (≈{fa(R["base"]["cost"]["total"][35])} میلیون تومان در ماه ۳۶) بالاتر می‌رود. از ماه ۱۲ به بعد بخش انگلیسی بیش از یک‌سوم درآمد را می‌سازد.</p>
{chart_monthly()}
<p class="note">سناریوی پایه، میلیون تومان در ماه. درآمد انگلیسی روی درآمد ایرانی انباشته شده است.</p>
<h3>کدام اهرم بیشتر اثر دارد؟</h3>
<p>هر بار یک متغیر را در سناریوی پایهٔ ترکیبی عوض کرده‌ام (به جز ردیف‌های ترکیبی/ساختاری).</p>
{sens_table()}
<div class="box"><b>برداشت:</b> (۱) نسخهٔ انگلیسی یک شرط‌بندی روی دو عدد است: نصب ارگانیک و eCPM. اگر هر کدام دو برابر شود، خالص سال سوم از {sg(b["net"][2])} به {sg(S_ORG2["net3"])} و {sg(S_ECPM2["net3"])} می‌رود؛ اگر هر کدام نصف شود، به {sg(S_ORGH["net3"])} و {sg(S_ECPMH["net3"])} می‌افتد؛ و اگر هر دو نصف شوند اوج نیاز نقدی به {bn(S_BOTH["peak"],1)} میلیارد می‌رسد که <b>از سقف {bn(ASK_TOTAL,1)} میلیارد بیرون است</b> (برای همین گیت ماه ۶ شرط انگلیسی دارد). (۲) خرید درون‌برنامه‌ای انگلیسی مهم است: بدون آن ({LTR("AdMob")} تنها) خالص سال سوم {sg(S_ADS["net3"])} و اوج نیاز {bn(S_ADS["peak"],1)} میلیارد است. (۳) جذب پولی انگلیسی زیان‌ده است: ۴۰ میلیون در ماه دائمی خالص سال سوم را به {sg(S_UA["net3"])} می‌رساند. (۴) اگر ثبت شرکت و حساب‌ها هنوز انجام نشده باشد، اوج نیاز نقدی {bn(S_SETUP["peak"],2)} میلیارد می‌شود. (۵) انتشار از طریق یک ناشر خارجی با ٪۳۰ سهم ناشر، اوج نیاز را به {bn(S_PUB["peak"],2)} میلیارد می‌رساند و هزینه‌ی شرکت/میزبان را حذف می‌کند، بی آنکه خالص سال سوم عوض شود ({sg(S_PUB["net3"])}) — گزینه‌ای که ممکن است ریسک حقوقی دریافت دلار را کم کند.</div>
<p><b>بدترین حالت انگلیسی کنترل‌شده است:</b> اگر انتقال درآمد دلاری ممکن نشود و پس از ۶ ماه نسخهٔ انگلیسی متوقف شود، اوج نیاز نقدی از {bn(fa_only["peak_need"],2)} به {bn(S_BLOCK["peak"],2)} میلیارد می‌رسد، یعنی هزینهٔ آزمون ≈{bn(S_BLOCK["peak"]-fa_only["peak_need"],2)} میلیارد تومان (≈{fa((S_BLOCK["peak"]-fa_only["peak_need"])*1e6/FX/1000,1)} هزار دلار).</p>
</section>

<!-- ============================ 8 ============================ -->
<section class="page">
<header class="top"><span>طرح درآمدی و پیش‌بینی مالی</span><span>ویرایش ۲</span></header>
<h2>هزینه‌ها، سرمایه و شاخص‌های آزادسازی <span class="n">۸</span></h2>
<p>با یک نفر تیم، هزینهٔ ثابت پایین است؛ نسخهٔ انگلیسی هزینهٔ ثابت را حدود ٪{fa(R["base"]["cost"]["total"][23]/R0["base"]["cost"]["total"][23]*100-100)} در ماه ۲۴ بالا می‌برد. اوج نیاز نقدی پایه {bn(b["peak_need"],2)} میلیارد تومان در ماه {fa(b["peak_month"])} است؛ {bn(ASK_TOTAL,1)} میلیارد حدود ٪{fa((ASK_TOTAL/b["peak_need"]-1)*100)} حاشیهٔ اطمینان دارد.</p>
{cost_table()}
<div class="two">
 <div class="stage"><b class="big">مرحلهٔ ۱: آزمایش</b><b>{bn(ASK_STAGE1,1)} میلیارد تومان (≈{fa(ASK_STAGE1*1e6/FX,0)} دلار)</b><br>ماه ۱ تا ۶ · مصرف مدل پایه: {bn(cum6,2)} میلیارد زیان تجمعی در ماه ۶ (ویرایش ۱: ۰٫۶۱)<br>کارها: پرداخت کافه‌بازار/مایکت، پیامک و TLS واقعی، اتصال تپسل و کمپین آزمایشی، <b>اندازه‌گیری واقعی ادموب، تأیید اولین پرداخت دلاری، آزمایش جذب انگلیسی</b></div>
 <div class="stage"><b class="big">مرحلهٔ ۲: رشد</b><b>{bn(ASK_STAGE2,1)} میلیارد تومان (≈{fa(ASK_STAGE2*1e6/FX,0)} دلار)</b><br>ماه ۷ تا ۳۰ · مصرف مدل پایه: {bn(b["peak_need"]-cum6,2)} میلیارد (اوج در ماه {fa(b["peak_month"])})<br>کارها: ویژگی‌های نگهداشت، آواتار و نشان، ASO و محتوای انگلیسی، جذب پولی ایرانی (فقط اگر بصرفد)، بازنگری قیمت‌ها</div>
</div>
<h3>گیت ماه ۶ — شرط پرداخت مرحلهٔ دوم</h3>
<p>پایهٔ پیش‌بینی در ماه ۶: حدود {fa(round(fa_inst6+en_inst6,-3))} نصب (ایرانی {fa(round(fa_inst6,-3))} + انگلیسی {fa(round(en_inst6,-3))}) و حدود {fa(round(fa_dau6+en_dau6,-2))} کاربر فعال روزانه (ایرانی {fa(round(fa_dau6,-2))} + انگلیسی {fa(round(en_dau6,-1))}). همهٔ ارقام با داده‌ی واقعی سنجیده می‌شوند، نه پیش‌بینی.</p>
<ul>
<li><b>ایرانی (بدون تغییر):</b> ≥ {fa(round(fa_dau6,-2))} کاربر فعال روزانه و ≥ {fa(round(fa_inst6,-3))} نصب؛ ماندگاری روز ۱/۷/۳۰ حداقل ٪۳۵/٪۱۲/٪۵؛ ARPDAU ≥ {fa(round(b["fa_arpdau"],-1))} تومان با درآمد واقعی تپسل و خرید واقعی؛ خریداران ≥ ٪۱٫۵ از MAU.</li>
<li><b>انگلیسی (جدید):</b> (الف) یک پرداخت واقعی از ادموب و یک از گوگل‌پلی به حساب برسد و به تومان قابل انتقال باشد؛ (ب) eCPM جایزه‌ای واقعی ادموب ≥ {fa(M.EN["base"]["ecpm"]*0.67,1)} دلار (دو سوم فرض پایه) با ≥ {fa(M.EN["base"]["imps"],1)} نمایش به‌ازای DAU؛ (ج) ماندگاری روز ۱ ≥ ٪{fa(M.EN["base"]["ret"][0]*100-3)} و روز ۷ ≥ ٪{fa(M.EN["base"]["ret"][1]*100-1)}؛ (د) DAU انگلیسی ≥ {fa(round(en_dau6*0.6,-1))} (۶۰٪ پایه) <i>بدون</i> تبلیغ پولی جدی؛ (ه) نسبت LTV/CPI آزمایش ۶ ماهه گزارش شود (بالای ۱ بودجهٔ جذب را باز می‌کند).</li>
<li><b>گیت ماه ۲۴:</b> درآمد ماهانه ترکیبی حداقل ٪۷۰ هزینهٔ ماهانه (در پایه {fa(b["rev_m24"])} از {fa(b["cost_m24"])} میلیون).</li>
</ul>
<div class="box warn">اگر شاخص‌های انگلیسی نرسید ولی ایرانی رسید: بخش انگلیسی متوقف می‌شود (صرفه‌جویی ≈{fa(M.usd(M.EN_ENTITY_USD+M.EN_HOSTING_USD+M.EN_OUTSOURCE_USD))} میلیون تومان در ماه) و پروژه با پلن ایرانی ادامه می‌یابد. اگر ایرانی هم نرسید، سه راه هست: ادامه با هزینهٔ کمتر (مثلاً حقوق مؤسس پایین‌تر)، فروش یا استقرار در یک ناشر بازی، یا توقف. زیان سرمایه‌گذار در بدترین حالت مرحلهٔ اول است.</div>
</section>

<!-- ============================ 9 ============================ -->
<section class="page">
<header class="top"><span>طرح درآمدی و پیش‌بینی مالی</span><span>ویرایش ۲</span></header>
<h2>نقشهٔ راه و ریسک‌ها <span class="n">۹</span></h2>
<div class="rm">
 <div><b>۱. آزمایش — ماه ۱ تا ۶</b>پرداخت داخلی ایران، پیامک و TLS؛ اندازه‌گیری ادموب، اولین پرداخت دلاری، آزمایش جذب انگلیسی<br><i>گیت ماه ۶</i></div>
 <div><b>۲. رشد — ماه ۷ تا ۳۰</b>نگهداشت، آواتار/نشان، ASO انگلیسی و محتوا؛ جذب پولی فقط اگر LTV/CPI > ۱<br><i>گیت ماه ۲۴: درآمد ≥ ٪۷۰ هزینه</i></div>
 <div><b>۳. سودآوری — ماه ۲۵ تا ۳۶</b>پایه: سودده شدن ماهانه از {fp(b["first_profit"])}؛ یا سرمایهٔ دورهٔ بعد، یا فروش به ناشر</div>
</div>
<h3>ریسک‌ها</h3>
{tbl(["ریسک", "چرا مهم است", "کاهش"], [
 [ "<b>دریافت درآمد دلاری</b> (بزرگ‌ترین ریسک جدید)",
   "تحریم‌ها: طبق گزارش‌های عمومی (اغلب قدیمی؛ سیاست ۲۰۲۵–۲۶ را پیدا نکردم)، گوگل‌پلی برنامه‌های پولی/خرید درون‌برنامه‌ای را برای ایران ممنوع کرده، ادموب برای ایران در دسترس نیست و در ۲۰۲۳ برنامه‌های ایرانی (دیجی‌کالا، تپسی) تعلیق شدند. ساختن شرکت خارجی ممکن است خودش با قوانین گوگل/تحریم‌ها در تعارض باشد اگر مالک واقعی در ایران باشد. همهٔ درآمد انگلیسی ({bn(b['rev_en'][2],1)} میلیارد تومان در سال ۳ پایه) به این بستگی دارد.".replace("{bn(b['rev_en'][2],1)}", bn(b['rev_en'][2],1)),
   "قبل از هر هزینهٔ دیگر مشاورهٔ حقوقی/تحریمی؛ گزینهٔ ناشر خارجی با تقسیم درآمد؛ گیت ماه ۶ (الف) پرداخت واقعی؛ سقف زیان آزمون ≈" + bn(S_BLOCK['peak']-fa_only['peak_need'],2) + " میلیارد" ],
 ["حساب ادموب/گوگل‌پلی مسدود می‌شود", "تعلیق حساب یا ترافیک نامعتبر، همه درآمد انگلیسی را قطع می‌کند و بازگشت حساب ممکن نیست", "فقط تبلیغ جایزه‌ایِ آغازشده با بازیکن؛ اجرای سیاست رضایت (UMP)؛ شبکهٔ تبلیغاتی دوم از طریق میانجی‌گری"],
 ["نصب ارگانیک انگلیسی و eCPM", "هر کدام نصف شود، خالص سال سوم حدود ۱ میلیارد بدتر می‌شود؛ هر دو → نیاز نقدی بیش از سقف", "گیت انگلیسی در ماه ۶؛ توقف بخش انگلیسی اگر نرسید"],
 ["شروع سرد بازی ۱ در ۱", "بدون بازیکن هم‌زمان، رقیب انسانی پیدا نمی‌شود و ورودی سکه‌ای معنا ندارد", "هوش مصنوعی به‌عنوان جایگزین؛ چالش روزانه و حالت تک‌نفره به‌عنوان حلقهٔ اصلی انگلیسی"],
 ["تیم یک‌نفره، دو بازار", "توسعه، پشتیبانی، انتشار و بازاریابی دو محصول روی یک نفر؛ ساعت‌های کار با منطقه‌های زمانی متفاوت", "خدمات بیرونی انگلیسی در مدل؛ بررسی نفر دوم در گیت ماه ۶ اگر درآمد اجازه دهد"],
 ["وابستگی به تبلیغ", "حدود ٪" + fa((res["base"]["rev_split3"]["fa_ads"]+res["base"]["rev_split3"]["en_ads"])/b["rev"][2]*100) + " درآمد سال سوم از تبلیغ جایزه‌ای است", "رشد خرید و اشتراک؛ دو شبکهٔ تبلیغ (تپسل + ادموب) به‌جای یکی"],
 ["نوسان ارز", "هزینه‌ها تومانی‌اند و درآمد انگلیسی دلاری؛ مدل با قیمت و نرخ ثابت است. تضعیف ریال به نفع سود انگلیسی است ولی تورم هزینه‌ها را بالا می‌برد", "بازبینی بودجه در گیت‌ها"],
 ["مجوز فرهنگ لغت", "هر دو فرهنگ لغت (فارسی: Hunspell, ویکی‌واژه, OpenSubtitles؛ انگلیسی: بررسی نشده) برای انتشار تجاری بررسی نشده‌اند", "بررسی حقوقی پیش از ارائه؛ جایگزینی منبع در صورت نیاز"],
 ["نبود تحلیل رقبا", "نمی‌دانیم در دو ژانر چه نصب و امتیازی عادی است", "تکمیل قبل از ارائه به سرمایه‌گذار"],
 ["فرض بودن اعداد", "هیچ مقداری از بازار واقعی اندازه‌گیری نشده", "مرحلهٔ ۱ و گیت ماه ۶ دقیقاً برای همین طراحی شده"],
], "as")}
<p class="note">ریسک‌های ویرایش ۱ (تیم یک‌نفره، کارمزد کافه‌بازار و مایکت، تورم و ارز، قطعی اینترنت و تغییر قوانین) همچنان معتبرند و برای کوتاهی در اینجا تکرار نشده‌اند.</p>
</section>

<!-- ============================ 10 ============================ -->
<section class="page">
<header class="top"><span>طرح درآمدی و پیش‌بینی مالی</span><span>ویرایش ۲</span></header>
<h2>پیوست الف — بازسازی مدل ایرانی <span class="n">۱۰</span></h2>
<p>مدل ماهانهٔ ویرایش ۱ همراه سند منتشر نشده بود. برای افزودن بخش انگلیسی، بخش ایرانی را از مفروضات و نتایج چاپ‌شدهٔ ویرایش ۱ بازسازی و کالیبره کردم (نصب ارگانیک با رشد ٪۴ در سال اول و ٪۲ بعد از آن؛ دهان‌به‌دهان ٪۰٫۵ نصب‌های تجمعی با ۳ ماه تأخیر؛ ماندگاری با دم توانی؛ هزینهٔ زیرساخت ≈ ۱۰ میلیون ثابت + ۰٫۳۳ به‌ازای هر ۱٬۰۰۰ DAU + ۰٫۱۹ به‌ازای هر ۱٬۰۰۰ نصب). اختلاف با ارقام منتشرشده:</p>
{reconcile_table()}
<p class="note">در سال سوم (ستون‌های جدول) اختلاف‌ها حداکثر ٪{fa(max(abs(res["reconcile"][s_][k][2]/V1[s_][k][2]-1)*100 for s_ in S for k in ("inst","dau","rev","cost")))} است؛ در سال اول درآمد بازسازی‌شده تا ٪{fa(max((res["reconcile"][s_]["rev"][0]/V1[s_]["rev"][0]-1)*100 for s_ in S))} بیشتر است. ماه سربه‌سر بازسازی‌شده در سناریوی پایهٔ ایرانی ماه {fn(fa_only["first_profit"])} است، دو ماه دیرتر از ماه ۳۹ ویرایش ۱ (برون‌یابی). در سناریوی خوش‌بینانه ماه اولین سود در بازسازی ماه ۳ است (ویرایش ۱: ماه ۶)؛ برنامهٔ جذب آن را با گیت از ماه ۶ مدل کرده‌ام. این اختلاف‌ها روی نتیجهٔ ترکیبی اثر اندکی دارند، ولی ارقام ایرانی این سند دقیقاً برابر ویرایش ۱ نیستند.</p>
<p>کد مدل: <span class="ltr">output/investor/model/zanjir_model.py</span> (قابل اجرا؛ هر عدد این سند از آن می‌آید) و ساخت سند: <span class="ltr">build_report.py</span>.</p>
<h3>منابع</h3>
<ul class="note">
<li>{LTR("Game Dev Reports — Cafe Bazaar has 30M MAU and 30M gamers")} (۲۰۲۱) · {LTR("IMARC — Iran Gaming Market")} (۲۰۲۵) — از ویرایش ۱.</li>
<li>eCPM: {LTR("tuapppara.com")} (آمریکا اندروید ۲۰۲۵)، {LTR("blog.playio.co/mobile-game-ecpm-benchmarks-2026")}، {LTR("globalgamesforum.com — How is Your eCPM Doing")}، {LTR("monetizemore.com/blog/admob-monetization")} — همه تخمین ثانویه، بدون جدول رسمی ادموب.</li>
<li>CPI: {LTR("admiral.media/mobile-game-marketing-benchmarks")} (۲۰۲۵)؛ ماندگاری: {LTR("AppsFlyer, Q3 2022")} به نقل {LTR("appfollow.io")}.</li>
<li>کارمزد: {LTR("support.google.com/googleplay/android-developer/answer/112622")}.</li>
<li>تحریم: {LTR("cnbc.com (2017)")}، {LTR("mobileworldlive.com")}، {LTR("arabnews.com/node/2324401")}، {LTR("trend.az")} — قدیمی؛ سیاست جاری باید از خود گوگل و مشاور حقوقی تأیید شود.</li>
<li>نرخ دلار: بازار آزاد ۱۷ مهر ۱۴۰۵ از یادداشت‌های پروژه. همهٔ پیش‌بینی‌ها محاسبهٔ داخلی بر پایهٔ مفروضات بخش ۵ است و تضمین عملکرد نیست.</li>
</ul>
</section>
</body></html>"""

html_path = os.path.join(OUT, "zanjir-investor-plan-fa-v2.html")
open(html_path, "w", encoding="utf-8").write(html)
pdf_path = os.path.join(OUT, "zanjir-investor-plan-fa-v2.pdf")
subprocess.run(["google-chrome", "--headless=new", "--no-sandbox", "--disable-gpu", "--allow-file-access-from-files",
                "--no-pdf-header-footer", f"--print-to-pdf={pdf_path}", "file://" + html_path], check=True,
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
print("wrote", pdf_path)
