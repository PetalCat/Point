import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/user.dart';
import '../models/group.dart';
import '../models/item.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiService {
  String? _token;

  void setToken(String token) {
    _token = token;
  }

  Map<String, String> get _headers {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final url = Uri.parse('${AppConfig.serverUrl}$path');
    debugPrint('[API] $method $url');
    late http.Response response;

    try {
      switch (method) {
        case 'GET':
          response = await http.get(url, headers: _headers);
          break;
        case 'POST':
          response = await http.post(
            url,
            headers: _headers,
            body: body != null ? jsonEncode(body) : null,
          );
          break;
        case 'PUT':
          response = await http.put(
            url,
            headers: _headers,
            body: body != null ? jsonEncode(body) : null,
          );
          break;
        case 'DELETE':
          response = await http.delete(
            url,
            headers: _headers,
            body: body != null ? jsonEncode(body) : null,
          );
          break;
        default:
          throw ArgumentError('Unsupported HTTP method: $method');
      }
    } catch (e) {
      debugPrint('[API] ERROR: $e');
      rethrow;
    }

    debugPrint(
      '[API] Response ${response.statusCode}: ${response.body.length > 200 ? response.body.substring(0, 200) : response.body}',
    );

    if (response.statusCode != 200) {
      String message;
      try {
        final decoded = jsonDecode(response.body);
        message = decoded['error'] ?? response.body;
      } catch (_) {
        message = response.body;
      }
      throw ApiException(response.statusCode, message);
    }

    if (response.body.isEmpty) return {};
    return jsonDecode(response.body);
  }

  // Auth

  Future<AuthResponse> register(
    String username,
    String displayName,
    String password, {
    String? inviteCode,
  }) async {
    final body = <String, dynamic>{
      'username': username,
      'display_name': displayName,
      'password': password,
    };
    if (inviteCode != null) {
      body['invite_code'] = inviteCode;
    }
    final json = await _request('POST', '/api/register', body: body);
    return AuthResponse.fromJson(json);
  }

  Future<AuthResponse> login(String username, String password) async {
    final json = await _request(
      'POST',
      '/api/login',
      body: {'username': username, 'password': password},
    );
    return AuthResponse.fromJson(json);
  }

  // Groups

  Future<Group> createGroup(String name) async {
    final json = await _request('POST', '/api/groups', body: {'name': name});
    return Group.fromJson(json);
  }

  Future<List<Group>> listGroups() async {
    final url = Uri.parse('${AppConfig.serverUrl}/api/groups');
    final response = await http.get(url, headers: _headers);
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, response.body);
    }
    final list = jsonDecode(response.body) as List;
    return list.map((g) => Group.fromJson(g as Map<String, dynamic>)).toList();
  }

  Future<void> addMember(String groupId, String userId, {String? role}) async {
    final body = <String, dynamic>{'user_id': userId};
    if (role != null) {
      body['role'] = role;
    }
    await _request('POST', '/api/groups/$groupId/members', body: body);
  }

  Future<void> removeMember(String groupId, String memberId) async {
    await _request('DELETE', '/api/groups/$groupId/members/$memberId');
  }

  Future<void> updateMyGroupSettings(
    String groupId, {
    String? precision,
    bool? sharing,
    String? scheduleType,
  }) async {
    final body = <String, dynamic>{};
    if (precision != null) body['precision'] = precision;
    if (sharing != null) body['sharing'] = sharing;
    if (scheduleType != null) body['schedule_type'] = scheduleType;
    await _request('PUT', '/api/groups/$groupId/me', body: body);
  }

  Future<void> updateGroupSettings(
    String groupId, {
    String? name,
    bool? membersCanInvite,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (membersCanInvite != null) body['members_can_invite'] = membersCanInvite;
    await _request('PUT', '/api/groups/$groupId/settings', body: body);
  }

  Future<void> updateMemberRole(
    String groupId,
    String memberId,
    String role,
  ) async {
    await _request(
      'PUT',
      '/api/groups/$groupId/members/$memberId/role',
      body: {'role': role},
    );
  }

  Future<void> deleteGroup(String groupId) async {
    await _request('DELETE', '/api/groups/$groupId');
  }

  // Items

  Future<Item> createItem(
    String name,
    String trackerType, {
    String? sourceId,
  }) async {
    final body = <String, dynamic>{'name': name, 'tracker_type': trackerType};
    if (sourceId != null) {
      body['source_id'] = sourceId;
    }
    final json = await _request('POST', '/api/items', body: body);
    return Item.fromJson(json);
  }

  Future<List<Item>> listItems() async {
    final url = Uri.parse('${AppConfig.serverUrl}/api/items');
    final response = await http.get(url, headers: _headers);
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, response.body);
    }
    final list = jsonDecode(response.body) as List;
    return list.map((i) => Item.fromJson(i as Map<String, dynamic>)).toList();
  }

  Future<void> shareItem(
    String itemId,
    String targetType,
    String targetId,
  ) async {
    await _request(
      'POST',
      '/items/$itemId/share',
      body: {'target_type': targetType, 'target_id': targetId},
    );
  }

  // Shares

  Future<Map<String, dynamic>> sendShareRequest(String toUserId) async {
    return await _request(
      'POST',
      '/api/shares/request',
      body: {'to_user_id': toUserId},
    );
  }

  Future<List<Map<String, dynamic>>> listShares() async {
    final url = Uri.parse('${AppConfig.serverUrl}/api/shares');
    final response = await http.get(url, headers: _headers);
    if (response.statusCode != 200)
      throw ApiException(response.statusCode, response.body);
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> listIncomingRequests() async {
    final url = Uri.parse('${AppConfig.serverUrl}/api/shares/requests');
    final response = await http.get(url, headers: _headers);
    if (response.statusCode != 200)
      throw ApiException(response.statusCode, response.body);
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> listOutgoingRequests() async {
    final url = Uri.parse(
      '${AppConfig.serverUrl}/api/shares/requests/outgoing',
    );
    final response = await http.get(url, headers: _headers);
    if (response.statusCode != 200)
      throw ApiException(response.statusCode, response.body);
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }

  Future<void> acceptRequest(String requestId) async {
    await _request('POST', '/api/shares/requests/$requestId/accept');
  }

  Future<void> rejectRequest(String requestId) async {
    await _request('POST', '/api/shares/requests/$requestId/reject');
  }

  Future<void> removeShare(String userId) async {
    await _request('DELETE', '/api/shares/$userId');
  }

  // Temporary Shares

  Future<Map<String, dynamic>> createTempShare(
    String toUserId,
    int durationMinutes, {
    String precision = 'exact',
  }) async {
    return await _request(
      'POST',
      '/api/shares/temp',
      body: {
        'to_user_id': toUserId,
        'duration_minutes': durationMinutes,
        'precision': precision,
      },
    );
  }

  Future<List<Map<String, dynamic>>> listTempShares() async {
    final url = Uri.parse('${AppConfig.serverUrl}/api/shares/temp');
    final response = await http.get(url, headers: _headers);
    if (response.statusCode != 200)
      throw ApiException(response.statusCode, response.body);
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }

  Future<void> deleteTempShare(String id) async {
    await _request('DELETE', '/api/shares/temp/$id');
  }

  // History

  Future<List<Map<String, dynamic>>> getHistory(
    String userId, {
    int? since,
    int limit = 100,
  }) async {
    var path = '/api/history/$userId?limit=$limit';
    if (since != null) path += '&since=$since';
    final url = Uri.parse('${AppConfig.serverUrl}$path');
    final response = await http.get(url, headers: _headers);
    if (response.statusCode != 200)
      throw ApiException(response.statusCode, response.body);
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }

  Future<void> deleteHistory() async {
    await _request('DELETE', '/api/history');
  }

  // Places (Geofences)

  Future<Map<String, dynamic>> createPlace(
    String groupId,
    String name, {
    String geometryType = 'circle',
    double? lat,
    double? lon,
    double? radius,
    List<Map<String, double>>? polygonPoints,
  }) async {
    final body = <String, dynamic>{'name': name, 'geometry_type': geometryType};
    if (geometryType == 'circle') {
      body['lat'] = lat;
      body['lon'] = lon;
      body['radius'] = radius;
    } else {
      body['polygon_points'] = polygonPoints;
    }
    return await _request('POST', '/api/groups/$groupId/places', body: body);
  }

  Future<List<Map<String, dynamic>>> listPlaces(String groupId) async {
    final url = Uri.parse('${AppConfig.serverUrl}/api/groups/$groupId/places');
    final response = await http.get(url, headers: _headers);
    if (response.statusCode != 200)
      throw ApiException(response.statusCode, response.body);
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }

  Future<void> deletePlace(String placeId) async {
    await _request('DELETE', '/api/places/$placeId');
  }

  Future<Map<String, dynamic>> createPersonalPlace(
    String name, {
    String geometryType = 'circle',
    double? lat,
    double? lon,
    double? radius,
    List<Map<String, double>>? polygonPoints,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'geometry_type': geometryType,
      'is_personal': true,
    };
    if (geometryType == 'circle') {
      body['lat'] = lat;
      body['lon'] = lon;
      body['radius'] = radius;
    } else {
      body['polygon_points'] = polygonPoints;
    }
    return await _request('POST', '/api/places/personal', body: body);
  }

  Future<List<Map<String, dynamic>>> listPersonalPlaces() async {
    final url = Uri.parse('${AppConfig.serverUrl}/api/places/personal');
    final response = await http.get(url, headers: _headers);
    if (response.statusCode != 200)
      throw ApiException(response.statusCode, response.body);
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }

  // Invites

  // Account

  Future<void> deleteAccount(String password) async {
    await _request('DELETE', '/api/account', body: {'password': password});
  }

  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    await _request(
      'PUT',
      '/api/account/password',
      body: {'current_password': currentPassword, 'new_password': newPassword},
    );
  }

  // FCM

  Future<void> registerFcmToken(String token) async {
    await _request('POST', '/api/fcm/token', body: {'token': token});
  }

  // Zone Consents

  Future<void> requestZoneConsent(String userId) async {
    await _request(
      'POST',
      '/api/zones/consent/request',
      body: {'user_id': userId},
    );
  }

  Future<List<Map<String, dynamic>>> listIncomingZoneConsents() async {
    final url = Uri.parse('${AppConfig.serverUrl}/api/zones/consent/incoming');
    final response = await http.get(url, headers: _headers);
    if (response.statusCode != 200)
      throw ApiException(response.statusCode, response.body);
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> listGrantedZoneConsents() async {
    final url = Uri.parse('${AppConfig.serverUrl}/api/zones/consent/granted');
    final response = await http.get(url, headers: _headers);
    if (response.statusCode != 200)
      throw ApiException(response.statusCode, response.body);
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }

  Future<void> acceptZoneConsent(String ownerId) async {
    await _request('POST', '/api/zones/consent/$ownerId/accept');
  }

  Future<void> rejectZoneConsent(String ownerId) async {
    await _request('POST', '/api/zones/consent/$ownerId/reject');
  }

  Future<void> revokeZoneConsent(String ownerId) async {
    await _request('DELETE', '/api/zones/consent/$ownerId');
  }

  // Invites

  Future<Map<String, dynamic>> createInvite({int? maxUses}) async {
    final body = <String, dynamic>{};
    if (maxUses != null) {
      body['max_uses'] = maxUses;
    }
    return await _request('POST', '/api/invites', body: body);
  }

  // Ghost Mode

  Future<void> setGhostFlag(bool ghosted) async {
    await _request('PUT', '/api/ghost', body: {'ghosted': ghosted});
  }

  // MLS Key Exchange

  Future<void> uploadKeyPackage(String base64KeyPackage) async {
    await _request('POST', '/api/mls/keys', body: {
      'key_packages': [base64KeyPackage],
    });
  }

  Future<List<String>> fetchKeyPackages(String userId) async {
    final url = Uri.parse('${AppConfig.serverUrl}/api/mls/keys/$userId');
    final response = await http.get(url, headers: _headers);
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, response.body);
    }
    final json = jsonDecode(response.body);
    return (json['key_packages'] as List).cast<String>();
  }

  Future<void> sendMlsWelcome(String recipientId, String groupId, String payloadBase64) async {
    await _request('POST', '/api/mls/welcome', body: {
      'recipient_id': recipientId,
      'group_id': groupId,
      'payload': payloadBase64,
    });
  }

  Future<void> sendMlsCommit(String groupId, String payloadBase64) async {
    await _request('POST', '/api/mls/commit', body: {
      'group_id': groupId,
      'payload': payloadBase64,
    });
  }

  Future<List<Map<String, dynamic>>> fetchMlsMessages() async {
    final url = Uri.parse('${AppConfig.serverUrl}/api/mls/messages');
    final response = await http.get(url, headers: _headers);
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, response.body);
    }
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }

  Future<void> ackMlsMessage(String messageId) async {
    await _request('POST', '/api/mls/messages/$messageId/ack');
  }

  // Group Invites

  Future<Map<String, dynamic>> createGroupInvite(String groupId) async {
    return await _request('POST', '/api/groups/$groupId/invite');
  }

  Future<Map<String, dynamic>> joinGroupByCode(String code) async {
    return await _request('POST', '/api/groups/join/$code');
  }
}
