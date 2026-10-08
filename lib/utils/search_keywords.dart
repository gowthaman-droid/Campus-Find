/// Builds the `keywords` list that makes Firestore search possible.
///
/// Firestore cannot search "inside" text, so every report stores a list of
/// small search words. A search then asks for reports whose list contains any
/// of the words the person typed.
///
/// IMPORTANT: backend/services/search_keywords.py implements the SAME
/// algorithm and must give identical results. Test vector (the same one is
/// used by both test suites):
///
///   itemName 'Black Leather Wallet', category 'Wallets & Purses',
///   location 'Library', locationDetail '2nd floor',
///   description 'Brown stitching with college ID card'
///   ->
///   [black, leather, wallet, wallets, purses, library, 2nd, floor, brown,
///    stitching, college, id, card, bla, blac, lea, leat, leath, leathe,
///    wal, wall, walle]
///
/// Rules of the algorithm:
///  1. Lower-case, then take every run of [a-z0-9] as a word.
///  2. Drop words shorter than 2 characters and the stop-words below.
///  3. Whole words of: item name, category, location, location detail, and
///     the first 30 words of the description (in that order).
///  4. Then prefixes (length 3 up to one letter short of the whole word) of
///     every item-name word, so "wal" finds "wallet".
///  5. Remove duplicates (first occurrence wins) and keep at most 80.
class SearchKeywords {
  SearchKeywords._();

  static const int maxKeywords = 80;
  static const int maxQueryWords = 10;
  static const int maxDescriptionWords = 30;
  static const int minPrefixLength = 3;

  static const Set<String> stopWords = <String>{
    'the',
    'and',
    'for',
    'with',
    'near',
    'from',
    'this',
    'that',
    'was',
    'are',
    'has',
    'have',
    'lost',
    'found',
  };

  static final RegExp _wordPattern = RegExp(r'[a-z0-9]+');

  /// Splits text into useful lower-case words (rules 1 and 2).
  static List<String> tokenize(String text) {
    final words = <String>[];
    for (final match in _wordPattern.allMatches(text.toLowerCase())) {
      final word = match.group(0)!;
      if (word.length < 2 || stopWords.contains(word)) {
        continue;
      }
      words.add(word);
    }
    return words;
  }

  /// The list stored in `reports.keywords`.
  static List<String> forReport({
    required String itemName,
    required String category,
    required String location,
    required String locationDetail,
    required String description,
  }) {
    final keywords = <String>{};
    final nameWords = tokenize(itemName);

    keywords.addAll(nameWords);
    keywords.addAll(tokenize(category));
    keywords.addAll(tokenize(location));
    keywords.addAll(tokenize(locationDetail));
    keywords.addAll(tokenize(description).take(maxDescriptionWords));

    for (final word in nameWords) {
      for (var length = minPrefixLength; length < word.length; length++) {
        keywords.add(word.substring(0, length));
      }
    }
    return keywords.take(maxKeywords).toList();
  }

  /// The words to look for when a person types a search (at most 10).
  /// An empty list means "show everything" (nothing searchable was typed).
  static List<String> forQuery(String text) {
    final unique = <String>[];
    for (final word in tokenize(text)) {
      if (!unique.contains(word)) {
        unique.add(word);
      }
      if (unique.length >= maxQueryWords) {
        break;
      }
    }
    return unique;
  }
}
