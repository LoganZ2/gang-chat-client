import '../protocol/api_client.dart';
import '../protocol/models.dart';
import 'search_display.dart' as search_display;

class GlobalSearchController {
  const GlobalSearchController({required this.api});

  final GangApi api;

  Future<GlobalSearchResults> search({
    required String query,
    int limit = 8,
    Iterable<search_display.GlobalSearchCategory>? categories,
    String? myRoomsCursor,
    String? publicRoomsCursor,
    String? messagesCursor,
    String? filesCursor,
  }) {
    return api.search(
      query: query,
      limit: limit,
      categories: categories?.map(search_display.globalSearchCategoryKey),
      myRoomsCursor: myRoomsCursor,
      publicRoomsCursor: publicRoomsCursor,
      messagesCursor: messagesCursor,
      filesCursor: filesCursor,
    );
  }
}
