# new_estim_engine.py
"""
Moteur de calcul EstimBatiment v2 — basé sur EstimType2.xlsx.

Produit 5 sorties :
  1. estimation      — devis complet (calcul A:E + open col I + tous modules)
  2. detail_materiaux — quantités de matériaux (feuille Materiaux)
  3. main_oeuvre     — main d'œuvre (calcul F×D, G×H, I×J)
  4. gros_oeuvre     — phase GO (calcul + open col F + Elec G + Plomb G + Toiture)
  5. finition        — phase finition (Elec F + Plomb F + Peinture + Revetement + open col H)
"""

import sys, os, re, math
_dir = os.path.dirname(os.path.abspath(__file__))
if _dir not in sys.path:
    sys.path.insert(0, _dir)

from expression_engine import load_engine, _to_float

ROMAN_SET = {"I","II","III","IV","V","VI","VII","VIII","IX","X","XI","XII"}


# ─── Public API ───────────────────────────────────────────────────────────────

def _precalculate_calcul(engine, wb) -> None:
    """
    Pré-évalue les expressions des colonnes D, G, I de la feuille calcul
    et stocke les résultats dans engine._cell_cache.

    Nécessaire car la feuille Materiaux référence ces cellules via
    des expressions du type  D10{calcul}*B7{cf}  (où D10 contient
    une expression personnalisée, pas une formule Excel).
    """
    ws = wb["calcul"]
    # Colonnes qui contiennent des expressions évaluables
    cols_to_precalc = [('D', 4), ('G', 7), ('I', 9)]

    for r in range(1, ws.max_row + 1):
        for col_letter, col_idx in cols_to_precalc:
            raw = ws.cell(r, col_idx).value
            if raw is None:
                continue
            s = str(raw).strip()
            if not s or s in ('QT', 'PU', 'Maçon', 'Coffrage', 'Feraillage'):
                continue
            val = engine.evaluate(s)
            # Clé identique à celle utilisée par lookup_cell
            key = (col_letter.upper(), r, 'calcul')
            engine._cell_cache[key] = val


def compute_all(file_bytes: bytes) -> dict:
    """
    Retourne un dict :
      {
        "outputs": [
          {"id": "estimation", "label": "Estimation", "rows": [...]},
          ...
        ]
      }
    """
    engine, wb = load_engine(file_bytes)

    # Injecter les quantités calculées dans le cache avant de lire Materiaux
    _precalculate_calcul(engine, wb)

    calcul_sections = _parse_calcul(engine, wb)
    open_rows       = _parse_open(engine, wb)
    mat_result      = _parse_materiaux(engine, wb)

    simple_sheets = {
        "elec_g":   _parse_simple(engine, wb, "Electricite (G)"),
        "elec_f":   _parse_simple(engine, wb, "Electricite (F)"),
        "plomb_g":  _parse_simple(engine, wb, "Plomberie (G)"),
        "plomb_f":  _parse_simple(engine, wb, "Plomberie (F)"),
        "revetement": _parse_simple(engine, wb, "Revetement"),
        "peinture":   _parse_simple(engine, wb, "Peinture"),
        "toiture":    _parse_simple(engine, wb, "Toiture"),
    }

    return {
        "outputs": [
            _build_estimation(calcul_sections, open_rows, simple_sheets),
            _build_materiaux(mat_result),
            _build_main_oeuvre(calcul_sections),
            _build_gros_oeuvre(calcul_sections, open_rows, simple_sheets),
            _build_finition(open_rows, simple_sheets),
        ]
    }


# ─── Parsers par feuille ──────────────────────────────────────────────────────

def _parse_calcul(engine, wb) -> list:
    """
    Retourne une liste de sections :
      [{"num": "I", "title": "TERRASSEMENT", "items": [...]}]
    Chaque item :
      {"num", "description", "unite",
       "qty", "pu_estim", "montant_estim",
       "macon_qty", "macon_pu", "macon_total",
       "coffreur_qty", "coffreur_pu", "coffreur_total",
       "ferailleur_qty", "ferailleur_pu", "ferailleur_total"}
    """
    ws = wb["calcul"]
    sections = []
    current = None

    for r in range(1, ws.max_row + 1):
        a = ws.cell(r, 1).value
        b = ws.cell(r, 2).value
        c = ws.cell(r, 3).value
        d = ws.cell(r, 4).value
        e = ws.cell(r, 5).value
        f = ws.cell(r, 6).value   # maçon PU
        g = ws.cell(r, 7).value   # coffrage QT (expression)
        h = ws.cell(r, 8).value   # coffrage PU
        i = ws.cell(r, 9).value   # ferraillage QT (expression)
        j = ws.cell(r, 10).value  # ferraillage PU

        a_str = str(a).strip() if a is not None else ""
        b_str = str(b).strip() if b is not None else ""

        # En-tête de section (chiffre romain)
        if a_str in ROMAN_SET:
            current = {"num": a_str, "title": b_str, "items": []}
            sections.append(current)
            continue

        # Ligne vide ou sans section
        if not a_str or current is None:
            continue

        # Ignorer la ligne de labels PU/QT
        if str(f).strip() in ("PU", "QT", "Maçon", "Coffrage", "Feraillage"):
            continue

        qty = engine.evaluate(d)
        pu_estim = _to_float(e)
        montant_estim = qty * pu_estim

        item = {
            "num":           a_str,
            "description":   b_str,
            "unite":         str(c).strip() if c else "",
            "qty":           qty,
            "pu_estim":      pu_estim,
            "montant_estim": montant_estim,
        }

        # Maçon : PU en col F × quantité calcul (col D)
        f_val = _to_float(f)
        if f_val:
            item["macon_qty"]   = qty
            item["macon_pu"]    = f_val
            item["macon_total"] = qty * f_val

        # Coffrage : QT en col G (expression) × PU en col H
        g_expr = str(g).strip() if g else ""
        h_val  = _to_float(h)
        if g_expr and g_expr not in ("", "QT", "0") and h_val:
            g_qty = engine.evaluate(g)
            if g_qty:
                item["coffreur_qty"]   = g_qty
                item["coffreur_pu"]    = h_val
                item["coffreur_total"] = g_qty * h_val

        # Ferraillage : QT en col I (expression) × PU en col J
        i_expr = str(i).strip() if i else ""
        j_val  = _to_float(j)
        if i_expr and i_expr not in ("", "QT", "0") and j_val:
            i_qty = engine.evaluate(i)
            if i_qty:
                item["ferailleur_qty"]   = i_qty
                item["ferailleur_pu"]    = j_val
                item["ferailleur_total"] = i_qty * j_val

        current["items"].append(item)

    return sections


def _cell_val(engine, ws_expr, ws_vals, row, col) -> float:
    """
    Lit la valeur d'une cellule.
    - Si la cellule contient une formule Excel (commence par '=') → valeur pré-calculée (data_only).
    - Sinon → évalue avec le moteur d'expressions personnalisées.
    """
    expr = ws_expr.cell(row, col).value
    if expr is None:
        return 0.0
    s = str(expr).strip()
    if s.startswith('='):
        return _to_float(ws_vals.cell(row, col).value)
    return engine.evaluate(s)


def _parse_open(engine, wb) -> list:
    """
    Feuille open :
      col A=désignation, B=l, C=h, D=nombre
      col F=prix GO, col H=prix Finition, col I=prix clé en main
    Les colonnes F/H/I contiennent des formules Excel → utiliser data_only=True.
    """
    ws_expr = wb["open"]
    ws_vals = engine._wb["open"]
    rows = []
    for r in range(2, ws_expr.max_row + 1):
        a = ws_expr.cell(r, 1).value  # désignation
        b = ws_expr.cell(r, 2).value  # longueur
        c = ws_expr.cell(r, 3).value  # hauteur
        d = ws_expr.cell(r, 4).value  # nombre

        if not a:
            continue

        l_val = _to_float(b)
        h_val = _to_float(c)
        nb    = _to_float(d)
        desc  = f"{a} {l_val:.1f}×{h_val:.1f}" if l_val and h_val else str(a)

        rows.append({
            "description":  desc,
            "unite":        "u",
            "nombre":       nb,
            "prix_go":  _to_float(ws_vals.cell(r, 6).value),
            "prix_fin": _to_float(ws_vals.cell(r, 8).value),
            "prix_cle": _to_float(ws_vals.cell(r, 9).value),
        })
    return rows


def _parse_simple(engine, wb, sheet_name: str) -> list:
    """
    Feuilles simples (Elec G/F, Plomb G/F, Revetement, Peinture, Toiture).
    Structure : A=désignation, B=unité, C=quantité, D=prix unitaire
    Ligne 1 peut être un en-tête de section (chiffre romain ou "Designation").
    """
    if sheet_name not in wb.sheetnames:
        return []

    ws = wb[sheet_name]
    rows = []
    section_hdr = None

    for r in range(1, ws.max_row + 1):
        a = ws.cell(r, 1).value
        b = ws.cell(r, 2).value
        c = ws.cell(r, 3).value
        d = ws.cell(r, 4).value
        e = ws.cell(r, 5).value  # présent dans Toiture, Peinture, Revetement

        a_str = str(a).strip() if a is not None else ""
        b_str = str(b).strip() if b is not None else ""

        # En-tête de section (chiffre romain)
        if a_str in ROMAN_SET:
            section_hdr = {"num": a_str, "title": b_str}
            continue

        # Ligne de labels ("Designation", "Unité"…)
        if b_str.lower() in ("unité", "unite", "u", ""):
            if a_str.lower() in ("designation", "désignation", ""):
                continue

        if not a_str:
            continue

        # Revetement/Peinture/Toiture : structure A=num, B=desc, C=unité, D=qty_expr, E=PU
        if e is not None:
            desc   = b_str
            unite  = str(c).strip() if c else ""
            qty    = engine.evaluate(d)
            pu_val = _to_float(e)
        else:
            # Electricite/Plomberie : A=desc, B=unité, C=nombre, D=PU
            desc   = a_str
            unite  = b_str
            qty    = _to_float(c)
            pu_val = _to_float(d)

        if not desc or (qty == 0 and pu_val == 0):
            continue

        rows.append({
            "section_hdr":  section_hdr,
            "num":          a_str if e is not None else "",
            "description":  desc,
            "unite":        unite,
            "quantite":     qty,
            "pu":           pu_val,
            "montant":      qty * pu_val,
        })

    return rows


def _extract_calcul_row(expr_str: str):
    """Extrait le numéro de ligne calcul depuis une expression comme D16{calcul}*D15{cf}/50."""
    m = re.search(r'[A-Za-z]+(\d+)\{calcul\}', expr_str, re.IGNORECASE)
    if m:
        return int(m.group(1))
    m = re.search(r"'?calcul'?!?\s*[A-Za-z]+(\d+)", expr_str, re.IGNORECASE)
    if m:
        return int(m.group(1))
    return None


def _compute_resume(headers: list, totals: list) -> list:
    """
    Calcule le résumé d'approvisionnement à partir des totaux par matériau.
    Retourne une liste de dicts : {materiau, total, commande}.
    """
    # Règles par matériau (normalisation du nom en minuscule)
    # (label, unité_total, fn_commande)
    _RULES = {
        "ciment":   ("Sacs de ciment  (50 kg/sac → tonnes)",
                     lambda t: f"{t:,.2f} sacs",
                     lambda t: f"→  {math.ceil(t * 50 / 1000)} t"),
        "brique":   ("Briques",
                     lambda t: f"{t:,.2f} nb",
                     lambda t: f"→  {math.ceil(t)}"),
        "hourdi":   ("Hourdis",
                     lambda t: f"{t:,.2f} nb",
                     lambda t: f"→  {math.ceil(t)}"),
        "sable":    ("Sable  (camions 28 m³)",
                     lambda t: f"{t:,.2f} m³",
                     lambda t: f"→  {math.ceil(t / 28)} camions"),
        "granite":  ("Granite  (camions 28 m³)",
                     lambda t: f"{t:,.2f} m³",
                     lambda t: f"→  {math.ceil(t / 28)} camions"),
        "planche":  ("Planches",
                     lambda t: f"{t:,.2f} nb",
                     lambda t: f"→  {math.ceil(t)} planches"),
        "eau":      ("Eau",
                     lambda t: f"{t:,.2f} m³",
                     lambda t: f"→  {round(t, 1)} m³"),
        "terre":    ("Terre  (camions 28 m³)",
                     lambda t: f"{t:,.2f} m³",
                     lambda t: f"→  {math.ceil(t / 28)} camions"),
    }

    resume = []
    for h, total in zip(headers, totals):
        h_norm = h.lower().strip().rstrip("s")  # brique/briques → brique

        # Aciers (ha6, ha8, ha10, ha12, ha14, fer...)
        if h_norm.startswith("ha") or h_norm.startswith("fer"):
            barres = math.ceil(total / 12) if total else 0
            resume.append({
                "materiau": f"Fers {h}  (barres 12 m)",
                "total":    f"{total:,.2f} ml",
                "commande": f"→  {barres} barres",
            })
            continue

        key = h_norm
        if key == "briques": key = "brique"
        if key == "hourdis": key = "hourdi"
        if key == "granites": key = "granite"

        if key in _RULES:
            label, fmt_total, fmt_cmd = _RULES[key]
            resume.append({
                "materiau": label,
                "total":    fmt_total(total),
                "commande": fmt_cmd(total),
            })

    return resume


def _parse_materiaux(engine, wb) -> dict:
    """
    Feuille Materiaux.
    - Ligne 1  : en-têtes matériaux (col 1 = ciment, col 2 = brique, …)
    - Lignes 2+: quantités évaluées (expressions custom ou formules Excel)
    - Descriptions : récupérées depuis la feuille calcul par numéro de ligne
    """
    ws_expr = wb["Materiaux"]
    ws_vals = engine._wb["Materiaux"]

    # ── En-têtes : toutes les colonnes à partir de col 1 ──────────────────────
    headers = []
    for c in range(1, ws_expr.max_column + 1):
        v = ws_expr.cell(1, c).value
        if v and str(v).strip():
            headers.append(str(v).strip())
        else:
            break

    n_cols = len(headers)

    # ── Descriptions depuis la feuille calcul (match par ligne) ───────────────
    calcul_desc = {}
    ws_c = wb["calcul"]
    for r in range(1, ws_c.max_row + 1):
        b = ws_c.cell(r, 2).value
        if b and str(b).strip() and str(b).strip() not in ROMAN_SET:
            calcul_desc[r] = str(b).strip()

    rows   = []
    totals = [0.0] * n_cols

    for r in range(2, ws_expr.max_row + 1):
        values         = []
        has_data       = False
        calcul_row_ref = None

        for c in range(1, n_cols + 1):
            raw = ws_expr.cell(r, c).value
            val = _cell_val(engine, ws_expr, ws_vals, r, c)
            values.append(val)
            if val:
                has_data = True
                totals[c - 1] += val
            # Extraire la référence de ligne calcul depuis l'expression
            if calcul_row_ref is None and raw:
                calcul_row_ref = _extract_calcul_row(str(raw))

        if not has_data:
            continue

        # Description : calcul!B{ligne} si trouvée, sinon fallback
        if calcul_row_ref:
            desc = calcul_desc.get(calcul_row_ref, f"Ligne {calcul_row_ref}")
        else:
            desc = calcul_desc.get(r, f"Ligne {r}")

        rows.append({
            "row":         r,
            "description": desc,
            "values":      [round(v, 3) for v in values],
        })

    totals_rounded = [round(t, 2) for t in totals]
    resume = _compute_resume(headers, totals_rounded)

    return {
        "headers": headers,
        "rows":    rows,
        "totals":  totals_rounded,
        "resume":  resume,
    }


# ─── Builders de sorties ──────────────────────────────────────────────────────

def _row_section(num: str, title: str):
    return {"type": "section_hdr", "num": num, "description": title,
            "unite": None, "quantite": None, "pu": None, "montant": None}


def _row_item(num, desc, unite, qty, pu, montant):
    return {"type": "item", "num": str(num), "description": desc,
            "unite": unite or "", "quantite": round(qty, 3),
            "pu": round(pu, 0), "montant": round(montant, 0)}


def _row_total(label: str, montant: float):
    return {"type": "section_total", "num": label, "description": "",
            "unite": None, "quantite": None, "pu": None,
            "montant": round(montant, 0)}


def _row_grand_total(montant: float):
    return {"type": "grand_total", "num": "", "description": "TOTAL GÉNÉRAL HTVA",
            "unite": None, "quantite": None, "pu": None,
            "montant": round(montant, 0)}


def _rows_from_calcul(sections):
    """Convertit les sections calcul en lignes de sortie."""
    rows = []
    for sec in sections:
        rows.append(_row_section(sec["num"], sec["title"]))
        total_sec = 0.0
        for it in sec["items"]:
            rows.append(_row_item(
                it["num"], it["description"], it["unite"],
                it["qty"], it["pu_estim"], it["montant_estim"]
            ))
            total_sec += it["montant_estim"]
        rows.append(_row_total(f"TOTAL {sec['num']}", total_sec))
    return rows


def _rows_from_simple(simple_rows, section_num: str, section_title: str):
    """Convertit les lignes d'une feuille simple en lignes de sortie."""
    rows = []
    rows.append(_row_section(section_num, section_title))
    total = 0.0
    for r in simple_rows:
        rows.append(_row_item(
            r["num"], r["description"], r["unite"],
            r["quantite"], r["pu"], r["montant"]
        ))
        total += r["montant"]
    rows.append(_row_total(f"TOTAL {section_num}", total))
    return rows, total


def _rows_from_open(open_rows, price_key: str, section_num: str, section_title: str):
    rows = [_row_section(section_num, section_title)]
    total = 0.0
    for r in open_rows:
        pu = r[price_key]
        qty = r["nombre"]
        montant = qty * pu
        rows.append(_row_item("", r["description"], r["unite"], qty, pu, montant))
        total += montant
    rows.append(_row_total(f"TOTAL {section_num}", total))
    return rows, total


# ── 1. ESTIMATION ─────────────────────────────────────────────────────────────

def _build_estimation(calcul_sections, open_rows, ss):
    rows = _rows_from_calcul(calcul_sections)
    grand_total = sum(
        it["montant_estim"]
        for sec in calcul_sections for it in sec["items"]
    )

    # Menuiserie (open col I)
    r_open, t = _rows_from_open(open_rows, "prix_cle", "IV", "MENUISERIE")
    rows += r_open; grand_total += t

    # Electricité G+F combinés
    elec_rows = ss["elec_g"] + ss["elec_f"]
    r_elec, t = _rows_from_simple(elec_rows, "V", "ELECTRICITE")
    rows += r_elec; grand_total += t

    # Plomberie G+F combinés
    plomb_rows = ss["plomb_g"] + ss["plomb_f"]
    r_plomb, t = _rows_from_simple(plomb_rows, "VI", "PLOMBERIE")
    rows += r_plomb; grand_total += t

    # Revetement
    r_rev, t = _rows_from_simple(ss["revetement"], "VII", "REVETEMENT")
    rows += r_rev; grand_total += t

    # Peinture
    r_pein, t = _rows_from_simple(ss["peinture"], "VIII", "PEINTURE")
    rows += r_pein; grand_total += t

    # Toiture
    r_toit, t = _rows_from_simple(ss["toiture"], "IX", "TOITURE")
    rows += r_toit; grand_total += t

    rows.append(_row_grand_total(grand_total))
    return {"id": "estimation", "label": "Estimation", "rows": rows}


# ── 2. DÉTAIL MATÉRIAUX ───────────────────────────────────────────────────────

def _build_materiaux(mat_result):
    headers = mat_result["headers"]
    rows = []

    # En-tête colonnes
    rows.append({
        "type": "mat_header",
        "headers": headers,
        "num": "", "description": "Élément de construction",
        "unite": None, "quantite": None, "pu": None, "montant": None,
        "values": None,
    })

    # Lignes de quantités
    for r in mat_result["rows"]:
        rows.append({
            "type": "mat_item",
            "num": str(r["row"]),
            "description": r["description"],
            "values": r["values"],
            "unite": None, "quantite": None, "pu": None, "montant": None,
        })

    # Ligne totaux
    rows.append({
        "type": "mat_total",
        "num": "", "description": "TOTAUX",
        "values": mat_result["totals"],
        "unite": None, "quantite": None, "pu": None, "montant": None,
    })

    # Résumé d'approvisionnement
    rows.append({
        "type": "mat_resume_hdr",
        "num": "", "description": "RÉSUMÉ D'APPROVISIONNEMENT",
        "unite": None, "quantite": None, "pu": None, "montant": None,
        "values": None,
    })
    for item in mat_result["resume"]:
        rows.append({
            "type":    "mat_resume",
            "num":     item["materiau"],
            "description": item["total"],
            "unite":   item["commande"],
            "quantite": None, "pu": None, "montant": None,
            "values":  None,
        })

    return {"id": "detail_materiaux", "label": "Détail Matériaux", "rows": rows}


# ── 3. MAIN D'ŒUVRE ───────────────────────────────────────────────────────────

def _build_main_oeuvre(calcul_sections):
    rows = []
    grand_total = 0.0

    for trade, key_qty, key_pu, key_total in [
        ("A", "macon_qty",      "macon_pu",      "macon_total"),
        ("B", "coffreur_qty",   "coffreur_pu",   "coffreur_total"),
        ("C", "ferailleur_qty", "ferailleur_pu", "ferailleur_total"),
    ]:
        labels = {"A": "MAÇON", "B": "COFFRAGE", "C": "FERRAILLAGE"}
        rows.append(_row_section(trade, labels[trade]))
        trade_total = 0.0

        for sec in calcul_sections:
            for it in sec["items"]:
                if key_total not in it:
                    continue
                rows.append(_row_item(
                    it["num"], it["description"], it["unite"],
                    it[key_qty], it[key_pu], it[key_total]
                ))
                trade_total += it[key_total]

        rows.append(_row_total(f"TOTAL {trade}", trade_total))
        grand_total += trade_total

    rows.append(_row_grand_total(grand_total))
    return {"id": "main_oeuvre", "label": "Main d'Œuvre", "rows": rows}


# ── 4. GROS ŒUVRE ────────────────────────────────────────────────────────────

def _build_gros_oeuvre(calcul_sections, open_rows, ss):
    rows = _rows_from_calcul(calcul_sections)
    grand_total = sum(
        it["montant_estim"]
        for sec in calcul_sections for it in sec["items"]
    )

    r_open, t = _rows_from_open(open_rows, "prix_go", "IV", "MENUISERIE GROS ŒUVRE")
    rows += r_open; grand_total += t

    r_elec, t = _rows_from_simple(ss["elec_g"], "V", "ELECTRICITE (GROS ŒUVRE)")
    rows += r_elec; grand_total += t

    r_plomb, t = _rows_from_simple(ss["plomb_g"], "VI", "PLOMBERIE (GROS ŒUVRE)")
    rows += r_plomb; grand_total += t

    r_toit, t = _rows_from_simple(ss["toiture"], "VII", "TOITURE")
    rows += r_toit; grand_total += t

    rows.append(_row_grand_total(grand_total))
    return {"id": "gros_oeuvre", "label": "Gros Œuvre", "rows": rows}


# ── 5. FINITION ───────────────────────────────────────────────────────────────

def _build_finition(open_rows, ss):
    rows = []
    grand_total = 0.0

    r_open, t = _rows_from_open(open_rows, "prix_fin", "I", "MENUISERIE FINITION")
    rows += r_open; grand_total += t

    r_elec, t = _rows_from_simple(ss["elec_f"], "II", "ELECTRICITE (FINITION)")
    rows += r_elec; grand_total += t

    r_plomb, t = _rows_from_simple(ss["plomb_f"], "III", "PLOMBERIE (FINITION)")
    rows += r_plomb; grand_total += t

    r_rev, t = _rows_from_simple(ss["revetement"], "IV", "REVETEMENT")
    rows += r_rev; grand_total += t

    r_pein, t = _rows_from_simple(ss["peinture"], "V", "PEINTURE")
    rows += r_pein; grand_total += t

    rows.append(_row_grand_total(grand_total))
    return {"id": "finition", "label": "Finition", "rows": rows}
