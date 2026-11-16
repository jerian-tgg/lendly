/// Centralized everyday, easily lendable physical item categories and
/// appraiser specialties for Orchid / Lendly.
///
/// Strictly restricted to everyday physical items that can be lent peer-to-peer
/// without complex legalities, titles, or registration. High-value or titled/regulated
/// assets (such as real estate, vehicles, firearms, or luxury jewelry) are excluded.
class ItemCategories {
  ItemCategories._();

  /// Canonical list of everyday, easily lendable physical item categories.
  /// Used for both item listings and appraiser specialties to enforce 1-to-1
  /// specialty matching.
  static const List<String> categories = [
    'Electronics',
    'Books',
    'Tools',
    'Musical Instruments',
    'Camping Gear',
    'Kitchen Appliances',
    'Cameras & Photography',
    'Audio & Video Equipment',
    'Sports & Fitness',
    'Board Games & Toys',
    'Party & Event Supplies',
    'Gardening Equipment',
    'Furniture',
    'Clothing & Costumes',
    'Baby & Kids Gear',
    'Arts & Crafts',
  ];

  /// Categories available when creating or editing an item listing.
  static List<String> get listingCategories => categories;

  /// Specialties available when registering or applying as an appraiser.
  static List<String> get appraiserSpecialties => categories;

  /// Categories available in marketplace and dashboard filter bars (includes 'All').
  static List<String> get filterCategories => const ['All', ...categories];

  /// Default category/specialty selection.
  static const String defaultCategory = 'Electronics';

  /// Prohibited asset categories and keywords (high-value, titled, or regulated items).
  static const List<String> excludedCategoryKeywords = [
    'real estate',
    'property',
    'land',
    'condo',
    'apartment',
    'house',
    'vehicle',
    'vehicles',
    'vehicles & transport',
    'car',
    'cars',
    'motorcycle',
    'truck',
    'boat',
    'watercraft',
    'aircraft',
    'firearm',
    'firearms',
    'weapon',
    'weapons',
    'gun',
    'guns',
    'ammunition',
    'explosive',
    'jewelry',
    'jewelry & luxury goods',
    'luxury',
    'bullion',
    'securities',
    'titled asset',
  ];

  /// Legacy category/specialty aliases mapped to their canonical category name
  /// for backward compatibility with existing Firestore documents.
  static const Map<String, String> _legacyAliases = {
    'electronics & technology': 'Electronics',
    'industrial tools & equipment': 'Tools',
    'tools & equipment': 'Tools',
    'home & office appliances': 'Kitchen Appliances',
    'appliances': 'Kitchen Appliances',
    'cameras': 'Cameras & Photography',
    'outdoor': 'Camping Gear',
    'camping & outdoor': 'Camping Gear',
    'sports': 'Sports & Fitness',
    'clothing': 'Clothing & Costumes',
    'home': 'Furniture',
  };

  /// Returns true if [raw] represents a prohibited category (e.g., real estate,
  /// vehicles, firearms, luxury jewelry).
  static bool isExcludedCategory(String? raw) {
    if (raw == null) return false;
    final normalized = raw.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    for (final keyword in excludedCategoryKeywords) {
      if (normalized == keyword || normalized.contains(keyword)) {
        return true;
      }
    }
    return false;
  }

  /// Resolves [raw] to a canonical category from [categories], or returns `null`
  /// if [raw] is null, empty, excluded, a generic catch-all ('All', 'Other',
  /// 'General Merchandise'), or unrecognized.
  static String? normalizeCategory(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (isExcludedCategory(trimmed)) return null;

    final lower = trimmed.toLowerCase();
    if (lower == 'all' ||
        lower == 'other' ||
        lower == 'general' ||
        lower == 'general merchandise' ||
        lower == 'general marketplace') {
      return null;
    }

    for (final cat in categories) {
      if (cat.toLowerCase() == lower) {
        return cat;
      }
    }

    return _legacyAliases[lower];
  }

  /// Returns true if [raw] is a valid allowed everyday item category.
  static bool isValidCategory(String? raw) {
    return normalizeCategory(raw) != null;
  }

  /// Enforces strict 1-to-1 specialty matching between an appraiser's designated
  /// specialty and an item's category.
  ///
  /// Both [appraiserSpecialty] and [itemCategory] must resolve to the same valid,
  /// non-excluded everyday category in [categories].
  static bool doesSpecialtyMatchCategory({
    required String? appraiserSpecialty,
    required String? itemCategory,
  }) {
    final canonicalSpecialty = normalizeCategory(appraiserSpecialty);
    final canonicalCategory = normalizeCategory(itemCategory);
    if (canonicalSpecialty == null || canonicalCategory == null) {
      return false;
    }
    return canonicalSpecialty == canonicalCategory;
  }

  /// Checks whether an item's [itemCategory] matches a UI filter selection
  /// ([selectedFilter]), where `'All'` matches any valid category.
  static bool matchesCategoryFilter({
    required String? itemCategory,
    required String selectedFilter,
  }) {
    if (selectedFilter == 'All') return true;
    final canonicalFilter = normalizeCategory(selectedFilter);
    final canonicalItem = normalizeCategory(itemCategory);
    if (canonicalFilter != null && canonicalItem != null) {
      return canonicalFilter == canonicalItem;
    }
    return (itemCategory ?? '').trim().toLowerCase() ==
        selectedFilter.trim().toLowerCase();
  }
}
