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
    String? userSettingsCursor,
    String? messagesCursor,
    String? filesCursor,
  }) async {
    final selected = categories?.toList(growable: false);
    final includeUserSettings =
        selected?.contains(search_display.GlobalSearchCategory.userSettings) ??
        false;
    final coreCategories = selected
        ?.where(
          (category) =>
              category != search_display.GlobalSearchCategory.userSettings,
        )
        .toList(growable: false);
    final coreFuture = coreCategories != null && coreCategories.isEmpty
        ? Future.value(
            const GlobalSearchResults(
              myRooms: [],
              publicRooms: [],
              messages: [],
              files: [],
            ),
          )
        : api.search(
            query: query,
            limit: limit,
            categories: coreCategories?.map(
              search_display.globalSearchCategoryKey,
            ),
            myRoomsCursor: myRoomsCursor,
            publicRoomsCursor: publicRoomsCursor,
            messagesCursor: messagesCursor,
            filesCursor: filesCursor,
          );
    final userFuture = includeUserSettings
        ? api.searchUsersPage(
            query: query,
            limit: limit,
            cursor: userSettingsCursor,
            includeSuspended: true,
          )
        : Future.value(const UserSearchPage(users: []));
    final core = await coreFuture;
    final users = await userFuture;
    return GlobalSearchResults(
      myRooms: core.myRooms,
      publicRooms: core.publicRooms,
      userSettings: users.users,
      messages: core.messages,
      files: core.files,
      nextCursors: GlobalSearchCursors(
        myRooms: core.nextCursors.myRooms,
        publicRooms: core.nextCursors.publicRooms,
        userSettings: users.nextCursor,
        messages: core.nextCursors.messages,
        files: core.nextCursors.files,
      ),
      totalCounts: GlobalSearchCounts(
        myRooms: core.totalCounts.myRooms,
        publicRooms: core.totalCounts.publicRooms,
        userSettings: users.totalCount,
        messages: core.totalCounts.messages,
        files: core.totalCounts.files,
      ),
    );
  }
}
