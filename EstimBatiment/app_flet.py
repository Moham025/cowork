# app_flet.py
"""
Interface graphique Flet pour EstimBatiment.
- Import du fichier Excel source
- Lancement du calcul
- Affichage du résultat dans une page modale avec option de téléchargement
"""
import flet as ft
import os
import threading
import sys

# S'assurer que le dossier courant est dans le path
_dir = os.path.dirname(os.path.abspath(__file__))
if _dir not in sys.path:
    sys.path.insert(0, _dir)

DEFAULT_FILE = r"D:\BOLO\9-EstimBatiment\EstimType.xlsx"


def main(page: ft.Page):
    page.title = "EstimBatiment"
    page.theme_mode = ft.ThemeMode.LIGHT
    page.bgcolor = ft.Colors.GREY_100
    page.window.width = 820
    page.window.height = 580
    page.window.resizable = True
    page.padding = 0

    # ── État de l'application ─────────────────────────────────────────────────
    state = {
        "input_path": DEFAULT_FILE if os.path.exists(DEFAULT_FILE) else "",
        "output_io": None,
        "output_filename": None,
        "blocs_count": 0,
    }

    # ── Références UI ─────────────────────────────────────────────────────────
    file_path_text = ft.Text(
        state["input_path"] or "Aucun fichier sélectionné",
        size=13,
        color=ft.Colors.GREY_700,
        max_lines=1,
        overflow=ft.TextOverflow.ELLIPSIS,
        expand=True,
    )

    status_icon = ft.Icon(ft.Icons.INFO_OUTLINE, color=ft.Colors.BLUE_400, size=18, visible=False)
    status_text = ft.Text("", size=13, color=ft.Colors.BLUE_700, expand=True)
    progress_ring = ft.ProgressRing(
        width=22, height=22, stroke_width=3, visible=False, color=ft.Colors.BLUE_600
    )

    calc_btn = ft.ElevatedButton(
        text="  Lancer le calcul",
        icon=ft.Icons.CALCULATE_OUTLINED,
        style=ft.ButtonStyle(
            bgcolor={
                ft.ControlState.DEFAULT: ft.Colors.BLUE_700,
                ft.ControlState.DISABLED: ft.Colors.BLUE_200,
            },
            color={
                ft.ControlState.DEFAULT: ft.Colors.WHITE,
                ft.ControlState.DISABLED: ft.Colors.WHITE,
            },
            padding=ft.Padding(20, 14, 20, 14),
            shape=ft.RoundedRectangleBorder(radius=8),
            elevation={ft.ControlState.PRESSED: 1, ft.ControlState.DEFAULT: 3},
        ),
        height=50,
    )

    # ── Page de résultat (modale) ──────────────────────────────────────────────
    result_filename_text = ft.Text(
        "",
        size=13,
        color=ft.Colors.GREY_600,
        text_align=ft.TextAlign.CENTER,
        italic=True,
    )
    result_blocs_text = ft.Text(
        "",
        size=14,
        color=ft.Colors.GREY_800,
        text_align=ft.TextAlign.CENTER,
    )

    def close_result_modal(e=None):
        result_modal.open = False
        page.update()

    def on_save_result(e: ft.FilePickerResultEvent):
        if e.path and state["output_io"]:
            try:
                state["output_io"].seek(0)
                with open(e.path, "wb") as f:
                    f.write(state["output_io"].read())
                set_status(
                    f"Fichier enregistré : {e.path}",
                    ft.Colors.GREEN_700,
                    ft.Icons.CHECK_CIRCLE_OUTLINE,
                )
                close_result_modal()
            except Exception as ex:
                set_status(
                    f"Erreur sauvegarde : {ex}",
                    ft.Colors.RED_700,
                    ft.Icons.ERROR_OUTLINE,
                )
                close_result_modal()

    save_picker = ft.FilePicker(on_result=on_save_result)
    page.overlay.append(save_picker)

    def on_download_click(e):
        save_picker.save_file(
            dialog_title="Enregistrer le fichier résultat",
            file_name=state["output_filename"] or "Estimation_Resultat.xlsx",
            allowed_extensions=["xlsx"],
        )

    result_modal = ft.AlertDialog(
        modal=True,
        title=ft.Row(
            [
                ft.Icon(ft.Icons.CHECK_CIRCLE, color=ft.Colors.GREEN_600, size=28),
                ft.Text(
                    "Calcul terminé avec succès",
                    weight=ft.FontWeight.BOLD,
                    size=17,
                ),
            ],
            spacing=10,
        ),
        content=ft.Container(
            content=ft.Column(
                [
                    ft.Divider(height=1),
                    ft.Container(height=8),
                    result_blocs_text,
                    ft.Container(height=4),
                    ft.Row(
                        [
                            ft.Icon(ft.Icons.TABLE_CHART, color=ft.Colors.BLUE_400, size=20),
                            result_filename_text,
                        ],
                        alignment=ft.MainAxisAlignment.CENTER,
                        spacing=6,
                    ),
                    ft.Container(height=8),
                    ft.Text(
                        "Cliquez sur « Enregistrer » pour sauvegarder le fichier Excel.",
                        size=13,
                        color=ft.Colors.GREY_600,
                        text_align=ft.TextAlign.CENTER,
                    ),
                ],
                horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                spacing=4,
                tight=True,
            ),
            width=380,
        ),
        actions=[
            ft.TextButton(
                "Fermer",
                on_click=close_result_modal,
                style=ft.ButtonStyle(color=ft.Colors.GREY_700),
            ),
            ft.ElevatedButton(
                "  Enregistrer le fichier",
                icon=ft.Icons.DOWNLOAD_OUTLINED,
                on_click=on_download_click,
                style=ft.ButtonStyle(
                    bgcolor={ft.ControlState.DEFAULT: ft.Colors.GREEN_700},
                    color={ft.ControlState.DEFAULT: ft.Colors.WHITE},
                    padding=ft.Padding(16, 12, 16, 12),
                    shape=ft.RoundedRectangleBorder(radius=6),
                ),
            ),
        ],
        actions_alignment=ft.MainAxisAlignment.END,
    )
    page.overlay.append(result_modal)

    # ── Sélection du fichier source ────────────────────────────────────────────
    def on_file_picked(e: ft.FilePickerResultEvent):
        if e.files:
            state["input_path"] = e.files[0].path
            file_path_text.value = state["input_path"]
            set_status("", ft.Colors.BLUE_700, None)
        page.update()

    file_picker = ft.FilePicker(on_result=on_file_picked)
    page.overlay.append(file_picker)

    def pick_file(e):
        file_picker.pick_files(
            dialog_title="Sélectionnez le fichier Excel d'estimation",
            allowed_extensions=["xlsx", "xls"],
            initial_directory=(
                os.path.dirname(state["input_path"]) if state["input_path"] else None
            ),
        )

    # ── Helpers ───────────────────────────────────────────────────────────────
    def set_status(msg, color, icon_name):
        status_text.value = msg
        status_text.color = color
        if icon_name:
            status_icon.name = icon_name
            status_icon.color = color
            status_icon.visible = True
        else:
            status_icon.visible = False

    def set_loading(active: bool):
        progress_ring.visible = active
        calc_btn.disabled = active

    # ── Logique de calcul (thread séparé) ─────────────────────────────────────
    def run_calculation():
        path = state["input_path"]
        if not path or not os.path.exists(path):
            set_status(
                "Fichier introuvable. Vérifiez le chemin.",
                ft.Colors.RED_700,
                ft.Icons.ERROR_OUTLINE,
            )
            set_loading(False)
            page.update()
            return

        try:
            from estim_engine import process_estim_batiment

            with open(path, "rb") as f:
                file_bytes = f.read()

            output_io, output_filename, blocs_count = process_estim_batiment(file_bytes)

            if output_io:
                state["output_io"] = output_io
                state["output_filename"] = output_filename
                state["blocs_count"] = blocs_count

                result_blocs_text.value = f"{blocs_count} bloc(s) traité(s) avec succès."
                result_filename_text.value = output_filename

                set_status(
                    "Calcul terminé.",
                    ft.Colors.GREEN_700,
                    ft.Icons.CHECK_CIRCLE_OUTLINE,
                )
                result_modal.open = True
            else:
                # output_filename contient le message d'erreur
                short_err = str(output_filename).split("\n")[0]
                set_status(short_err, ft.Colors.RED_700, ft.Icons.ERROR_OUTLINE)

        except Exception as exc:
            set_status(f"Erreur inattendue : {exc}", ft.Colors.RED_700, ft.Icons.ERROR_OUTLINE)

        set_loading(False)
        page.update()

    def on_calc_click(e):
        if not state["input_path"]:
            set_status(
                "Veuillez d'abord sélectionner un fichier.",
                ft.Colors.ORANGE_700,
                ft.Icons.WARNING_AMBER_OUTLINED,
            )
            page.update()
            return
        set_status(
            "Calcul en cours, veuillez patienter…",
            ft.Colors.BLUE_700,
            ft.Icons.HOURGLASS_EMPTY,
        )
        set_loading(True)
        page.update()
        threading.Thread(target=run_calculation, daemon=True).start()

    calc_btn.on_click = on_calc_click

    # ── Mise en page ──────────────────────────────────────────────────────────
    header = ft.Container(
        content=ft.Row(
            [
                ft.Icon(ft.Icons.APARTMENT, color=ft.Colors.WHITE, size=30),
                ft.Column(
                    [
                        ft.Text(
                            "EstimBatiment",
                            size=22,
                            weight=ft.FontWeight.BOLD,
                            color=ft.Colors.WHITE,
                        ),
                        ft.Text(
                            "Calcul automatique de devis",
                            size=12,
                            color=ft.Colors.BLUE_100,
                        ),
                    ],
                    spacing=0,
                    tight=True,
                ),
            ],
            spacing=14,
            vertical_alignment=ft.CrossAxisAlignment.CENTER,
        ),
        bgcolor=ft.Colors.BLUE_800,
        padding=ft.Padding(28, 18, 28, 18),
    )

    file_card = ft.Card(
        content=ft.Container(
            content=ft.Column(
                [
                    ft.Text(
                        "FICHIER EXCEL SOURCE",
                        size=11,
                        weight=ft.FontWeight.W_600,
                        color=ft.Colors.GREY_500,
                    ),
                    ft.Row(
                        [
                            ft.Icon(
                                ft.Icons.TABLE_CHART_OUTLINED,
                                color=ft.Colors.BLUE_600,
                                size=22,
                            ),
                            file_path_text,
                            ft.IconButton(
                                icon=ft.Icons.FOLDER_OPEN_OUTLINED,
                                icon_color=ft.Colors.BLUE_700,
                                tooltip="Choisir un autre fichier",
                                on_click=pick_file,
                            ),
                        ],
                        spacing=8,
                        vertical_alignment=ft.CrossAxisAlignment.CENTER,
                    ),
                ],
                spacing=6,
                tight=True,
            ),
            padding=ft.Padding(18, 14, 10, 14),
        ),
        elevation=2,
    )

    action_row = ft.Row(
        [calc_btn, progress_ring],
        spacing=14,
        vertical_alignment=ft.CrossAxisAlignment.CENTER,
    )

    status_row = ft.Row(
        [status_icon, status_text],
        spacing=6,
        vertical_alignment=ft.CrossAxisAlignment.CENTER,
    )

    body = ft.Container(
        content=ft.Column(
            [
                file_card,
                ft.Container(height=10),
                action_row,
                ft.Container(height=6),
                status_row,
            ],
            spacing=0,
        ),
        padding=ft.Padding(28, 28, 28, 28),
        expand=True,
    )

    page.add(
        ft.Column(
            [header, body],
            spacing=0,
            expand=True,
        )
    )


if __name__ == "__main__":
    ft.app(target=main)
