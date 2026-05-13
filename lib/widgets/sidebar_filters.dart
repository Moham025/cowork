// lib/widgets/sidebar_filters.dart

import 'package:flutter/material.dart';

class SidebarFilters extends StatelessWidget {
  final String categorieActive;
  final List<String> categories;
  final Function(String) onCategorieChanged;
  final Function(String) onSearchChanged;
  final double budgetMax;
  final Function(double) onBudgetChanged;
  final VoidCallback onChangerDossier;
  final VoidCallback onViderCache;

  const SidebarFilters({
    Key? key,
    required this.categorieActive,
    required this.categories,
    required this.onCategorieChanged,
    required this.onSearchChanged,
    required this.budgetMax,
    required this.onBudgetChanged,
    required this.onChangerDossier,
    required this.onViderCache,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(
              children: [
                const Text(
                  'NGnior',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2C3E50),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'CONCEPTION',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[700],
                  ),
                ),
              ],
            ),
          ),

          // Recherche
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 25, vertical: 10),
            child: Text(
              'RECHERCHE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              onChanged: onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Rechercher...',
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),

          const SizedBox(height: 30),

          // Catégories
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 25, vertical: 10),
            child: Text(
              'CATÉGORIES',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              children: categories.map((cat) {
                final isActive = cat == categorieActive;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Material(
                    color:
                        isActive ? const Color(0xFFD3E3FD) : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => onCategorieChanged(cat),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 15, vertical: 12),
                        child: Row(
                          children: [
                            Text(
                              cat,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isActive
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isActive
                                    ? const Color(0xFF174EA6)
                                    : const Color(0xFF2C3E50),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 30),

          // Budget
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 25, vertical: 10),
            child: Text(
              'BUDGET MAX',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 25),
            child: Text(
              budgetMax == 0
                  ? 'Tous budgets'
                  : '${budgetMax.toStringAsFixed(0).replaceAllMapped(
                        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                        (Match m) => '${m[1]} ',
                      )} FCFA',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
            child: Slider(
              value: budgetMax,
              min: 0,
              max: 500000000,
              divisions: 50,
              activeColor: const Color(0xFF3B8ED0),
              onChanged: onBudgetChanged,
            ),
          ),

          const Spacer(),

          // Boutons actions
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onChangerDossier,
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('Changer dossier'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF3B8ED0),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onViderCache,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Vider cache + lien'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
