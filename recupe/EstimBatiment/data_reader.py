# data_reader.py

def get_qt_data(qt_sheet):
    """
    Reads data from the 'qt' sheet and organizes it into a dictionary.
    Dictionary keys are item names (lowercase),
    and values are another dictionary containing headers and their values.
    """
    data = {}
    # Get values from the first row to identify headers
    header_row_values = [cell.value for cell in qt_sheet[1]] 

    if not header_row_values or len(header_row_values) < 2:
        print("ERROR [get_qt_data]: Insufficient or no headers found in 'qt' sheet at row 1.")
        return {}

    # Convert value headers to lowercase and clean them
    value_headers_qt = [str(h).strip().lower() for h in header_row_values[1:] if h is not None]

    if not value_headers_qt:
        print("ERROR [get_qt_data]: No valid value headers found after the first column in 'qt'.")
        return {}

    # Iterate over rows starting from the second (min_row=2)
    for row_num, row_tuple in enumerate(qt_sheet.iter_rows(min_row=2, values_only=True), start=2):
        if not row_tuple or row_tuple[0] is None:
            continue # Skip row if it's empty or the first column is empty
        
        item_name_original = str(row_tuple[0]) 
        item_name_lower = item_name_original.strip().lower()
        data[item_name_lower] = {} # Initialize dictionary for the current item
        
        # Associate each value with its corresponding header
        for i, header_key in enumerate(value_headers_qt):
            actual_col_index_in_row_tuple = i + 1 # +1 because the first column is the item name
            cell_value_to_assign = None 

            if actual_col_index_in_row_tuple < len(row_tuple):
                cell_value_raw = row_tuple[actual_col_index_in_row_tuple]
                
                if isinstance(cell_value_raw, (int, float)):
                    cell_value_to_assign = float(cell_value_raw)
                elif isinstance(cell_value_raw, str):
                    try:
                        # Try to convert strings to float (handles commas)
                        cell_value_to_assign = float(cell_value_raw.replace(',', '.'))
                    except ValueError:
                        pass # Value remains None if conversion fails
            
            data[item_name_lower][header_key] = cell_value_to_assign
                
    if not data:
        print("WARNING [get_qt_data]: No item data read from 'qt' sheet.")
    return data

def get_open_data(open_sheet):
    """
    Reads data from the 'open' sheet (Menuiserie) and organizes it into a list of dictionaries.
    Each dictionary represents an opening with 'Designation', 'l' (largeur), 'h' (hauteur),
    'nombre', 'type', 'prix unitaire'.
    """
    data = []
    # Assumes headers are in the first row
    header_row_values = [str(cell.value).strip().lower() if cell.value is not None else "" for cell in open_sheet[1]]

    # Map expected headers to their column indices
    # Using a dictionary for faster lookup and robustness to column order changes
    header_map = {
        'designation': -1, 'l': -1, 'h': -1, 'nombre': -1, 'type': -1, 'prix unitaire': -1
    }
    for idx, header in enumerate(header_row_values):
        if header in header_map:
            header_map[header] = idx

    # Check if all required headers are found
    required_headers_found = True
    for req_header, idx in header_map.items():
        if idx == -1:
            print(f"WARNING [get_open_data]: Required header '{req_header}' not found in 'open' sheet.")
            required_headers_found = False
    
    if not required_headers_found:
        print("ERROR [get_open_data]: Missing one or more required headers in 'open' sheet. Cannot process.")
        return []

    # Iterate over rows starting from the second (min_row=2) for data
    for row_num, row_tuple in enumerate(open_sheet.iter_rows(min_row=2, values_only=True), start=2):
        if not row_tuple or not any(row_tuple): # Skip completely empty rows
            continue

        item = {}
        try:
            item['designation'] = str(row_tuple[header_map['designation']]).strip()
            item['l'] = float(str(row_tuple[header_map['l']]).replace(',', '.') if row_tuple[header_map['l']] is not None else 0.0)
            item['h'] = float(str(row_tuple[header_map['h']]).replace(',', '.') if row_tuple[header_map['h']] is not None else 0.0)
            item['nombre'] = int(row_tuple[header_map['nombre']] if row_tuple[header_map['nombre']] is not None else 0)
            item['type'] = str(row_tuple[header_map['type']]).strip()
            item['prix unitaire'] = float(str(row_tuple[header_map['prix unitaire']]).replace(',', '.') if row_tuple[header_map['prix unitaire']] is not None else 0.0)
            data.append(item)
        except (ValueError, IndexError) as e:
            print(f"WARNING [get_open_data]: Skipping row {row_num} due to data parsing error: {e}. Row data: {row_tuple}")
            continue
            
    if not data:
        print("WARNING [get_open_data]: No valid item data read from 'open' sheet.")
    return data

def get_simple_block_data(sheet):
    """
    Reads data from sheets like 'Electricite' or 'Plomberie'
    and organizes it into a list of dictionaries.
    Assumes columns: Designation, Unité, Nombre, Prix Unitaire.
    """
    data = []
    header_row_values = [str(cell.value).strip().lower() if cell.value is not None else "" for cell in sheet[1]]

    header_map = {
        'designation': -1, 'unité': -1, 'nombre': -1, 'prix unitaire': -1
    }
    for idx, header in enumerate(header_row_values):
        if header in header_map:
            header_map[header] = idx

    required_headers_found = True
    for req_header, idx in header_map.items():
        if idx == -1:
            print(f"WARNING [get_simple_block_data]: Required header '{req_header}' not found in '{sheet.title}' sheet.")
            required_headers_found = False
    
    if not required_headers_found:
        print(f"ERROR [get_simple_block_data]: Missing one or more required headers in '{sheet.title}' sheet. Cannot process.")
        return []

    for row_num, row_tuple in enumerate(sheet.iter_rows(min_row=2, values_only=True), start=2):
        if not row_tuple or not any(row_tuple):
            continue

        item = {}
        try:
            # Ensure indices exist before accessing
            if header_map['designation'] >= len(row_tuple) or \
               header_map['unité'] >= len(row_tuple) or \
               header_map['nombre'] >= len(row_tuple) or \
               header_map['prix unitaire'] >= len(row_tuple):
                print(f"WARNING [get_simple_block_data]: Skipping row {row_num} in '{sheet.title}' due to insufficient columns in row_tuple.")
                continue

            item['designation'] = str(row_tuple[header_map['designation']]).strip()
            item['unit'] = str(row_tuple[header_map['unité']]).strip()
            item['number'] = float(str(row_tuple[header_map['nombre']]).replace(',', '.') if row_tuple[header_map['nombre']] is not None else 0.0)
            item['unit_price'] = float(str(row_tuple[header_map['prix unitaire']]).replace(',', '.') if row_tuple[header_map['prix unitaire']] is not None else 0.0)
            data.append(item)
        except (ValueError, IndexError) as e:
            print(f"WARNING [get_simple_block_data]: Skipping row {row_num} in '{sheet.title}' due to data parsing error: {e}. Row data: {row_tuple}")
            continue
            
    if not data:
        print(f"WARNING [get_simple_block_data]: No valid item data read from '{sheet.title}' sheet.")
    return data

def get_formula_block_data(sheet):
    """
    Reads data from sheets like 'Peinture', 'Revetement', 'Toiture'
    where quantity is represented by a formula or direct value, and unit price is direct.
    Assumes columns: Designation/Description (Col B), Unité (Col C), Quantité/Formule (Col D), Prix Unitaire (Col E).
    """
    data = []
    # We will assume a structure matching the items within a 'calcul' block for these sheets
    # Column indices in row_tuple:
    # 0 (Col A - often empty for item numbers or similar)
    # 1 (Col B - Description)
    # 2 (Col C - Unit)
    # 3 (Col D - Quantity/Formula)
    # 4 (Col E - P.U.)

    for row_num, row_tuple in enumerate(sheet.iter_rows(min_row=2, values_only=True), start=2):
        if not row_tuple or not any(row_tuple): # Skip completely empty rows
            continue

        item = {}
        try:
            # Ensure row_tuple has enough elements for columns B, C, D, E (indices 1 to 4)
            if len(row_tuple) < 5: 
                print(f"WARNING [get_formula_block_data]: Skipping row {row_num} in '{sheet.title}' due to insufficient columns. Expected at least 5, got {len(row_tuple)}. Row data: {row_tuple}")
                continue

            item['description'] = str(row_tuple[1]).strip() if row_tuple[1] is not None else "" # Column B
            item['unit'] = str(row_tuple[2]).strip() if row_tuple[2] is not None else "" # Column C
            item['formula_or_qty'] = row_tuple[3] # Column D (can be formula or value)
            item['pu'] = float(str(row_tuple[4]).replace(',', '.') if row_tuple[4] is not None else 0.0) if row_tuple[4] is not None else 0.0 # Column E

            data.append(item)
        except (ValueError, IndexError) as e:
            print(f"WARNING [get_formula_block_data]: Skipping row {row_num} in '{sheet.title}' due to data parsing error: {e}. Row data: {row_tuple}")
            continue
            
    if not data:
        print(f"WARNING [get_formula_block_data]: No valid item data read from '{sheet.title}' sheet.")
    return data
