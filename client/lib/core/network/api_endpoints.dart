abstract final class ApiEndpoints {
  static const String _base = '/api/v1';

  // Auth
  static const String register = '$_base/auth/register';
  static const String login = '$_base/auth/login';
  static const String refresh = '$_base/auth/refresh';

  // Game
  static const String soloGame = '$_base/game/solo';
  static String game(String id) => '$_base/game/$id';
  static const String profileStats = '$_base/profile/stats';
  static const String powerupInventory = '$_base/powerup/inventory';
  static const String powerupUse = '$_base/powerup/use';

  // Matchmaking
  static const String matchQueue = '$_base/match/queue';

  // Leaderboard
  static const String leaderboard = '$_base/leaderboard';

  // Daily challenge
  static const String daily = '$_base/challenges/pending';
  static const String dailyRetry = '$_base/daily/retry';

  // Friends
  static const String friendsRequest = '$_base/friends/request';
  static const String friends = '$_base/friends';
  static const String friendsRequests = '$_base/friends/requests';
  static const String friendsRespond = '$_base/friends/respond';
  static String removeFriend(String friendId) => '$_base/friends/$friendId';

  // Friend challenges
  static const String challenges = '$_base/challenges';
  static String respondChallenge(String id) => '$_base/challenges/$id/respond';
  static const String challengesPending = '$_base/challenges/pending';

  // Push notifications
  static const String notificationToken = '$_base/notifications/token';
}
