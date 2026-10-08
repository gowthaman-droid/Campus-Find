import 'package:campus_find/utils/search_keywords.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SearchKeywords.tokenize', () {
    test('lower-cases, splits on punctuation and drops stop-words', () {
      expect(
        SearchKeywords.tokenize('The BLACK wallet, with ID-card!'),
        <String>['black', 'wallet', 'id', 'card'],
      );
    });

    test('drops one-letter words', () {
      expect(SearchKeywords.tokenize('a b c wallet'), <String>['wallet']);
    });
  });

  group('SearchKeywords.forReport', () {
    test('matches the shared test vector (same one the Python tests use)', () {
      final keywords = SearchKeywords.forReport(
        itemName: 'Black Leather Wallet',
        category: 'Wallets & Purses',
        location: 'Library',
        locationDetail: '2nd floor',
        description: 'Brown stitching with college ID card',
      );
      expect(keywords, <String>[
        'black',
        'leather',
        'wallet',
        'wallets',
        'purses',
        'library',
        '2nd',
        'floor',
        'brown',
        'stitching',
        'college',
        'id',
        'card',
        'bla',
        'blac',
        'lea',
        'leat',
        'leath',
        'leathe',
        'wal',
        'wall',
        'walle',
      ]);
    });

    test('lets a partial word find the item', () {
      final keywords = SearchKeywords.forReport(
        itemName: 'Wallet',
        category: 'Other',
        location: 'Canteen',
        locationDetail: '',
        description: 'Brown',
      );
      expect(keywords, contains('wal'));
    });

    test('never returns more than 80 keywords', () {
      final longName =
          List<String>.generate(30, (i) => 'product${i}name').join(' ');
      final keywords = SearchKeywords.forReport(
        itemName: longName,
        category: 'Other',
        location: 'Library',
        locationDetail: '',
        description: 'something',
      );
      expect(keywords.length, SearchKeywords.maxKeywords);
    });
  });

  group('SearchKeywords.forQuery', () {
    test('removes duplicates and keeps the typed order', () {
      expect(
        SearchKeywords.forQuery('Black   wallet black'),
        <String>['black', 'wallet'],
      );
    });

    test('keeps at most 10 words', () {
      final text = List<String>.generate(15, (i) => 'word$i').join(' ');
      expect(SearchKeywords.forQuery(text).length, 10);
    });

    test('a text with nothing searchable gives an empty list', () {
      expect(SearchKeywords.forQuery('the and !!'), isEmpty);
    });
  });
}
