"""Zanjir revenue model v2 — Persian (Tapsell / Bazaar / Myket) + English (Google Play / AdMob).

The v1 investor PDF (zanjir-investor-plan-fa.pdf) was published without its model source, so the
Persian segment here is RE-DERIVED from the assumptions and outputs printed in that PDF and
calibrated to them (see `reconcile()`; deviations are a few percent). The English segment is new.

All money is in million toman at constant Mehr-1405 prices, FX fixed at 266,000 toman / USD
(same simplification as v1: no inflation, no FX drift).

Run:  python3 zanjir_model.py          -> prints headline tables and writes results.json
"""
import json
import numpy as np

FX = 266_000          # toman per USD (free market, 2026-10-09 per CLAUDE.md)
T = 60                # months simulated; the plan horizon is 36, the rest is extrapolation only
H = 36
DAU_MAU = 0.22
IAP_START = 3         # first month with in-app-purchase revenue (both segments)
FEE_BAZAAR = 0.30     # Bazaar / Myket cut (unconfirmed, as in v1)
FEE_PLAY = 0.15       # Google Play: 15% on first $1M/yr and on subscriptions (rest of world)
EN_REPATRIATION = 0.05  # assumed loss moving USD -> toman (exchange spread / transfer), unverified

SCEN = ["cons", "base", "opt"]
SCEN_FA = {"cons": "محافظه‌کارانه", "base": "پایه", "opt": "خوش‌بینانه"}

# ------------------------------------------------------------------ segment parameters
# retention = (D1, D7, D30); b = exponent of the power-law tail after day 30 (calibrated to v1's DAU)
FA = {
    "cons": dict(O=3000, CPI=20_000, viral=.18, w=.003, ret=(.30, .09, .04), b=.66,
                 ecpm=120_000, imps=1.0, buy=.008, spend=40_000, prem=.002, price=19_000),
    "base": dict(O=5000, CPI=12_000, viral=.30, w=.005, ret=(.35, .12, .05), b=.54,
                 ecpm=260_000, imps=1.5, buy=.015, spend=40_000, prem=.004, price=19_000),
    "opt":  dict(O=8000, CPI=8_000, viral=.45, w=.008, ret=(.40, .15, .07), b=.50,
                 ecpm=450_000, imps=2.0, buy=.025, spend=40_000, prem=.008, price=19_000),
}
# English: CPI / eCPM / spend in USD, converted below. eCPM = developer earnings per 1000 rewarded
# impressions as AdMob reports them (already net of AdMob's share), blended over the geo mix.
EN = {
    "cons": dict(O=1500, CPI=1.20, viral=.10, w=.0015, ret=(.25, .07, .025), b=.66,
                 ecpm=1.5, imps=1.0, buy=.003, spend=3.0, prem=.0007, price=2.99),
    "base": dict(O=3000, CPI=0.80, viral=.15, w=.0025, ret=(.29, .09, .035), b=.56,
                 ecpm=3.0, imps=1.5, buy=.006, spend=4.0, prem=.0015, price=2.99),
    "opt":  dict(O=6000, CPI=0.40, viral=.25, w=.004, ret=(.33, .12, .05), b=.50,
                 ecpm=5.0, imps=2.0, buy=.012, spend=5.0, prem=.0035, price=2.99),
}
# geo mix behind the English eCPM (share of rewarded impressions, eCPM in USD)
EN_GEO = {
    "cons": [("آمریکا/بریتانیا/کانادا/استرالیا", .08, 11.0), ("اروپای غربی", .07, 5.0), ("هند/فیلیپین/برزیل/نیجریه و مشابه", .85, .30)],
    "base": [("آمریکا/بریتانیا/کانادا/استرالیا", .15, 12.0), ("اروپای غربی", .10, 6.0), ("هند/فیلیپین/برزیل/نیجریه و مشابه", .75, .80)],
    "opt":  [("آمریکا/بریتانیا/کانادا/استرالیا", .25, 13.0), ("اروپای غربی", .15, 6.5), ("هند/فیلیپین/برزیل/نیجریه و مشابه", .60, 1.20)],
}

# ------------------------------------------------------------------ cost parameters (M toman / month)
FOUNDER0, FOUNDER_STEP = 45.0, 5.0     # +5 per year
OUTSOURCE_FA = 30.0
UA_TEST = 40.0          # Persian paid-UA test budget, M toman / month
EN_UA_TEST, EN_UA_MONTHS = 25.0, 6   # English: ~$95/month for 6 months only, to measure LTV/CPI; then 0 unless the gate opens
INFRA_FIXED_FA, INFRA_PER_KDAU, INFRA_PER_KINST = 10.0, 0.332, 0.188   # fitted to v1 cost lines (SMS ~ installs)
# English incremental costs, USD
EN_SETUP_USD = 2_000        # foreign entity + Play developer account + privacy policy / ToS. SUNK in the base case
                            # (the English app is assumed already published); charged only in the `setup` sensitivity
EN_ENTITY_USD = 100         # registered agent / accounting / bank, per month
EN_HOSTING_USD = 60         # foreign VPS (the Iran host cannot reach Google; also latency), per month
EN_OUTSOURCE_USD = 150      # ASO, English store copy, community, support, per month
usd = lambda x: x * FX / 1e6   # USD -> M toman


def fa_budget(scen):
    if scen == "opt":                       # gate opens early: 40M x4, 120M x1, then 200M
        return [40] * 4 + [120] + [200] * (T - 5)
    return [UA_TEST] * T


# ------------------------------------------------------------------ core mechanics
def _tail_curve(ret, b, n):
    r = np.zeros(n)
    pts = [(0, 1.0), (1, ret[0]), (7, ret[1]), (30, ret[2])]
    for d in range(n):
        if d <= 30:
            for (x0, y0), (x1, y1) in zip(pts[:-1], pts[1:]):
                if x0 <= d <= x1:
                    r[d] = np.exp(np.log(y0) + (np.log(y1) - np.log(y0)) * (d - x0) / (x1 - x0))
                    break
        else:
            r[d] = ret[2] * (30 / d) ** b
    return r


def retention_by_month(ret, b):
    r = _tail_curve(ret, b, 30 * T + 31)
    return np.array([r[30 * a:30 * a + 30].mean() for a in range(T)]), r


def installs(p, budget_m, cpi_toman):
    org, x = [], p["O"]
    for t in range(T):
        if t > 0:
            x *= 1.04 if t < 12 else 1.02
        org.append(x)
    inst, cum = np.zeros(T), np.zeros(T + 1)
    paid = np.zeros(T)
    for t in range(T):
        paid[t] = budget_m[t] * 1e6 / cpi_toman * (1 + p["viral"])
        wom = p["w"] * cum[t - 3] if t >= 3 else 0.0
        inst[t] = org[t] + paid[t] + wom
        cum[t + 1] = cum[t] + inst[t]
    return inst, paid


def arpdau_parts(p, fee, fx_mult, haircut=0.0):
    """toman per DAU per day: (ads, iap, premium). fx_mult converts price units to toman."""
    ads = p["imps"] * p["ecpm"] * fx_mult / 1000
    iap = p["buy"] * p["spend"] * fx_mult / 30 / DAU_MAU * (1 - fee)
    pr = p["prem"] * p["price"] * fx_mult / 30 / DAU_MAU * (1 - fee)
    k = 1 - haircut
    return ads * k, iap * k, pr * k


def segment(p, budget_m, fx_mult, fee, haircut=0.0, iap_start=IAP_START, ads_only=False):
    cpi = p["CPI"] * fx_mult
    inst, paid = installs(p, budget_m, cpi)
    rb, daily = retention_by_month(p["ret"], p["b"])
    dau = np.array([sum(inst[c] * rb[t - c] for c in range(t + 1)) for t in range(T)])
    ads, iap, pr = arpdau_parts(p, fee, fx_mult, haircut)
    m_ads = dau * 30 * ads / 1e6
    on = np.array([1.0 if (t + 1) >= iap_start and not ads_only else 0.0 for t in range(T)])
    m_iap, m_pr = dau * 30 * iap * on / 1e6, dau * 30 * pr * on / 1e6
    active_days = daily[:365].sum()
    full = ads + iap + pr
    return dict(inst=inst, paid=paid, dau=dau, ads=m_ads, iap=m_iap, prem=m_pr,
                rev=m_ads + m_iap + m_pr, arpdau=full, arpdau_parts=(ads, iap, pr),
                ltv=full * active_days, cpi=cpi, active_days=active_days)


def costs(fa, en, scen, en_on=True, en_variant=None):
    """returns dict of monthly cost arrays (M toman)."""
    v = en_variant or {}
    c = {}
    c["founder"] = np.array([FOUNDER0 + FOUNDER_STEP * (t // 12) for t in range(T)], float)
    c["outsource_fa"] = np.full(T, OUTSOURCE_FA)
    c["ua_fa"] = np.array(fa_budget(scen), float)
    c["infra_fa"] = INFRA_FIXED_FA + INFRA_PER_KDAU * fa["dau"] / 1000 + INFRA_PER_KINST * fa["inst"] / 1000
    z = np.zeros(T)
    if en_on:
        n = v.get("months", T)
        mask = np.array([1.0 if t < n else 0.0 for t in range(T)])
        no_entity = v.get("no_entity", False)
        c["en_entity"] = z + (0 if no_entity else usd(EN_ENTITY_USD)) * mask
        c["en_setup"] = z.copy()
        c["en_setup"][0] = usd(EN_SETUP_USD) if v.get("setup") else 0
        c["en_hosting"] = (0 if no_entity else usd(EN_HOSTING_USD) + INFRA_PER_KDAU * en["dau"] / 1000) * mask
        c["en_outsource"] = z + usd(EN_OUTSOURCE_USD) * mask
        ua = np.array([EN_UA_TEST if t < EN_UA_MONTHS else 0.0 for t in range(T)])
        if v.get("ua_full"): ua = np.full(T, UA_TEST)
        c["en_ua"] = (z if v.get("no_ua") else ua) * mask
    else:
        for k in ("en_entity", "en_setup", "en_hosting", "en_outsource", "en_ua"):
            c[k] = z
    c["total"] = sum(c.values())
    return c


def scenario(scen, en_on=True, en_over=None, en_variant=None, fa_over=None):
    pf = {**FA[scen], **(fa_over or {})}
    fa = segment(pf, fa_budget(scen), 1.0, FEE_BAZAAR)
    pe = {**EN[scen], **(en_over or {})}
    kw = {}
    if en_variant:
        if en_variant.get("ads_only"): kw["ads_only"] = True
    en_budget = [EN_UA_TEST if t < EN_UA_MONTHS else 0.0 for t in range(T)]
    if en_variant and en_variant.get("ua_full"): en_budget = [UA_TEST] * T
    if en_variant and en_variant.get("no_ua"): en_budget = [0.0] * T
    en = segment(pe, en_budget, FX, FEE_PLAY, EN_REPATRIATION, **kw)
    if en_variant and en_variant.get("rev_share"):      # publisher takes a share of net revenue
        for k in ("ads", "iap", "prem", "rev"):
            en[k] = en[k] * (1 - en_variant["rev_share"])
    if en_variant and "months" in en_variant:           # segment shut down after N months
        m = np.array([1.0 if t < en_variant["months"] else 0.0 for t in range(T)])
        for k in ("ads", "iap", "prem", "rev", "dau", "inst"):
            en[k] = en[k] * m
    if en_variant and en_variant.get("no_revenue"):     # revenue can't be repatriated
        for k in ("ads", "iap", "prem", "rev"):
            en[k] = en[k] * 0
    if not en_on:
        for k in ("ads", "iap", "prem", "rev", "dau", "inst"):
            en[k] = en[k] * 0
    c = costs(fa, en, scen, en_on, en_variant)
    net = fa["rev"] + en["rev"] - c["total"]
    return dict(fa=fa, en=en, cost=c, net=net, cum=np.cumsum(net))


def first_profit(net):
    for t in range(T):
        if net[t] >= 0 and all(net[t:t + 3] >= 0):
            return t + 1
    return None


def year(a, y):
    return float(a[y * 12:(y + 1) * 12].sum())


def summary(r):
    out = {}
    out["inst"] = [year(r["fa"]["inst"], y) + year(r["en"]["inst"], y) for y in range(3)]
    out["inst_fa"] = [year(r["fa"]["inst"], y) for y in range(3)]
    out["inst_en"] = [year(r["en"]["inst"], y) for y in range(3)]
    out["dau_end"] = [float(r["fa"]["dau"][11 + 12 * y] + r["en"]["dau"][11 + 12 * y]) for y in range(3)]
    out["dau_fa"] = [float(r["fa"]["dau"][11 + 12 * y]) for y in range(3)]
    out["dau_en"] = [float(r["en"]["dau"][11 + 12 * y]) for y in range(3)]
    out["rev"] = [year(r["fa"]["rev"], y) + year(r["en"]["rev"], y) for y in range(3)]
    out["rev_fa"] = [year(r["fa"]["rev"], y) for y in range(3)]
    out["rev_en"] = [year(r["en"]["rev"], y) for y in range(3)]
    out["cost"] = [year(r["cost"]["total"], y) for y in range(3)]
    out["net"] = [year(r["net"], y) for y in range(3)]
    out["cum36"] = float(r["cum"][H - 1])
    out["cum6"] = float(r["cum"][5])
    out["peak_need"] = float(-r["cum"].min())
    out["peak_month"] = int(r["cum"].argmin() + 1)
    out["first_profit"] = first_profit(r["net"])
    out["net_m36"] = float(r["net"][H - 1])
    out["rev_m24"] = float(r["fa"]["rev"][23] + r["en"]["rev"][23])
    out["cost_m24"] = float(r["cost"]["total"][23])
    out["cost24"] = float(r["cost"]["total"][:24].sum())
    out["rev24"] = float((r["fa"]["rev"][:24] + r["en"]["rev"][:24]).sum())
    out["dau6"] = float(r["fa"]["dau"][5] + r["en"]["dau"][5])
    out["inst6"] = float(r["fa"]["inst"][:6].sum() + r["en"]["inst"][:6].sum())
    out["dau_m36"] = float(r["fa"]["dau"][H - 1] + r["en"]["dau"][H - 1])
    return out


# ------------------------------------------------------------------ v1 published numbers (for reconcile)
V1 = {
    "cons": dict(inst=[73392, 93646, 114641], dau=[1758, 2750, 3755], rev=[67, 131, 187], cost=[1519, 1587, 1655], net=[-1452, -1456, -1468]),
    "base": dict(inst=[128554, 166089, 205938], dau=[4195, 6849, 9619], rev=[458, 936, 1385], cost=[1536, 1613, 1691], net=[-1078, -677, -305]),
    "opt":  dict(inst=[436478, 668650, 783904], dau=[21406, 37078, 51960], rev=[4148, 11077, 16602], cost=[2829, 3719, 3852], net=[1319, 7358, 12749]),
}


def reconcile():
    rows = {}
    for s in SCEN:
        r = scenario(s, en_on=False)
        sm = summary(r)
        rows[s] = dict(inst=sm["inst"], dau=sm["dau_end"], rev=sm["rev"], cost=sm["cost"], net=sm["net"],
                       cum36=sm["cum36"], first_profit=sm["first_profit"], peak=sm["peak_need"], pm=sm["peak_month"])
    return rows


def pct(a, b): return (a / b - 1) * 100


SENS = [  # (label, kwargs for scenario('base'))
    ("سناریوی پایهٔ ترکیبی (بدون تغییر)", dict()),
    ("فقط ایرانی (بدون نسخهٔ انگلیسی)", dict(en_on=False)),
    ("انگلیسی فقط با تبلیغ (بدون خرید درون‌برنامه‌ای)", dict(en_variant=dict(ads_only=True))),
    ("eCPM انگلیسی دو برابر (۶ دلار)", dict(en_over=dict(ecpm=6.0))),
    ("eCPM انگلیسی نصف (۱٫۵ دلار)", dict(en_over=dict(ecpm=1.5))),
    ("نصب ارگانیک انگلیسی دو برابر", dict(en_over=dict(O=6000))),
    ("نصب ارگانیک انگلیسی نصف", dict(en_over=dict(O=1500))),
    ("خریداران انگلیسی از ٪۰٫۶ به ٪۱٫۲", dict(en_over=dict(buy=.012))),
    ("بدون هیچ تبلیغ پولی انگلیسی (حتی آزمایشی)", dict(en_variant=dict(no_ua=True))),
    ("تبلیغ پولی انگلیسی ۴۰ میلیون در ماه، همیشگی", dict(en_variant=dict(ua_full=True))),
    ("راه‌اندازی انگلیسی هنوز انجام نشده: شرکت خارجی و حساب‌ها (+۲٬۰۰۰ دلار)", dict(en_variant=dict(setup=True))),
    ("انتشار از طریق ناشر خارجی (٪۳۰ سهم ناشر، بدون شرکت و میزبان خارجی)", dict(en_variant=dict(rev_share=.30, no_entity=True))),
    ("انتقال درآمد دلاری ممکن نشد: ۶ ماه هزینه، بدون درآمد، توقف", dict(en_variant=dict(no_revenue=True, months=6))),
    ("هر دو ضربه: eCPM انگلیسی نصف و ارگانیک انگلیسی نصف", dict(en_over=dict(ecpm=1.5, O=1500))),
]


def sensitivity():
    rows = []
    for label, kw in SENS:
        r = scenario("base", **kw)
        sm = summary(r)
        rows.append(dict(label=label, net3=sm["net"][2], net_m36=sm["net_m36"], first=sm["first_profit"],
                         peak=sm["peak_need"], rev3=sm["rev"][2]))
    return rows


def main():
    res = {"reconcile": reconcile(), "sens": sensitivity()}
    for s in SCEN:
        r = scenario(s)
        res[s] = summary(r)
        res[s]["fa_arpdau"] = r["fa"]["arpdau"]; res[s]["en_arpdau"] = r["en"]["arpdau"]
        res[s]["en_arpdau_parts"] = r["en"]["arpdau_parts"]
        res[s]["fa_arpdau_parts"] = r["fa"]["arpdau_parts"]
        res[s]["en_ltv"] = r["en"]["ltv"]; res[s]["fa_ltv"] = r["fa"]["ltv"]
        res[s]["en_ltv_cpi"] = r["en"]["ltv"] / r["en"]["cpi"]
        res[s]["fa_ltv_cpi"] = r["fa"]["ltv"] / r["fa"]["cpi"]
        res[s]["en_cpi"] = r["en"]["cpi"]; res[s]["fa_cpi"] = r["fa"]["cpi"]
        res[s]["series"] = dict(
            cum=r["cum"].tolist(), net=r["net"].tolist(),
            rev_fa=r["fa"]["rev"].tolist(), rev_en=r["en"]["rev"].tolist(), cost=r["cost"]["total"].tolist(),
            dau_fa=r["fa"]["dau"].tolist(), dau_en=r["en"]["dau"].tolist())
        res[s]["cost_split24"] = {k: float(v[:24].sum()) for k, v in r["cost"].items()}
        res[s]["cost_split12"] = {k: float(v[:12].sum()) for k, v in r["cost"].items()}
        res[s]["rev_split3"] = dict(fa_ads=year(r["fa"]["ads"], 2), fa_iap=year(r["fa"]["iap"], 2) + year(r["fa"]["prem"], 2),
                                    en_ads=year(r["en"]["ads"], 2), en_iap=year(r["en"]["iap"], 2) + year(r["en"]["prem"], 2))
        # persian-only series for the comparison line
        r0 = scenario(s, en_on=False)
        res[s]["series"]["cum_fa_only"] = r0["cum"].tolist()
        res[s]["fa_only"] = summary(r0)
    json.dump(res, open(__file__.replace("zanjir_model.py", "results.json"), "w"), ensure_ascii=False, indent=1)
    return res


if __name__ == "__main__":
    res = main()
    print("== reconcile (Persian-only rebuilt vs v1 published) ==")
    for s in SCEN:
        a, v = res["reconcile"][s], V1[s]
        print(s, "inst", [f"{pct(x, y):+.0f}%" for x, y in zip(a["inst"], v["inst"])],
              "dau", [f"{pct(x, y):+.0f}%" for x, y in zip(a["dau"], v["dau"])],
              "rev", [f"{pct(x, y):+.0f}%" for x, y in zip(a["rev"], v["rev"])],
              "cost", [f"{pct(x, y):+.0f}%" for x, y in zip(a["cost"], v["cost"])],
              "net", [round(x) for x in a["net"]], "v1", v["net"],
              "cum36", round(a["cum36"]), "first_profit", a["first_profit"], "peak", round(a["peak"]), "@", a["pm"])
    print("\n== combined ==")
    for s in SCEN:
        m = res[s]
        print(s, "inst", [round(x) for x in m["inst"]], "dau", [round(x) for x in m["dau_end"]], "(en", [round(x) for x in m["dau_en"]], ")")
        print("   rev", [round(x) for x in m["rev"]], "(en", [round(x) for x in m["rev_en"]], ") cost", [round(x) for x in m["cost"]],
              "net", [round(x) for x in m["net"]])
        print("   cum36", round(m["cum36"]), "peak", round(m["peak_need"]), "@", m["peak_month"], "first profit", m["first_profit"],
              "cum6", round(m["cum6"]), "m24 rev/cost", round(m["rev_m24"]), round(m["cost_m24"]),
              "en ARPDAU toman", round(m["en_arpdau"]), "$", round(m["en_arpdau"] / FX, 4), "LTV/CPI en", round(m["en_ltv_cpi"], 2), "fa", round(m["fa_ltv_cpi"], 2))
    print("\n== sensitivity (base) ==")
    for r in res["sens"]:
        print(f"{r['label'][:60]:60s} net3 {r['net3']:8.0f}  m36 {r['net_m36']:6.0f}  first {r['first']}  peak {r['peak']:.0f}")
