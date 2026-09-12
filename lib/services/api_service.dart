import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import 'storage_service.dart';

class ApiException implements Exception {
  final String message;
  final int? status;
  final String? code;
  ApiException(this.message, {this.status, this.code});
  @override
  String toString() => message;
}

class ApiService {
  static final ApiService instance = ApiService._internal();
  ApiService._internal();

  Future<Map<String, dynamic>> _request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    bool retry = true,
  }) async {
    final token = await StorageService.getAccessToken();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    final uri = Uri.parse('${AppConfig.apiBaseUrl}$path');
    http.Response res;
    switch (method) {
      case 'POST':
        res = await http.post(uri, headers: headers, body: body != null ? jsonEncode(body) : null);
        break;
      case 'PATCH':
        res = await http.patch(uri, headers: headers, body: body != null ? jsonEncode(body) : null);
        break;
      case 'PUT':
        res = await http.put(uri, headers: headers, body: body != null ? jsonEncode(body) : null);
        break;
      case 'DELETE':
        res = await http.delete(uri, headers: headers, body: body != null ? jsonEncode(body) : null);
        break;
      default:
        res = await http.get(uri, headers: headers);
    }

    Map<String, dynamic> data = {};
    if (res.body.isNotEmpty) {
      try {
        data = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {}
    }

    if (res.statusCode == 401 && data['code'] == 'TOKEN_EXPIRED' && retry) {
      final refreshed = await _refreshAccessToken();
      if (refreshed) return _request(path, method: method, body: body, retry: false);
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(data['message'] ?? 'Request failed', status: res.statusCode, code: data['code']);
    }
    return data;
  }

  Future<bool> _refreshAccessToken() async {
    try {
      final refreshToken = await StorageService.getRefreshToken();
      if (refreshToken == null) return false;
      final res = await http.post(
        Uri.parse('${AppConfig.apiBaseUrl}/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      );
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['success'] == true) {
        await StorageService.setAccessToken(data['accessToken']);
        return true;
      }
    } catch (_) {}
    await StorageService.clearTokens();
    return false;
  }

  /// Multipart upload (video/thumbnail/screenshot files + form fields)
  Future<Map<String, dynamic>> uploadMultipart(
    String path, {
    required Map<String, String> fields,
    required List<http.MultipartFile> files,
    bool retry = true,
    String method = 'POST',
  }) async {
    final token = await StorageService.getAccessToken();
    final uri = Uri.parse('${AppConfig.apiBaseUrl}$path');
    final request = http.MultipartRequest(method, uri);
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.fields.addAll(fields);
    request.files.addAll(files);

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);

    Map<String, dynamic> data = {};
    if (res.body.isNotEmpty) {
      try {
        data = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {}
    }

    if (res.statusCode == 401 && data['code'] == 'TOKEN_EXPIRED' && retry) {
      final refreshed = await _refreshAccessToken();
      if (refreshed) return uploadMultipart(path, fields: fields, files: files, retry: false, method: method);
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(data['message'] ?? 'Upload failed', status: res.statusCode, code: data['code']);
    }
    return data;
  }

  // ---------------- Auth ----------------
  Future<Map<String, dynamic>> signup({required String name, required String email, required String password}) =>
      _request('/auth/signup', method: 'POST', body: {'name': name, 'email': email, 'password': password});

  Future<Map<String, dynamic>> login({required String email, required String password}) =>
      _request('/auth/login', method: 'POST', body: {'email': email, 'password': password});

  Future<Map<String, dynamic>> googleLogin(String idToken) =>
      _request('/auth/google', method: 'POST', body: {'idToken': idToken});

  Future<Map<String, dynamic>> logout() => _request('/auth/logout', method: 'POST');

  Future<Map<String, dynamic>> forgotPassword(String email) =>
      _request('/auth/forgot-password', method: 'POST', body: {'email': email});

  Future<Map<String, dynamic>> me() => _request('/auth/me');

  Future<Map<String, dynamic>> setupUsername({required String username, required String language, String? avatar}) =>
      _request('/auth/setup-username', method: 'POST', body: {
        'username': username,
        'language': language,
        if (avatar != null) 'avatar': avatar,
      });

  Future<Map<String, dynamic>> applyReferralCode(String referralCode) =>
      _request('/auth/apply-referral', method: 'POST', body: {'referralCode': referralCode});

  Future<Map<String, dynamic>> deleteMyAccount() => _request('/auth/delete-account', method: 'DELETE');

  // ---------------- Dashboard ----------------
  Future<Map<String, dynamic>> dashboard() => _request('/dashboard');

  // ---------------- YouTube ----------------
  Future<Map<String, dynamic>> getYoutubeOAuthUrl() => _request('/youtube/oauth/url?platform=mobile');
  Future<Map<String, dynamic>> getYoutubeChannel() => _request('/youtube/channel');
  Future<Map<String, dynamic>> disconnectYoutube() => _request('/youtube/disconnect', method: 'DELETE');

  // ⚠️ NEW (Boss request — Option B, "Apply to Video" should also reach
  // videos already published on the connected YouTube channel, not just
  // ones TubePilot itself uploaded/queued): real channel videos straight
  // from YouTube (GET /api/youtube/my-videos) and a direct write to an
  // already-live video's title/description on YouTube itself
  // (PATCH /api/youtube/my-videos/:videoId) — separate from
  // updateVideoMetadata() below, which only touches TubePilot's own DB
  // record for videos it uploaded itself.
  Future<Map<String, dynamic>> getMyYoutubeVideos() => _request('/youtube/my-videos');

  Future<Map<String, dynamic>> updateYoutubeVideoMetadata(
    String videoId, {
    String? title,
    String? description,
  }) =>
      _request('/youtube/my-videos/$videoId', method: 'PATCH', body: {
        if (title != null) 'title': title,
        if (description != null) 'description': description,
      });

  // ---------------- Meta (Facebook + Instagram) ----------------
  // Since a Facebook Page's linked Instagram Business Account is
  // auto-fetched by the backend at connect/select-page time, one OAuth
  // flow + one status check now covers BOTH platforms — no separate
  // Instagram connect endpoint exists or is needed.
  Future<Map<String, dynamic>> getMetaOAuthUrl() => _request('/meta/oauth/url?platform=mobile');
  Future<Map<String, dynamic>> getMetaStatus() => _request('/meta/status');
  Future<Map<String, dynamic>> getMetaPendingPages() => _request('/meta/pages');
  Future<Map<String, dynamic>> selectMetaPage(String pageId) =>
      _request('/meta/select-page', method: 'PATCH', body: {'pageId': pageId});
  // Disconnecting the Facebook Page always disconnects its linked
  // Instagram account too (backend clears both in one call).
  Future<Map<String, dynamic>> disconnectFacebook() => _request('/meta/facebook/disconnect', method: 'DELETE');

  // ---------------- Videos (multi-platform: YouTube + Facebook + Instagram) ----------------
  Future<Map<String, dynamic>> uploadVideo({
    required String videoPath,
    String? thumbnailPath,
    List<String>? mediaPaths, // Instagram/Facebook carousel — additional images
    required List<String> platforms,
    String? postType, // 'video' | 'reel' | 'carousel' | 'post'
    Map<String, dynamic>? youtube,
    Map<String, dynamic>? facebook,
    Map<String, dynamic>? instagram,
  }) async {
    final videoMime = _lookupMimeOrDefault(videoPath, 'video/mp4');
    final files = [
      await http.MultipartFile.fromPath('video', videoPath, contentType: videoMime),
    ];
    if (thumbnailPath != null) {
      final thumbMime = _lookupMimeOrDefault(thumbnailPath, 'image/jpeg');
      files.add(await http.MultipartFile.fromPath('thumbnail', thumbnailPath, contentType: thumbMime));
    }

    final fields = <String, String>{
      'platforms': jsonEncode(platforms),
      if (postType != null) 'postType': postType,
      if (youtube != null) 'youtube': jsonEncode(youtube),
      if (facebook != null) 'facebook': jsonEncode(facebook),
      if (instagram != null) 'instagram': jsonEncode(instagram),
    };

    return uploadMultipart('/videos/upload', fields: fields, files: files);
  }

  /// POST /api/videos/bulk-upload — up to 30 files in one request, backend
  /// auto-slots them across days (today skipped, plan's daily cap applied).
  /// [items] is a per-file metadata list, index-aligned with [videoPaths]
  /// (title/description/caption/tags/hashtags/category/playlist/audience/privacyStatus).
  Future<Map<String, dynamic>> bulkUploadVideos({
    required List<String> videoPaths,
    required List<String> platforms,
    String? postType,
    List<Map<String, dynamic>>? items,
    String? preferredTime, // 'HH:mm', defaults to 10:00 on the backend
  }) async {
    final files = <http.MultipartFile>[];
    for (final path in videoPaths) {
      final mime = _lookupMimeOrDefault(path, 'video/mp4');
      files.add(await http.MultipartFile.fromPath('videos', path, contentType: mime));
    }

    final fields = <String, String>{
      'platforms': jsonEncode(platforms),
      if (postType != null) 'postType': postType,
      if (items != null) 'items': jsonEncode(items),
      if (preferredTime != null) 'preferredTime': preferredTime,
    };

    return uploadMultipart('/videos/bulk-upload', fields: fields, files: files);
  }

  Future<Map<String, dynamic>> listVideos({String? status}) =>
      _request('/videos${status != null ? '?status=$status' : ''}');
  Future<Map<String, dynamic>> getVideo(String id) => _request('/videos/$id');
  Future<Map<String, dynamic>> scheduleVideoPlatform(String id, String platform, String scheduledAt) =>
      _request('/videos/$id/schedule/$platform', method: 'PATCH', body: {'scheduledAt': scheduledAt});
  Future<Map<String, dynamic>> cancelVideo(String id) => _request('/videos/$id', method: 'DELETE');
  Future<Map<String, dynamic>> updateVideoMetadata(
    String id, {
    required String platform,
    String? title,
    String? description,
    String? caption,
    String? hashtags,
  }) =>
      _request('/videos/$id/metadata', method: 'PATCH', body: {
        'platform': platform,
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (caption != null) 'caption': caption,
        if (hashtags != null) 'hashtags': hashtags,
      });

  // ---------------- Diamonds (Cashfree) ----------------
  // The old manual UPI/QR + screenshot + UTR flow (getPaymentSettings +
  // POST /diamonds/purchase-request) is fully removed. Replaced by:
  //   1. createCashfreeOrder() — backend creates a Cashfree order, returns
  //      a paymentSessionId for the Cashfree Flutter SDK to open checkout.
  //   2. verifyCashfreePayment() — called after the SDK checkout closes
  //      (success OR failure/cancel); backend re-confirms directly with
  //      Cashfree's server before crediting diamonds — never trust the
  //      SDK's client-side result alone.
  Future<Map<String, dynamic>> getDiamondPackages() => _request('/diamonds/packages');

  Future<Map<String, dynamic>> createCashfreeOrder(int diamondPackage) =>
      _request('/diamonds/create-order', method: 'POST', body: {'diamondPackage': diamondPackage});

  Future<Map<String, dynamic>> verifyCashfreePayment(String orderId) =>
      _request('/diamonds/verify-payment', method: 'POST', body: {'orderId': orderId});

  Future<Map<String, dynamic>> myPurchaseRequests() => _request('/diamonds/my-requests');

  // ---------------- Wallet ----------------
  Future<Map<String, dynamic>> getWallet() => _request('/wallet');

  // ---------------- AI (platform-aware) ----------------
  Future<Map<String, dynamic>> aiTitle(String topic) => _request('/ai/title', method: 'POST', body: {'topic': topic});
  Future<Map<String, dynamic>> aiTitleOptions(String topic, {int count = 5}) =>
      _request('/ai/title-options', method: 'POST', body: {'topic': topic, 'count': count});
  Future<Map<String, dynamic>> aiDescription(String topic) =>
      _request('/ai/description', method: 'POST', body: {'topic': topic});
  Future<Map<String, dynamic>> aiDescriptionOptions(String topic, {int count = 4}) =>
      _request('/ai/description-options', method: 'POST', body: {'topic': topic, 'count': count});
  Future<Map<String, dynamic>> aiTags(String topic) => _request('/ai/tags', method: 'POST', body: {'topic': topic});
  Future<Map<String, dynamic>> aiCaption(String topic, String platform) =>
      _request('/ai/caption', method: 'POST', body: {'topic': topic, 'platform': platform});
  Future<Map<String, dynamic>> aiHashtags(String topic, String platform) =>
      _request('/ai/hashtags', method: 'POST', body: {'topic': topic, 'platform': platform});
  Future<Map<String, dynamic>> aiIdeas({required String niche, String platform = 'youtube', int count = 5}) =>
      _request('/ai/ideas', method: 'POST', body: {'niche': niche, 'platform': platform, 'count': count});
  Future<Map<String, dynamic>> aiSeoScore({
    required String title,
    String? description,
    List<String>? tags,
    String platform = 'youtube',
  }) =>
      _request('/ai/seo-score', method: 'POST', body: {
        'title': title,
        if (description != null) 'description': description,
        if (tags != null) 'tags': tags,
        'platform': platform,
      });

  // ---------------- Analytics: Competitors & Audit ----------------
  Future<Map<String, dynamic>> listCompetitors() => _request('/analytics/competitors');

  /// Live channel-name search for the Competitor Radar "add competitor"
  /// autocomplete (e.g. typing "tube" returns matching real YouTube
  /// channels with name + thumbnail + channelId). Backed by
  /// GET /api/analytics/competitors/search?q=... — see routes/analytics.js.
  Future<Map<String, dynamic>> searchCompetitors(String query) =>
      _request('/analytics/competitors/search?q=${Uri.encodeQueryComponent(query)}');

  Future<Map<String, dynamic>> addCompetitor({String? channelId, String? handle, String? label}) =>
      _request('/analytics/competitors', method: 'POST', body: {
        if (channelId != null) 'channelId': channelId,
        if (handle != null) 'handle': handle,
        if (label != null) 'label': label,
      });
  Future<Map<String, dynamic>> deleteCompetitor(String id) =>
      _request('/analytics/competitors/$id', method: 'DELETE');
  Future<Map<String, dynamic>> getChannelAudit() => _request('/analytics/audit');

  // ---------------- Notifications ----------------
  Future<Map<String, dynamic>> getNotifications() => _request('/notifications');
  Future<Map<String, dynamic>> markNotificationRead(String id) =>
      _request('/notifications/$id/read', method: 'PATCH');
  Future<Map<String, dynamic>> markAllNotificationsRead() => _request('/notifications/read-all', method: 'PATCH');
  Future<Map<String, dynamic>> registerDeviceToken(String fcmToken) =>
      _request('/notifications/register-device', method: 'POST', body: {'fcmToken': fcmToken});
  Future<Map<String, dynamic>> registerOneSignalPlayerId(String playerId) =>
      _request('/notifications/register-onesignal-player', method: 'POST', body: {'playerId': playerId});

  Future<Map<String, dynamic>> deleteNotification(String id) =>
      _request('/notifications/$id', method: 'DELETE');

  Future<Map<String, dynamic>> deleteAllNotifications() =>
      _request('/notifications', method: 'DELETE');

  // ---------------- Analytics ----------------
  Future<Map<String, dynamic>> getAnalytics() => _request('/analytics');

  // ---------------- Ratings (Rate Us) ----------------
  Future<Map<String, dynamic>> getRatingStatus() => _request('/ratings/status');
  Future<Map<String, dynamic>> suggestRatingReview(int stars) => _request('/ratings/suggest?stars=$stars');
  Future<Map<String, dynamic>> submitRating({required int stars, required String reviewText, required String email}) =>
      _request('/ratings', method: 'POST', body: {'stars': stars, 'reviewText': reviewText, 'email': email});
  Future<Map<String, dynamic>> dismissRating() => _request('/ratings/dismiss', method: 'POST');
  Future<Map<String, dynamic>> getMyRating() => _request('/ratings/mine');

  // ---------------- Admin ----------------
  Future<Map<String, dynamic>> adminDashboard() => _request('/admin/dashboard');
  Future<Map<String, dynamic>> adminPayments({String? status}) =>
      _request('/admin/payments${status != null ? '?status=$status' : ''}');
  Future<Map<String, dynamic>> approvePayment(String id) => _request('/admin/payments/$id/approve', method: 'PATCH');
  Future<Map<String, dynamic>> rejectPayment(String id, String note) =>
      _request('/admin/payments/$id/reject', method: 'PATCH', body: {'note': note});
  Future<Map<String, dynamic>> getAdminPaymentSettings() => _request('/admin/payment-settings');

  Future<Map<String, dynamic>> adminUsers({String? search}) => _request(
      '/admin/users${search != null && search.trim().isNotEmpty ? '?search=${Uri.encodeQueryComponent(search.trim())}' : ''}');

  Future<Map<String, dynamic>> forceLogoutUser(String id) =>
      _request('/admin/users/$id/force-logout', method: 'POST');

  Future<Map<String, dynamic>> toggleUserActive(String id) =>
      _request('/admin/users/$id/toggle-active', method: 'PATCH');

  Future<Map<String, dynamic>> deleteUserAccount(String id) => _request('/admin/users/$id', method: 'DELETE');

  // ---------------- Gift Codes ----------------
  Future<Map<String, dynamic>> adminCreateGiftCode({String? code, required int diamondValue, String? label}) =>
      _request('/admin/gift-codes', method: 'POST', body: {
        if (code != null) 'code': code,
        'diamondValue': diamondValue,
        if (label != null) 'label': label,
      });
  Future<Map<String, dynamic>> adminListGiftCodes() => _request('/admin/gift-codes');
  Future<Map<String, dynamic>> adminToggleGiftCode(String id) =>
      _request('/admin/gift-codes/$id/toggle-active', method: 'PATCH');
  Future<Map<String, dynamic>> redeemGiftCode(String code) =>
      _request('/diamonds/redeem-gift-code', method: 'POST', body: {'code': code});

  Future<Map<String, dynamic>> updatePaymentSettings({
    required String upiId,
    required String accountName,
    required String merchantName,
    String? qrImagePath,
  }) async {
    if (qrImagePath != null) {
      final qrFile = await http.MultipartFile.fromPath('qrImage', qrImagePath);
      return uploadMultipart(
        '/admin/payment-settings',
        method: 'PATCH',
        fields: {
          'upiId': upiId,
          'accountName': accountName,
          'merchantName': merchantName,
        },
        files: [qrFile],
      );
    }
    return _request('/admin/payment-settings', method: 'PATCH', body: {
      'upiId': upiId,
      'accountName': accountName,
      'merchantName': merchantName,
    });
  }

  http.MediaType _lookupMimeOrDefault(String path, String fallback) {
    final ext = path.split('.').last.toLowerCase();
    const map = {
      'mp4': 'video/mp4', 'mov': 'video/quicktime', 'mkv': 'video/x-matroska',
      'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png',
    };
    final full = map[ext] ?? fallback;
    final parts = full.split('/');
    return http.MediaType(parts[0], parts[1]);
  }
}