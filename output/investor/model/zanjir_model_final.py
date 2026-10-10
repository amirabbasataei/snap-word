"""Zanjir revenue model — final investor edition.

Four segments, one shared cost base:
  ir  : Persian, Android, Cafe Bazaar + Myket, Tapsell ads, Iranian server (domestic stack)
  gp  : English, Google Play, AdMob, foreign server            (published by the founder's friend abroad)
  ase : English, App Store, AdMob, foreign server              (same friend account)
  asf : Persian, App Store (Iranian iPhone users + diaspora)   (same binary as ase, language option)

Rule for anything without data or with ambiguity: take the worst plausible value (see WORST below).
Market uncertainty is carried by the three scenarios. Money is million toman at constant Mehr-1405
prices, FX fixed at 266,000 toman / USD (free market, 16 Mehr 1405).

Run:  python3 zanjir_model_final.py      -> prints headline tables and writes results_final.json
"""
import json
import os
import numpy as np

FX = 266_000
T = 60                 # months simulated (36 = plan horizon, 37-60 extrapolation for payback only)
H = 36
DAU_MAU = 0.22
SCEN = ["cons", "base", "opt"]
SCEN_FA = {"cons": "بدبینانه", "base": "پایه", "opt": "خوش‌بینانه"}
usd = lambda x: x * FX / 1e6            # USD -> M toman

# ------------------------------------------------------------------ worst-case structural assumptions
WORST = dict(
    # Iran
    fee_bazaar=0.30,       # Bazaar/Myket cut. Bazaar has a 15% tier for sales < 1B toman/yr (since 1400); not assumed
    vat=0.12,              # VAT 1405 = 12%; assumed to come out of the developer's revenue (ads and purchases)
    lag_ads=0.20,          # Tapsell rates re-priced once a year under ~69% inflation -> ~20% average real erosion
    lag_iap=0.05,          # our own prices re-priced quarterly -> ~5%
    blackout=1 / 12,       # 2 months a year at half revenue (2026 had ~4 months of international blackout;
                           # the domestic stack keeps running on the national network, but ad demand falls)
    tax_ir=0.25,           # Iranian income tax on each profitable year, no loss carry-forward
    # International (friend publishes under his own Google Play / Apple accounts)
    fee_gp_coins=0.25,     # Google Play 2026: 20% for items with a gameplay effect (hints) + 5% billing fee
    fee_gp_subs=0.15,      # subscriptions: 9% + 5% (or legacy 15%) -> 15%
    fee_apple=0.15,        # App Store Small Business Program (< $1M/yr), coins and subscriptions
    friend_tax=0.35,       # income tax in the friend's (unknown) country, on gross payouts, no deductions
    friend_fee=0.20,       # friend's share for publishing, payouts and transfers (terms not agreed yet)
    transfer=0.10,         # exchange-house spread moving USD -> toman
    usd_cost_premium=0.10, # paying foreign costs from Iran (buying USD + transfer)
    lag_ir_cash=1,         # months between earning and cash: Bazaar / Tapsell settle monthly
    lag_intl_cash=2,       # Google / Apple / AdMob pay the following month, then the transfer
)
KEEP_INTL = (1 - WORST["friend_tax"]) * (1 - WORST["friend_fee"]) * (1 - WORST["transfer"])

LAUNCH = dict(ir=1, gp=5, ase=6, asf=6)      # the international build does not exist yet: 4-5 months of work
IAP_START = dict(ir=3, gp=5, ase=6, asf=6)   # Bazaar/Myket billing integrated in months 1-2

# ------------------------------------------------------------------ segment parameters
# ret = (D1, D7, D30); b = power-law tail exponent after day 30
IR = {
    "cons": dict(O=3000, CPI=20_000, viral=.18, w=.003, ret=(.30, .09, .04), b=.66,
                 ecpm=120_000, imps=1.0, buy=.008, spend=40_000, prem=.002, price=19_000),
    "base": dict(O=5000, CPI=12_000, viral=.30, w=.005, ret=(.35, .12, .05), b=.54,
                 ecpm=260_000, imps=1.5, buy=.015, spend=40_000, prem=.004, price=19_000),
    "opt":  dict(O=8000, CPI=8_000, viral=.45, w=.008, ret=(.40, .15, .07), b=.50,
                 ecpm=450_000, imps=2.0, buy=.025, spend=40_000, prem=.008, price=19_000),
}
# USD-denominated segments. eCPM = developer earnings per 1000 rewarded impressions (net of AdMob's share)
GP = {
    "cons": dict(O=1000, CPI=1.20, viral=.10, w=.0015, ret=(.25, .07, .025), b=.66,
                 ecpm=1.5, imps=1.0, buy=.003, spend=3.0, prem=.0007, price=2.99),
    "base": dict(O=2000, CPI=0.80, viral=.15, w=.0025, ret=(.29, .09, .035), b=.56,
                 ecpm=3.0, imps=1.5, buy=.006, spend=4.0, prem=.0015, price=2.99),
    "opt":  dict(O=5000, CPI=0.40, viral=.25, w=.004, ret=(.33, .12, .05), b=.50,
                 ecpm=5.0, imps=2.0, buy=.012, spend=5.0, prem=.0035, price=2.99),
}
# geo mix behind the blended eCPMs: (label, share of impressions, rewarded eCPM USD)
GEO = {
    "gp": {
        "cons": [("آمریکا، بریتانیا، کانادا، استرالیا", .08, 11.0), ("اروپای غربی", .07, 5.0), ("سایر کشورها (هند، فیلیپین، برزیل…)", .85, .30)],
        "base": [("آمریکا، بریتانیا، کانادا، استرالیا", .15, 12.0), ("اروپای غربی", .10, 6.0), ("سایر کشورها (هند، فیلیپین، برزیل…)", .75, .80)],
        "opt":  [("آمریکا، بریتانیا، کانادا، استرالیا", .25, 13.0), ("اروپای غربی", .15, 6.5), ("سایر کشورها (هند، فیلیپین، برزیل…)", .60, 1.20)],
    },
    "ase": {
        "cons": [("آمریکا، بریتانیا، کانادا، استرالیا", .20, 11.0), ("اروپای غربی", .10, 5.0), ("سایر کشورها", .70, .80)],
        "base": [("آمریکا، بریتانیا، کانادا، استرالیا", .30, 12.0), ("اروپای غربی", .15, 6.0), ("سایر کشورها", .55, 1.00)],
        "opt":  [("آمریکا، بریتانیا، کانادا، استرالیا", .45, 14.0), ("اروپای غربی", .15, 7.0), ("سایر کشورها", .40, 1.50)],
    },
}
blend = lambda mix: sum(sh * e for _, sh, e in mix)
ASE = {s: {**GP[s], "O": {"cons": 400, "base": 800, "opt": 2000}[s], "CPI": {"cons": 2.5, "base": 1.8, "opt": 1.0}[s],
           "ecpm": round(blend(GEO["ase"][s]), 2)} for s in SCEN}
for s in SCEN:
    GP[s]["ecpm"] = round(blend(GEO["gp"][s]), 2)

# Persian on the App Store: 75% of users assumed inside Iran -> no ad fill (AdMob does not serve Iran) and no
# purchases (USD-priced, gift-card Apple IDs): worst case zero. The 25% diaspora monetise like English iOS users.
ASF_DIASPORA = 0.25
ASF_BLACKOUT_DAU = 1 - 0.75 * 0.25            # inside-Iran users unreachable 3 months a year
ASF = {}
for s in SCEN:
    r = IR[s]["ret"]
    ASF[s] = dict(O={"cons": 500, "base": 1000, "opt": 2500}[s], CPI=ASE[s]["CPI"], viral=IR[s]["viral"], w=IR[s]["w"],
                  ret=tuple(round(x * 0.9, 4) for x in r), b=IR[s]["b"],
                  ecpm_diaspora={"cons": 4.0, "base": 6.0, "opt": 9.0}[s], imps=IR[s]["imps"],
                  buy=GP[s]["buy"], spend=GP[s]["spend"], prem=GP[s]["prem"], price=2.99)
    ASF[s]["ecpm"] = ASF[s]["ecpm_diaspora"] * ASF_DIASPORA
    ASF[s]["buy_eff"] = ASF[s]["buy"] * ASF_DIASPORA
    ASF[s]["prem_eff"] = ASF[s]["prem"] * ASF_DIASPORA

# ------------------------------------------------------------------ cost parameters (M toman / month unless noted)
FOUNDER0, FOUNDER_STEP = 45.0, 5.0       # founder pay, +5 per year (real)
OUTSOURCE_IR = 30.0                      # design, content, accounting, legal (Iran)
UA_IR = 40.0                             # Persian paid-UA test budget, months 1-6 only
UA_IR_TEST_MONTHS = 6                    # afterwards paid UA runs only where LTV/CPI > 1 (the optimistic case)
INFRA_FIXED, INFRA_PER_KDAU, INFRA_PER_KINST = 10.0, 0.332, 0.188
GP_UA_TEST, GP_UA_MONTHS = 15.0, 4       # English Google Play paid-UA test after launch, to measure CPI and LTV
INTL_HOST_USD = 60                       # foreign VPS (the international build cannot use the Iranian server)
INTL_OUTSOURCE_USD = 80                  # freelance English copy/support + ASO tooling for two stores
INTL_MISC_USD = 15                       # domain + site (privacy policy, app-ads.txt), bank fees
GOOGLE_DEV_USD, APPLE_DEV_USD = 25, 99   # Play one-time, Apple yearly
ONE_OFF = dict(                          # month -> (label, M toman)
    legal=(1, usd(600) * 1.1),           # written contract with the friend + one consult in his country
    intl_build=(2, usd(900) * 1.1),      # English word list proofreading, UI/store translation review, store art (m2-4)
    ios_kit=(2, 150.0),                  # second-hand Mac + test iPhone, bought in Iran
)


def fa_budget(scen):
    if scen == "opt":                    # Persian gate opens early: 40 x4, 120, then 200
        return [40.0] * 4 + [120.0] + [200.0] * (T - 5)
    return [UA_IR if t < UA_IR_TEST_MONTHS else 0.0 for t in range(T)]


# ------------------------------------------------------------------ mechanics
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


def installs(p, budget_m, cpi_toman, launch):
    inst, paid, cum = np.zeros(T), np.zeros(T), np.zeros(T + 1)
    x = p["O"]
    for t in range(T):
        age = t - (launch - 1)
        if age < 0:
            cum[t + 1] = cum[t]
            continue
        if age > 0:
            x *= 1.04 if age < 12 else 1.02
        paid[t] = budget_m[t] * 1e6 / cpi_toman * (1 + p["viral"])
        wom = p["w"] * cum[t - 3] if t >= 3 else 0.0
        inst[t] = x + paid[t] + wom
        cum[t + 1] = cum[t] + inst[t]
    return inst, paid


def segment(key, p, budget_m, scen, over=None):
    """returns monthly installs, DAU and net revenue (M toman, what reaches the Iranian business)."""
    o = over or {}
    W = {**WORST, **o.get("worst", {})}
    fxm = 1.0 if key == "ir" else FX
    launch = o.get("launch", LAUNCH[key])
    iap_start = max(o.get("iap_start", IAP_START[key]), launch)
    inst, paid = installs(p, budget_m, p["CPI"] * fxm, launch)
    rb, daily = retention_by_month(p["ret"], p["b"])
    dau = np.array([sum(inst[c] * rb[t - c] for c in range(t + 1)) for t in range(T)])
    if key == "asf":
        dau = dau * o.get("asf_dau", ASF_BLACKOUT_DAU)

    buy = p.get("buy_eff", p["buy"])
    prem = p.get("prem_eff", p["prem"])
    if key == "ir":
        fee_c = fee_s = W["fee_bazaar"]
        k_all = (1 / (1 + W["vat"])) * (1 - W["blackout"])
        k_ads, k_iap = k_all * (1 - W["lag_ads"]), k_all * (1 - W["lag_iap"])
    else:
        fee_c, fee_s = (W["fee_gp_coins"], W["fee_gp_subs"]) if key == "gp" else (W["fee_apple"], W["fee_apple"])
        keep = (1 - W["friend_tax"]) * (1 - W["friend_fee"]) * (1 - W["transfer"])
        k_ads = k_iap = keep
    ads = p["imps"] * p["ecpm"] * fxm / 1000 * k_ads                       # toman / DAU / day
    iap = buy * p["spend"] * fxm / 30 / DAU_MAU * (1 - fee_c) * k_iap
    pr = prem * p["price"] * fxm / 30 / DAU_MAU * (1 - fee_s) * k_iap
    on = np.array([1.0 if (t + 1) >= iap_start and not o.get("ads_only") else 0.0 for t in range(T)])
    m_ads = dau * 30 * ads / 1e6
    m_iap, m_pr = dau * 30 * iap * on / 1e6, dau * 30 * pr * on / 1e6
    gross_ads = p["imps"] * p["ecpm"] * fxm / 1000
    full = ads + iap + pr
    return dict(inst=inst, paid=paid, dau=dau, ads=m_ads, iap=m_iap, prem=m_pr, rev=m_ads + m_iap + m_pr,
                arpdau=full, parts=(ads, iap, pr), gross_ads=gross_ads,
                ltv=full * daily[:365].sum(), cpi=p["CPI"] * fxm)


def gp_budget(o):
    n0 = o.get("launch_gp", LAUNCH["gp"]) - 1
    if o.get("no_ua"):
        return [0.0] * T
    return [GP_UA_TEST if n0 <= t < n0 + GP_UA_MONTHS else 0.0 for t in range(T)]


def costs(seg, scen, o):
    prem = 1 + WORST["usd_cost_premium"]
    intl = not o.get("no_intl")
    stop = o.get("intl_stop")                      # month after which the international side is shut
    alive = np.array([1.0 if intl and (stop is None or t < stop) else 0.0 for t in range(T)])
    launch_gp = o.get("launch_gp", LAUNCH["gp"])
    c = {}
    c["founder"] = np.array([FOUNDER0 + FOUNDER_STEP * (t // 12) for t in range(T)], float) + o.get("founder_add", 0)
    c["outsource_ir"] = np.full(T, OUTSOURCE_IR)
    c["ua_ir"] = np.array(fa_budget(scen), float) * o.get("ua_ir_mult", 1.0)
    c["infra_ir"] = INFRA_FIXED + INFRA_PER_KDAU * seg["ir"]["dau"] / 1000 + INFRA_PER_KINST * seg["ir"]["inst"] / 1000
    intl_dau = seg["gp"]["dau"] + seg["ase"]["dau"] + seg["asf"]["dau"]
    pre = np.array([1.0 if t >= launch_gp - 2 else 0.0 for t in range(T)])          # server up a month before launch
    live = np.array([1.0 if t >= launch_gp - 1 else 0.0 for t in range(T)])
    c["intl_host"] = (usd(INTL_HOST_USD) * prem * pre + INFRA_PER_KDAU * intl_dau / 1000) * alive
    c["intl_outsource"] = usd(INTL_OUTSOURCE_USD) * prem * live * alive
    acc = np.zeros(T)
    acc += usd(INTL_MISC_USD) * prem * pre
    acc[launch_gp - 2] += usd(GOOGLE_DEV_USD) * prem
    for t in range(LAUNCH["ase"] - 1, T, 12):
        acc[t] += usd(APPLE_DEV_USD) * prem
    c["intl_accounts"] = acc * alive
    c["intl_ua"] = np.array(gp_budget(o)) * alive
    one = np.zeros(T)
    if intl:
        one[ONE_OFF["legal"][0] - 1] += ONE_OFF["legal"][1]
        for m in (2, 3, 4):
            one[m - 1] += ONE_OFF["intl_build"][1] / 3
        one[ONE_OFF["ios_kit"][0] - 1] += ONE_OFF["ios_kit"][1]
    c["one_off"] = one
    c["total"] = sum(c.values())
    return c


def scenario(scen, o=None):
    o = o or {}
    pir = {**IR[scen], **o.get("ir", {})}
    pgp = {**GP[scen], **o.get("gp", {})}
    pase = {**ASE[scen], **o.get("ase", {})}
    pasf = {**ASF[scen], **o.get("asf", {})}
    lg = o.get("launch_gp", LAUNCH["gp"])
    li = lg + (LAUNCH["ase"] - LAUNCH["gp"])
    seg = {
        "ir": segment("ir", pir, fa_budget(scen) if "ua_ir_mult" not in o else [x * o["ua_ir_mult"] for x in fa_budget(scen)], scen, o),
        "gp": segment("gp", pgp, gp_budget(o), scen, {**o, "launch": lg}),
        "ase": segment("ase", pase, [0.0] * T, scen, {**o, "launch": li}),
        "asf": segment("asf", pasf, [0.0] * T, scen, {**o, "launch": li}),
    }
    stop = o.get("intl_stop")
    for k in ("gp", "ase", "asf"):
        m = np.array([0.0 if o.get("no_intl") or (stop is not None and t >= stop) else 1.0 for t in range(T)])
        if o.get("intl_no_revenue"):
            for f in ("ads", "iap", "prem", "rev"):
                seg[k][f] = seg[k][f] * 0
        for f in ("ads", "iap", "prem", "rev", "dau", "inst"):
            seg[k][f] = seg[k][f] * m
    c = costs(seg, scen, o)
    rev_ir = seg["ir"]["rev"]
    rev_intl = seg["gp"]["rev"] + seg["ase"]["rev"] + seg["asf"]["rev"]
    rev = rev_ir + rev_intl
    ebit = rev - c["total"]
    # Iranian income tax on profitable years (accrual: spread over the year's months for the P&L)
    tax = np.zeros(T)
    tax_cash = np.zeros(T)
    for y in range(T // 12):
        prof = ebit[12 * y:12 * y + 12].sum()
        if prof > 0:
            tax[12 * y:12 * y + 12] = WORST["tax_ir"] * prof / 12
            if 12 * (y + 1) + 3 < T:
                tax_cash[12 * (y + 1) + 3] = WORST["tax_ir"] * prof
    net = ebit - tax
    # cash: revenue arrives with settlement lags; tax paid in month 4 of the following year
    li_, ln_ = WORST["lag_ir_cash"], WORST["lag_intl_cash"]
    cash_in = np.concatenate([np.zeros(li_), rev_ir[:-li_]]) + np.concatenate([np.zeros(ln_), rev_intl[:-ln_]])
    cash = cash_in - c["total"] - tax_cash
    return dict(seg=seg, cost=c, rev=rev, rev_ir=rev_ir, rev_intl=rev_intl, ebit=ebit, tax=tax, net=net,
                cash=cash, cum=np.cumsum(cash))


def first_profit(net):
    for t in range(T):
        if net[t] >= 0 and all(net[t:t + 3] >= 0):
            return t + 1
    return None


def payback(cum):
    """first month the cumulative cash position climbs back to zero after its trough."""
    lo = int(cum.argmin())
    for t in range(lo, T):
        if cum[t] >= 0:
            return t + 1
    return None


def year(a, y):
    return float(a[y * 12:(y + 1) * 12].sum())


def summary(r):
    s, out = r["seg"], {}
    for k in ("ir", "gp", "ase", "asf"):
        out[f"inst_{k}"] = [year(s[k]["inst"], y) for y in range(3)]
        out[f"dau_{k}"] = [float(s[k]["dau"][11 + 12 * y]) for y in range(3)]
        out[f"rev_{k}"] = [year(s[k]["rev"], y) for y in range(3)]
        out[f"ads_{k}"] = [year(s[k]["ads"], y) for y in range(3)]
        out[f"iap_{k}"] = [year(s[k]["iap"] + s[k]["prem"], y) for y in range(3)]
    out["inst"] = [sum(out[f"inst_{k}"][y] for k in ("ir", "gp", "ase", "asf")) for y in range(3)]
    out["dau"] = [sum(out[f"dau_{k}"][y] for k in ("ir", "gp", "ase", "asf")) for y in range(3)]
    out["rev"] = [year(r["rev"], y) for y in range(3)]
    out["rev_intl"] = [year(r["rev_intl"], y) for y in range(3)]
    out["cost"] = [year(r["cost"]["total"], y) for y in range(3)]
    out["ebit"] = [year(r["ebit"], y) for y in range(3)]
    out["tax"] = [year(r["tax"], y) for y in range(3)]
    out["net"] = [year(r["net"], y) for y in range(3)]
    out["cash"] = [year(r["cash"], y) for y in range(3)]
    out["cum36"] = float(r["cum"][H - 1])
    out["cum60"] = float(r["cum"][T - 1])
    out["cum6"] = float(r["cum"][5])
    out["peak_need"] = float(-r["cum"][:H].min())
    out["peak_need60"] = float(-r["cum"].min())
    out["peak_month"] = int(r["cum"].argmin() + 1)
    out["first_profit"] = first_profit(r["ebit"])
    out["payback"] = payback(r["cum"])
    out["ebit_m36"] = float(r["ebit"][H - 1])
    out["rev_m36"] = float(r["rev"][H - 1])
    out["cost_m36"] = float(r["cost"]["total"][H - 1])
    out["dau6"] = float(sum(s[k]["dau"][5] for k in s))
    out["dau6_ir"] = float(s["ir"]["dau"][5])
    out["inst6"] = float(sum(s[k]["inst"][:6].sum() for k in s))
    out["inst6_ir"] = float(s["ir"]["inst"][:6].sum())
    out["dau12_intl"] = float(s["gp"]["dau"][11] + s["ase"]["dau"][11] + s["asf"]["dau"][11])
    out["dau9_gp"] = float(s["gp"]["dau"][8])
    out["dau9_as"] = float(s["ase"]["dau"][8] + s["asf"]["dau"][8])
    return out


def unit(r):
    s = r["seg"]
    return {k: dict(arpdau=float(s[k]["arpdau"]), parts=[float(x) for x in s[k]["parts"]], ltv=float(s[k]["ltv"]),
                    cpi=float(s[k]["cpi"]), ltv_cpi=float(s[k]["ltv"] / s[k]["cpi"]), gross_ads=float(s[k]["gross_ads"]))
            for k in s}


SENS = [  # (label, overrides on the base scenario)
    ("سناریوی پایه (بدون تغییر)", {}),
    ("فقط ایران: بدون گوگل‌پلی و اپ‌استور", dict(no_intl=True)),
    ("دوست در کشوری بدون مالیات (مثلاً امارات) و بدون سهم", dict(worst=dict(friend_tax=0.0, friend_fee=0.0))),
    ("دوست بدون سهم، ولی مالیات ٪۳۵ پرداخت می‌شود", dict(worst=dict(friend_fee=0.0))),
    ("کارمزد کافه‌بازار ٪۱۵ (طرح فروش زیر ۱ میلیارد)", dict(worst=dict(fee_bazaar=0.15))),
    ("بدون اختلال قطعی اینترنت و با تعدیل به‌موقع نرخ تپسل", dict(worst=dict(blackout=0.0, lag_ads=0.0, lag_iap=0.0))),
    ("eCPM تپسل نصف (۱۳۰ هزار تومان)", dict(ir=dict(ecpm=130_000))),
    ("eCPM تپسل دو برابر (۵۲۰ هزار تومان)", dict(ir=dict(ecpm=520_000))),
    ("نصب ارگانیک ایرانی نصف", dict(ir=dict(O=2500))),
    ("نصب ارگانیک ایرانی دو برابر", dict(ir=dict(O=10000))),
    ("ماندگاری ایرانی یک پله بدتر (٪۳۰ / ٪۹ / ٪۴)", dict(ir=dict(ret=(.30, .09, .04), b=.66))),
    ("نصب ارگانیک گوگل‌پلی و اپ‌استور نصف", dict(gp=dict(O=1000), ase=dict(O=400), asf=dict(O=500))),
    ("همان، با بستن بخش خارجی در گیت ماه ۱۲", dict(gp=dict(O=1000), ase=dict(O=400), asf=dict(O=500), intl_stop=12)),
    ("نصب ارگانیک گوگل‌پلی و اپ‌استور دو برابر", dict(gp=dict(O=4000), ase=dict(O=1600), asf=dict(O=2000))),
    ("نسخهٔ بین‌المللی ۳ ماه دیرتر منتشر شود", dict(launch_gp=8)),
    ("حساب گوگل/اپل در ماه ۱۸ مسدود شود", dict(intl_stop=18)),
    ("درآمد دلاری هرگز به ایران نرسد؛ توقف در ماه ۱۲", dict(intl_no_revenue=True, intl_stop=12)),
    ("حقوق مؤسس ۷۰ میلیون (به‌جای ۴۵)", dict(founder_add=25.0)),
]


def sensitivity():
    rows = []
    for label, o in SENS:
        r = scenario("base", o)
        sm = summary(r)
        rows.append(dict(label=label, rev3=sm["rev"][2], ebit3=sm["ebit"][2], ebit_m36=sm["ebit_m36"],
                         first=sm["first_profit"], peak=sm["peak_need"], peak60=sm["peak_need60"],
                         payback=sm["payback"], cum36=sm["cum36"]))
    return rows


def main(write=True):
    res = {"sens": sensitivity(), "keep_intl": KEEP_INTL}
    for s in SCEN:
        r = scenario(s)
        res[s] = summary(r)
        res[s]["unit"] = unit(r)
        res[s]["series"] = dict(cum=r["cum"].tolist(), ebit=r["ebit"].tolist(), cash=r["cash"].tolist(),
                                rev_ir=r["rev_ir"].tolist(), rev_gp=r["seg"]["gp"]["rev"].tolist(),
                                rev_as=(r["seg"]["ase"]["rev"] + r["seg"]["asf"]["rev"]).tolist(),
                                cost=r["cost"]["total"].tolist())
        res[s]["cost_split"] = {k: [year(v, y) for y in range(3)] for k, v in r["cost"].items()}
        r0 = scenario(s, dict(no_intl=True))
        res[s]["ir_only"] = summary(r0)
        res[s]["series"]["cum_ir_only"] = r0["cum"].tolist()
    if write:
        json.dump(res, open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "results_final.json"), "w"),
                  ensure_ascii=False, indent=1)
    return res


if __name__ == "__main__":
    res = main()
    print("keep factor intl", round(KEEP_INTL, 3))
    for s in SCEN:
        m = res[s]
        print(f"\n== {s} ==")
        print(" inst ir/gp/ase/asf y3", [round(m[f'inst_{k}'][2]) for k in ('ir', 'gp', 'ase', 'asf')])
        print(" dau  y1..3", [round(x) for x in m["dau"]], " ir", [round(x) for x in m["dau_ir"]],
              " gp", [round(x) for x in m["dau_gp"]], " ase", [round(x) for x in m["dau_ase"]], " asf", [round(x) for x in m["dau_asf"]])
        print(" rev", [round(x) for x in m["rev"]], " ir", [round(x) for x in m["rev_ir"]], " gp", [round(x) for x in m["rev_gp"]],
              " ase", [round(x) for x in m["rev_ase"]], " asf", [round(x) for x in m["rev_asf"]])
        print(" cost", [round(x) for x in m["cost"]], " ebit", [round(x) for x in m["ebit"]], " tax", [round(x) for x in m["tax"]],
              " net", [round(x) for x in m["net"]])
        print(" cum6", round(m["cum6"]), "cum36", round(m["cum36"]), "cum60", round(m["cum60"]), "peak36", round(m["peak_need"]),
              "peak60", round(m["peak_need60"]), "@", m["peak_month"], "first profit", m["first_profit"], "payback", m["payback"])
        print(" ir-only cum36", round(m["ir_only"]["cum36"]), "peak", round(m["ir_only"]["peak_need60"]), "first", m["ir_only"]["first_profit"])
        for k, u in m["unit"].items():
            print(f"   {k}: arpdau {u['arpdau']:.0f} parts {[round(x) for x in u['parts']]} ltv/cpi {u['ltv_cpi']:.2f}")
    print("\n== sensitivity (base) ==")
    for r in res["sens"]:
        print(f"{r['label'][:55]:55s} rev3 {r['rev3']:7.0f} ebit3 {r['ebit3']:7.0f} m36 {r['ebit_m36']:6.0f} first {r['first']} "
              f"peak36 {r['peak']:.0f} peak60 {r['peak60']:.0f} payback {r['payback']}")
