# main.py (pour les tests locaux)
import tkinter as tk
from tkinter import filedialog
import os
import sys

# Ajouter le dossier parent (backend) au chemin pour trouver estim_engine
# Cette ligne est cruciale
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Importer la fonction de traitement depuis notre moteur centralisé
from estim_engine import process_estim_batiment

def main_local():
    root = tk.Tk()
    root.withdraw()

    input_filepath = filedialog.askopenfilename(
        title="Sélectionnez le fichier Excel d'estimation",
        filetypes=(("Fichiers Excel", "*.xlsx *.xls"),)
    )
    if not input_filepath:
        print("Aucun fichier sélectionné.")
        return

    print(f"Lecture du fichier: {input_filepath}")
    with open(input_filepath, 'rb') as f:
        file_bytes = f.read()

    # Appeler le moteur de traitement
    output_io, output_filename = process_estim_batiment(file_bytes)

    if output_io:
        save_path = filedialog.asksaveasfilename(
            title="Enregistrer le fichier de sortie sous...",
            initialfile=output_filename,
            defaultextension=".xlsx"
        )
        if save_path:
            with open(save_path, 'wb') as f:
                f.write(output_io.getvalue())
            print(f"Fichier sauvegardé avec succès: {save_path}")
        else:
            print("Sauvegarde annulée.")
    else:
        print(f"Une erreur est survenue: {output_filename}")

if __name__ == "__main__":
    main_local()