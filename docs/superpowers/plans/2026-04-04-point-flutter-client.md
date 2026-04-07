# Point Flutter Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Point Flutter client — a mobile app that connects to the Point server for real-time location sharing with the Duo split-screen UI.

**Architecture:** Flutter app targeting Android (primary test device: Samsung S24 Ultra). Connects to Point server via REST (auth, groups, items) and WebSocket (real-time location). Background location via geolocator + foreground service. Google Maps for the map view. State management via Provider/ChangeNotifier for simplicity.

**Tech Stack:** Flutter 3.38, Dart, google_maps_flutter, geolocator, web_socket_channel, provider, http, shared_preferences, flutter_local_notifications

---

## File Structure

```
point/
├── pubspec.yaml
├── android/
│   └── app/src/main/AndroidManifest.xml  (permissions)
├── lib/
│   ├── main.dart                    # App entry, MaterialApp, routes
│   ├── config.dart                  # Server URL, constants
│   ├── models/
│   │   ├── user.dart                # User, AuthResponse
│   │   ├── group.dart               # Group, GroupMember
│   │   ├── item.dart                # Item, ItemShare
│   │   └── location_update.dart     # LocationUpdate (the WS message)
│   ├── services/
│   │   ├── api_service.dart         # REST client (auth, groups, items, invites)
│   │   ├── ws_service.dart          # WebSocket connection, message handling
│   │   ├── location_service.dart    # GPS tracking, background location
│   │   └── auth_service.dart        # Token storage, auth state
│   ├── providers/
│   │   ├── auth_provider.dart       # Auth state (logged in/out, user info)
│   │   ├── location_provider.dart   # People locations, own location
│   │   ├── group_provider.dart      # Groups state
│   │   └── item_provider.dart       # Items state
│   ├── screens/
│   │   ├── login_screen.dart        # Login form
│   │   ├── register_screen.dart     # Register form (with invite code)
│   │   ├── home_screen.dart         # Main screen with map + drawer
│   │   ├── inbox_screen.dart        # Location inbox (placeholder)
│   │   └── profile_screen.dart      # Profile/settings (placeholder)
│   └── widgets/
│       ├── map_view.dart            # Google Maps with people/item markers
│       ├── people_drawer.dart       # Bottom drawer with people/items list
│       ├── filter_bar.dart          # All/People/Items segmented control
│       ├── group_chip_bar.dart      # Group sub-filter pills
│       ├── person_row.dart          # Single person row in drawer
│       └── item_row.dart            # Single item row in drawer
```

---

### Task 1: Flutter Project Scaffold

**Files:**
- Create: `point/` Flutter project
- Create: `point/lib/main.dart`
- Create: `point/lib/config.dart`

- [ ] **Step 1: Create Flutter project**

```bash
cd /Users/parker/Developer/GlobalMap
flutter create point --org com.point --platforms android
cd point
```

- [ ] **Step 2: Add dependencies to pubspec.yaml**

Add under `dependencies:`:
```yaml
dependencies:
  flutter:
    sdk: flutter
  provider: ^6.1.2
  http: ^1.2.2
  web_socket_channel: ^3.0.1
  shared_preferences: ^2.3.3
  google_maps_flutter: ^2.10.0
  geolocator: ^13.0.2
  permission_handler: ^11.3.1
  flutter_local_notifications: ^18.0.1
  json_annotation: ^4.9.0
  intl: ^0.19.0
```

- [ ] **Step 3: Write config.dart**

```dart
// lib/config.dart
class AppConfig {
  // Change this to your server URL
  static const String serverUrl = 'http://10.0.2.2:8080'; // Android emulator localhost
  static const String wsUrl = 'ws://10.0.2.2:8080/ws';
  
  // For real device on same network, use your machine's IP:
  // static const String serverUrl = 'http://192.168.x.x:8080';
  // static const String wsUrl = 'ws://192.168.x.x:8080/ws';
}
```

- [ ] **Step 4: Write minimal main.dart**

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config.dart';

void main() {
  runApp(const PointApp());
}

class PointApp extends StatelessWidget {
  const PointApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Point',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A1A1A),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'SF Pro Display',
      ),
      home: const Scaffold(
        body: Center(child: Text('Point', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800))),
      ),
    );
  }
}
```

- [ ] **Step 5: Verify it builds and runs**

```bash
cd /Users/parker/Developer/GlobalMap/point
flutter run -d R5CW22SH8SD
```

Should show "Point" centered on screen.

- [ ] **Step 6: Commit**

```bash
cd /Users/parker/Developer/GlobalMap
git add point/
git commit -m "feat: scaffold Point Flutter app"
```

---

### Task 2: Models & API Service

**Files:**
- Create: `point/lib/models/user.dart`
- Create: `point/lib/models/group.dart`
- Create: `point/lib/models/item.dart`
- Create: `point/lib/models/location_update.dart`
- Create: `point/lib/services/api_service.dart`
- Create: `point/lib/services/auth_service.dart`

- [ ] **Step 1: Write user model**

```dart
// lib/models/user.dart
class AuthResponse {
  final String token;
  final String userId;
  final String displayName;
  final bool isAdmin;

  AuthResponse({required this.token, required this.userId, required this.displayName, required this.isAdmin});

  factory AuthResponse.fromJson(Map<String, dynamic> json) => AuthResponse(
    token: json['token'],
    userId: json['user_id'],
    displayName: json['display_name'],
    isAdmin: json['is_admin'],
  );
}
```

- [ ] **Step 2: Write group model**

```dart
// lib/models/group.dart
class Group {
  final String id;
  final String name;
  final String ownerId;
  final List<GroupMember> members;

  Group({required this.id, required this.name, required this.ownerId, required this.members});

  factory Group.fromJson(Map<String, dynamic> json) => Group(
    id: json['id'],
    name: json['name'],
    ownerId: json['owner_id'],
    members: (json['members'] as List).map((m) => GroupMember.fromJson(m)).toList(),
  );
}

class GroupMember {
  final String userId;
  final String role;
  final String precision;

  GroupMember({required this.userId, required this.role, required this.precision});

  factory GroupMember.fromJson(Map<String, dynamic> json) => GroupMember(
    userId: json['user_id'],
    role: json['role'],
    precision: json['precision'],
  );
}
```

- [ ] **Step 3: Write item model**

```dart
// lib/models/item.dart
class Item {
  final String id;
  final String ownerId;
  final String name;
  final String trackerType;
  final String? sourceId;
  final List<ItemShare> shares;

  Item({required this.id, required this.ownerId, required this.name, required this.trackerType, this.sourceId, required this.shares});

  factory Item.fromJson(Map<String, dynamic> json) => Item(
    id: json['id'],
    ownerId: json['owner_id'],
    name: json['name'],
    trackerType: json['tracker_type'],
    sourceId: json['source_id'],
    shares: (json['shares'] as List? ?? []).map((s) => ItemShare.fromJson(s)).toList(),
  );
}

class ItemShare {
  final String targetType;
  final String targetId;
  final String precision;

  ItemShare({required this.targetType, required this.targetId, required this.precision});

  factory ItemShare.fromJson(Map<String, dynamic> json) => ItemShare(
    targetType: json['target_type'],
    targetId: json['target_id'],
    precision: json['precision'],
  );
}
```

- [ ] **Step 4: Write location_update model**

```dart
// lib/models/location_update.dart
class LocationUpdate {
  final String from;
  final String encryptedBlob;
  final String sourceType;
  final int timestamp;

  LocationUpdate({required this.from, required this.encryptedBlob, required this.sourceType, required this.timestamp});

  factory LocationUpdate.fromJson(Map<String, dynamic> json) => LocationUpdate(
    from: json['from'] ?? '',
    encryptedBlob: json['encrypted_blob'] ?? '',
    sourceType: json['source_type'] ?? 'native',
    timestamp: json['timestamp'] ?? 0,
  );
}

/// Decrypted location data (for now, no encryption — will add MLS later)
class LocationData {
  final double lat;
  final double lon;
  final double? accuracy;
  final double? speed;
  final double? heading;
  final int? battery;
  final String? activity;
  final int timestamp;

  LocationData({
    required this.lat, required this.lon, this.accuracy,
    this.speed, this.heading, this.battery, this.activity,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'lat': lat, 'lon': lon, 'accuracy': accuracy,
    'speed': speed, 'heading': heading, 'battery': battery,
    'activity': activity, 'timestamp': timestamp,
  };

  factory LocationData.fromJson(Map<String, dynamic> json) => LocationData(
    lat: (json['lat'] as num).toDouble(),
    lon: (json['lon'] as num).toDouble(),
    accuracy: (json['accuracy'] as num?)?.toDouble(),
    speed: (json['speed'] as num?)?.toDouble(),
    heading: (json['heading'] as num?)?.toDouble(),
    battery: json['battery'] as int?,
    activity: json['activity'] as String?,
    timestamp: json['timestamp'] as int,
  );
}
```

- [ ] **Step 5: Write auth_service.dart**

```dart
// lib/services/auth_service.dart
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const _tokenKey = 'auth_token';
  static const _userIdKey = 'user_id';
  static const _displayNameKey = 'display_name';
  static const _isAdminKey = 'is_admin';

  Future<void> saveAuth(String token, String userId, String displayName, bool isAdmin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userIdKey, userId);
    await prefs.setString(_displayNameKey, displayName);
    await prefs.setBool(_isAdminKey, isAdmin);
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userIdKey);
  }

  Future<String?> getDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_displayNameKey);
  }

  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_displayNameKey);
    await prefs.remove(_isAdminKey);
  }
}
```

- [ ] **Step 6: Write api_service.dart**

```dart
// lib/services/api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/user.dart';
import '../models/group.dart';
import '../models/item.dart';

class ApiService {
  String? _token;

  void setToken(String token) => _token = token;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  // Auth
  Future<AuthResponse> register(String username, String displayName, String password, {String? inviteCode}) async {
    final body = {'username': username, 'display_name': displayName, 'password': password};
    if (inviteCode != null) body['invite_code'] = inviteCode;
    final res = await http.post(Uri.parse('${AppConfig.serverUrl}/api/register'), headers: _headers, body: jsonEncode(body));
    if (res.statusCode != 200) throw ApiException(res.statusCode, _parseError(res.body));
    return AuthResponse.fromJson(jsonDecode(res.body));
  }

  Future<AuthResponse> login(String username, String password) async {
    final res = await http.post(Uri.parse('${AppConfig.serverUrl}/api/login'), headers: _headers, body: jsonEncode({'username': username, 'password': password}));
    if (res.statusCode != 200) throw ApiException(res.statusCode, _parseError(res.body));
    return AuthResponse.fromJson(jsonDecode(res.body));
  }

  // Groups
  Future<Group> createGroup(String name) async {
    final res = await http.post(Uri.parse('${AppConfig.serverUrl}/api/groups'), headers: _headers, body: jsonEncode({'name': name}));
    if (res.statusCode != 200) throw ApiException(res.statusCode, _parseError(res.body));
    return Group.fromJson(jsonDecode(res.body));
  }

  Future<List<Group>> listGroups() async {
    final res = await http.get(Uri.parse('${AppConfig.serverUrl}/api/groups'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(res.statusCode, _parseError(res.body));
    return (jsonDecode(res.body) as List).map((g) => Group.fromJson(g)).toList();
  }

  Future<void> addMember(String groupId, String userId, {String role = 'member'}) async {
    final res = await http.post(Uri.parse('${AppConfig.serverUrl}/api/groups/$groupId/members'), headers: _headers, body: jsonEncode({'user_id': userId, 'role': role}));
    if (res.statusCode != 200) throw ApiException(res.statusCode, _parseError(res.body));
  }

  // Items
  Future<Item> createItem(String name, String trackerType, {String? sourceId}) async {
    final body = {'name': name, 'tracker_type': trackerType};
    if (sourceId != null) body['source_id'] = sourceId;
    final res = await http.post(Uri.parse('${AppConfig.serverUrl}/api/items'), headers: _headers, body: jsonEncode(body));
    if (res.statusCode != 200) throw ApiException(res.statusCode, _parseError(res.body));
    return Item.fromJson(jsonDecode(res.body));
  }

  Future<List<Item>> listItems() async {
    final res = await http.get(Uri.parse('${AppConfig.serverUrl}/api/items'), headers: _headers);
    if (res.statusCode != 200) throw ApiException(res.statusCode, _parseError(res.body));
    return (jsonDecode(res.body) as List).map((i) => Item.fromJson(i)).toList();
  }

  Future<void> shareItem(String itemId, String targetType, String targetId) async {
    final res = await http.post(Uri.parse('${AppConfig.serverUrl}/api/items/$itemId/share'), headers: _headers, body: jsonEncode({'target_type': targetType, 'target_id': targetId}));
    if (res.statusCode != 200) throw ApiException(res.statusCode, _parseError(res.body));
  }

  // Invites
  Future<Map<String, dynamic>> createInvite({int maxUses = 1}) async {
    final res = await http.post(Uri.parse('${AppConfig.serverUrl}/api/invites'), headers: _headers, body: jsonEncode({'max_uses': maxUses}));
    if (res.statusCode != 200) throw ApiException(res.statusCode, _parseError(res.body));
    return jsonDecode(res.body);
  }

  String _parseError(String body) {
    try { return jsonDecode(body)['error'] ?? body; } catch (_) { return body; }
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
  @override
  String toString() => 'ApiException($statusCode): $message';
}
```

- [ ] **Step 7: Verify build**

```bash
cd /Users/parker/Developer/GlobalMap/point && flutter build apk --debug 2>&1 | tail -3
```

- [ ] **Step 8: Commit**

```bash
cd /Users/parker/Developer/GlobalMap
git add point/
git commit -m "feat: models and API service for auth, groups, items"
```

---

### Task 3: Auth Provider & Login/Register Screens

**Files:**
- Create: `point/lib/providers/auth_provider.dart`
- Create: `point/lib/screens/login_screen.dart`
- Create: `point/lib/screens/register_screen.dart`
- Modify: `point/lib/main.dart` — add providers, routing

- [ ] **Step 1: Write auth_provider.dart**

```dart
// lib/providers/auth_provider.dart
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final ApiService _api;
  final AuthService _auth;

  bool _isLoggedIn = false;
  bool _isLoading = true;
  String? _userId;
  String? _displayName;
  bool _isAdmin = false;
  String? _token;
  String? _error;

  bool get isLoggedIn => _isLoggedIn;
  bool get isLoading => _isLoading;
  String? get userId => _userId;
  String? get displayName => _displayName;
  bool get isAdmin => _isAdmin;
  String? get token => _token;
  String? get error => _error;

  AuthProvider(this._api, this._auth) {
    _init();
  }

  Future<void> _init() async {
    _isLoading = true;
    notifyListeners();

    final token = await _auth.getToken();
    if (token != null) {
      _token = token;
      _userId = await _auth.getUserId();
      _displayName = await _auth.getDisplayName();
      _isLoggedIn = true;
      _api.setToken(token);
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> register(String username, String displayName, String password, {String? inviteCode}) async {
    _error = null;
    notifyListeners();
    try {
      final res = await _api.register(username, displayName, password, inviteCode: inviteCode);
      await _auth.saveAuth(res.token, res.userId, res.displayName, res.isAdmin);
      _token = res.token;
      _userId = res.userId;
      _displayName = res.displayName;
      _isAdmin = res.isAdmin;
      _isLoggedIn = true;
      _api.setToken(res.token);
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> login(String username, String password) async {
    _error = null;
    notifyListeners();
    try {
      final res = await _api.login(username, password);
      await _auth.saveAuth(res.token, res.userId, res.displayName, res.isAdmin);
      _token = res.token;
      _userId = res.userId;
      _displayName = res.displayName;
      _isAdmin = res.isAdmin;
      _isLoggedIn = true;
      _api.setToken(res.token);
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await _auth.logout();
    _isLoggedIn = false;
    _token = null;
    _userId = null;
    _displayName = null;
    _isAdmin = false;
    notifyListeners();
  }
}
```

- [ ] **Step 2: Write login_screen.dart**

Clean, bold login screen matching Point's Duo aesthetic — black on white, thick type, minimal.

```dart
// lib/screens/login_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;

  Future<void> _login() async {
    setState(() => _loading = true);
    final auth = context.read<AuthProvider>();
    await auth.login(_username.text.trim(), _password.text);
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAF8),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 80),
              const Text('Point', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
              const SizedBox(height: 8),
              const Text('Sign in to continue', style: TextStyle(fontSize: 16, color: Color(0xFF999999))),
              const SizedBox(height: 48),
              TextField(
                controller: _username,
                decoration: _inputDecoration('Username'),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _password,
                decoration: _inputDecoration('Password'),
                obscureText: true,
                onSubmitted: (_) => _login(),
              ),
              if (auth.error != null) ...[
                const SizedBox(height: 12),
                Text(auth.error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A1A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Sign In'),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
                  child: const Text("Don't have an account? Register", style: TextStyle(color: Color(0xFF999999))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Color(0xFF999999)),
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1A1A1A), width: 2)),
  );
}
```

- [ ] **Step 3: Write register_screen.dart**

```dart
// lib/screens/register_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  final _password = TextEditingController();
  final _inviteCode = TextEditingController();
  bool _loading = false;

  Future<void> _register() async {
    setState(() => _loading = true);
    final auth = context.read<AuthProvider>();
    final success = await auth.register(
      _username.text.trim(),
      _displayName.text.trim(),
      _password.text,
      inviteCode: _inviteCode.text.trim().isEmpty ? null : _inviteCode.text.trim(),
    );
    setState(() => _loading = false);
    if (success && mounted) Navigator.popUntil(context, (r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAF8),
      appBar: AppBar(backgroundColor: const Color(0xFFFAFAF8), elevation: 0, foregroundColor: const Color(0xFF1A1A1A)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              const Text('Create Account', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
              const SizedBox(height: 32),
              TextField(controller: _username, decoration: _inputDecoration('Username'), textInputAction: TextInputAction.next),
              const SizedBox(height: 12),
              TextField(controller: _displayName, decoration: _inputDecoration('Display Name'), textInputAction: TextInputAction.next),
              const SizedBox(height: 12),
              TextField(controller: _password, decoration: _inputDecoration('Password'), obscureText: true, textInputAction: TextInputAction.next),
              const SizedBox(height: 12),
              TextField(controller: _inviteCode, decoration: _inputDecoration('Invite Code (first user can skip)'), textInputAction: TextInputAction.done, onSubmitted: (_) => _register()),
              if (auth.error != null) ...[
                const SizedBox(height: 12),
                Text(auth.error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _register,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A1A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Create Account'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Color(0xFF999999)),
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1A1A1A), width: 2)),
  );
}
```

- [ ] **Step 4: Update main.dart with providers and routing**

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const PointApp());
}

class PointApp extends StatelessWidget {
  const PointApp({super.key});

  @override
  Widget build(BuildContext context) {
    final apiService = ApiService();
    final authService = AuthService();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider(apiService, authService)),
      ],
      child: MaterialApp(
        title: 'Point',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A1A1A), brightness: Brightness.light),
          scaffoldBackgroundColor: const Color(0xFFFAFAF8),
          useMaterial3: true,
        ),
        home: const AuthGate(),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return auth.isLoggedIn ? const HomeScreen() : const LoginScreen();
  }
}
```

- [ ] **Step 5: Create placeholder home_screen.dart**

```dart
// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAF8),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Welcome, ${auth.displayName}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(auth.userId ?? '', style: const TextStyle(color: Color(0xFF999999))),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => auth.logout(),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A1A1A), foregroundColor: Colors.white),
                child: const Text('Sign Out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Build and test on device**

Start the Point server first, then run the app. Make sure to update `config.dart` with the correct server IP if testing on a real device.

```bash
cd /Users/parker/Developer/GlobalMap/point && flutter run -d R5CW22SH8SD
```

- [ ] **Step 7: Commit**

```bash
cd /Users/parker/Developer/GlobalMap
git add point/
git commit -m "feat: auth provider, login/register screens with Duo aesthetic"
```

---

### Task 4: WebSocket Service & Location Provider

**Files:**
- Create: `point/lib/services/ws_service.dart`
- Create: `point/lib/services/location_service.dart`
- Create: `point/lib/providers/location_provider.dart`

- [ ] **Step 1: Write ws_service.dart**

```dart
// lib/services/ws_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config.dart';

class WsService {
  WebSocketChannel? _channel;
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Timer? _reconnectTimer;
  String? _token;
  bool _connected = false;
  int _reconnectDelay = 1;

  Stream<Map<String, dynamic>> get messages => _messageController.stream;
  bool get isConnected => _connected;

  void connect(String token) {
    _token = token;
    _doConnect();
  }

  void _doConnect() {
    if (_token == null) return;
    try {
      _channel = WebSocketChannel.connect(Uri.parse('${AppConfig.wsUrl}?token=$_token'));
      _connected = true;
      _reconnectDelay = 1;

      _channel!.stream.listen(
        (data) {
          try {
            final msg = jsonDecode(data as String) as Map<String, dynamic>;
            _messageController.add(msg);
          } catch (_) {}
        },
        onDone: _onDisconnect,
        onError: (_) => _onDisconnect(),
      );
    } catch (_) {
      _onDisconnect();
    }
  }

  void _onDisconnect() {
    _connected = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: _reconnectDelay), () {
      _reconnectDelay = (_reconnectDelay * 2).clamp(1, 300);
      _doConnect();
    });
  }

  void send(Map<String, dynamic> message) {
    if (_channel != null && _connected) {
      _channel!.sink.add(jsonEncode(message));
    }
  }

  void sendLocationUpdate({
    required String recipientType,
    required String recipientId,
    required String encryptedBlob,
    String sourceType = 'native',
    required int timestamp,
    int ttl = 300,
  }) {
    send({
      'type': 'location.update',
      'recipient_type': recipientType,
      'recipient_id': recipientId,
      'encrypted_blob': encryptedBlob,
      'source_type': sourceType,
      'timestamp': timestamp,
      'ttl': ttl,
    });
  }

  void sendPresence({int? battery, String? activity}) {
    send({
      'type': 'presence.update',
      'battery': battery,
      'activity': activity,
    });
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _connected = false;
  }

  void dispose() {
    disconnect();
    _messageController.close();
  }
}
```

- [ ] **Step 2: Write location_service.dart**

```dart
// lib/services/location_service.dart
import 'dart:async';
import 'package:geolocator/geolocator.dart';

class LocationService {
  StreamSubscription<Position>? _subscription;
  final _positionController = StreamController<Position>.broadcast();

  Stream<Position> get positions => _positionController.stream;

  Future<bool> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      return false;
    }
    return true;
  }

  Future<Position?> getCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
    } catch (_) {
      return null;
    }
  }

  void startTracking({int intervalMs = 10000, int distanceFilter = 10}) {
    _subscription?.cancel();

    final settings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: distanceFilter,
      intervalDuration: Duration(milliseconds: intervalMs),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'Point',
        notificationText: 'Sharing your location',
        enableWakeLock: true,
      ),
    );

    _subscription = Geolocator.getPositionStream(locationSettings: settings).listen(
      (position) => _positionController.add(position),
      onError: (_) {},
    );
  }

  void stopTracking() {
    _subscription?.cancel();
    _subscription = null;
  }

  void dispose() {
    stopTracking();
    _positionController.close();
  }
}
```

- [ ] **Step 3: Write location_provider.dart**

```dart
// lib/providers/location_provider.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../models/location_update.dart';
import '../services/ws_service.dart';
import '../services/location_service.dart';

class PersonLocation {
  final String userId;
  final double lat;
  final double lon;
  final String sourceType;
  final int timestamp;
  final int? battery;
  final String? activity;
  final bool online;

  PersonLocation({
    required this.userId, required this.lat, required this.lon,
    required this.sourceType, required this.timestamp,
    this.battery, this.activity, this.online = false,
  });
}

class LocationProvider extends ChangeNotifier {
  final WsService _ws;
  final LocationService _location;

  final Map<String, PersonLocation> _people = {};
  Position? _myPosition;
  bool _sharing = false;
  StreamSubscription? _wsSub;
  StreamSubscription? _locationSub;
  List<String> _activeGroupIds = [];

  Map<String, PersonLocation> get people => Map.unmodifiable(_people);
  Position? get myPosition => _myPosition;
  bool get isSharing => _sharing;

  LocationProvider(this._ws, this._location) {
    _wsSub = _ws.messages.listen(_handleMessage);
  }

  void setActiveGroups(List<String> groupIds) {
    _activeGroupIds = groupIds;
  }

  Future<void> startSharing() async {
    final permitted = await _location.requestPermission();
    if (!permitted) return;

    _sharing = true;
    _location.startTracking();

    _locationSub = _location.positions.listen((pos) {
      _myPosition = pos;

      // Send to all active groups (no encryption yet — will add MLS later)
      final locationData = LocationData(
        lat: pos.latitude, lon: pos.longitude,
        accuracy: pos.accuracy, speed: pos.speed,
        heading: pos.heading, timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
      final blob = base64Encode(utf8.encode(jsonEncode(locationData.toJson())));

      for (final groupId in _activeGroupIds) {
        _ws.sendLocationUpdate(
          recipientType: 'group',
          recipientId: groupId,
          encryptedBlob: blob,
          timestamp: locationData.timestamp,
        );
      }

      notifyListeners();
    });

    notifyListeners();
  }

  void stopSharing() {
    _sharing = false;
    _location.stopTracking();
    _locationSub?.cancel();
    _locationSub = null;
    notifyListeners();
  }

  void _handleMessage(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;
    if (type == 'location.broadcast') {
      _handleLocationBroadcast(msg);
    } else if (type == 'presence.broadcast') {
      _handlePresenceBroadcast(msg);
    }
  }

  void _handleLocationBroadcast(Map<String, dynamic> msg) {
    final from = msg['from'] as String? ?? '';
    final blob = msg['encrypted_blob'] as String? ?? '';
    final sourceType = msg['source_type'] as String? ?? 'native';
    final timestamp = msg['timestamp'] as int? ?? 0;

    try {
      // Decode (no encryption yet)
      final decoded = jsonDecode(utf8.decode(base64Decode(blob)));
      final loc = LocationData.fromJson(decoded);

      _people[from] = PersonLocation(
        userId: from, lat: loc.lat, lon: loc.lon,
        sourceType: sourceType, timestamp: timestamp,
        battery: loc.battery, activity: loc.activity,
        online: _people[from]?.online ?? true,
      );
      notifyListeners();
    } catch (_) {}
  }

  void _handlePresenceBroadcast(Map<String, dynamic> msg) {
    final userId = msg['user_id'] as String? ?? '';
    final online = msg['online'] as bool? ?? false;
    final battery = msg['battery'] as int?;
    final activity = msg['activity'] as String?;

    if (_people.containsKey(userId)) {
      final existing = _people[userId]!;
      _people[userId] = PersonLocation(
        userId: userId, lat: existing.lat, lon: existing.lon,
        sourceType: existing.sourceType, timestamp: existing.timestamp,
        battery: battery ?? existing.battery,
        activity: activity ?? existing.activity,
        online: online,
      );
    } else {
      _people[userId] = PersonLocation(
        userId: userId, lat: 0, lon: 0,
        sourceType: 'native', timestamp: 0,
        battery: battery, activity: activity, online: online,
      );
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _locationSub?.cancel();
    _location.dispose();
    super.dispose();
  }
}
```

- [ ] **Step 4: Update AndroidManifest.xml for location permissions**

Add to `android/app/src/main/AndroidManifest.xml` inside `<manifest>`:
```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
<uses-permission android:name="android.permission.INTERNET" />
```

Also need to set `android:foregroundServiceType="location"` on the app's service if geolocator creates one.

- [ ] **Step 5: Update main.dart with location providers**

Update the providers in main.dart to include WsService, LocationService, and LocationProvider. Wire them up to connect WebSocket after login.

- [ ] **Step 6: Build and verify**

```bash
cd /Users/parker/Developer/GlobalMap/point && flutter build apk --debug
```

- [ ] **Step 7: Commit**

```bash
cd /Users/parker/Developer/GlobalMap
git add point/
git commit -m "feat: WebSocket service, location tracking, and location provider"
```

---

### Task 5: Home Screen with Map & Drawer (Duo Layout)

**Files:**
- Modify: `point/lib/screens/home_screen.dart`
- Create: `point/lib/widgets/map_view.dart`
- Create: `point/lib/widgets/people_drawer.dart`
- Create: `point/lib/widgets/filter_bar.dart`
- Create: `point/lib/widgets/person_row.dart`
- Create: `point/lib/widgets/item_row.dart`
- Create: `point/lib/providers/group_provider.dart`

- [ ] **Step 1: Write group_provider.dart**

```dart
// lib/providers/group_provider.dart
import 'package:flutter/foundation.dart';
import '../models/group.dart';
import '../services/api_service.dart';

class GroupProvider extends ChangeNotifier {
  final ApiService _api;
  List<Group> _groups = [];
  String? _selectedGroupId;
  bool _loading = false;

  List<Group> get groups => _groups;
  String? get selectedGroupId => _selectedGroupId;
  Group? get selectedGroup => _groups.where((g) => g.id == _selectedGroupId).firstOrNull;
  bool get isLoading => _loading;

  GroupProvider(this._api);

  Future<void> loadGroups() async {
    _loading = true;
    notifyListeners();
    try {
      _groups = await _api.listGroups();
      if (_selectedGroupId == null && _groups.isNotEmpty) {
        _selectedGroupId = _groups.first.id;
      }
    } catch (_) {}
    _loading = false;
    notifyListeners();
  }

  void selectGroup(String? id) {
    _selectedGroupId = id;
    notifyListeners();
  }

  Future<Group?> createGroup(String name) async {
    try {
      final group = await _api.createGroup(name);
      _groups.add(group);
      notifyListeners();
      return group;
    } catch (_) {
      return null;
    }
  }
}
```

- [ ] **Step 2: Write filter_bar.dart**

```dart
// lib/widgets/filter_bar.dart
import 'package:flutter/material.dart';

enum FilterMode { all, people, items }

class FilterBar extends StatelessWidget {
  final FilterMode selected;
  final ValueChanged<FilterMode> onChanged;

  const FilterBar({super.key, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: FilterMode.values.map((mode) {
          final active = mode == selected;
          return GestureDetector(
            onTap: () => onChanged(mode),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: active ? const Color(0xFF1A1A1A) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                mode.name[0].toUpperCase() + mode.name.substring(1),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : const Color(0xFFAAAAAA),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
```

- [ ] **Step 3: Write person_row.dart**

```dart
// lib/widgets/person_row.dart
import 'package:flutter/material.dart';
import '../providers/location_provider.dart';

class PersonRow extends StatelessWidget {
  final PersonLocation person;
  final String? displayName;

  const PersonRow({super.key, required this.person, this.displayName});

  @override
  Widget build(BuildContext context) {
    final name = displayName ?? person.userId.split('@').first;
    final initial = name[0].toUpperCase();
    final timeDiff = DateTime.now().millisecondsSinceEpoch ~/ 1000 - person.timestamp;
    final timeStr = timeDiff < 60 ? 'just now' : timeDiff < 3600 ? '${timeDiff ~/ 60}m ago' : '${timeDiff ~/ 3600}h ago';
    final isStale = timeDiff > 7200;

    return Opacity(
      opacity: isStale ? 0.35 : 1.0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: _colorForUser(person.userId),
                  child: Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                ),
                if (person.online)
                  Positioned(
                    bottom: 0, right: 0,
                    child: Container(
                      width: 11, height: 11,
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
                      const SizedBox(width: 6),
                      _buildBadge(person.sourceType),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    person.activity ?? (person.online ? 'online' : 'offline'),
                    style: const TextStyle(fontSize: 11, color: Color(0xFF999999)),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (person.lat != 0) Text(timeStr, style: const TextStyle(fontSize: 10, color: Color(0xFFCCCCCC))),
                if (person.battery != null)
                  Text('${person.battery}%', style: const TextStyle(fontSize: 10, color: Color(0xFFCCCCCC))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(String sourceType) {
    final (label, color) = switch (sourceType) {
      'native' => ('E2E', const Color(0xFF16A34A)),
      String s when s.startsWith('bridge:findmy') => ('Find My', const Color(0xFFE85D5D)),
      String s when s.startsWith('bridge:google') => ('Google', const Color(0xFFC49A5A)),
      _ => ('', Colors.transparent),
    };
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: color)),
    );
  }

  Color _colorForUser(String userId) {
    final colors = [
      const Color(0xFFE85D5D), const Color(0xFF4A9E6B), const Color(0xFFC49A5A),
      const Color(0xFF7A8AAB), const Color(0xFF9B6B9E), const Color(0xFF5A8AAB),
    ];
    return colors[userId.hashCode.abs() % colors.length];
  }
}
```

- [ ] **Step 4: Write map_view.dart**

```dart
// lib/widgets/map_view.dart
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/location_provider.dart';

class MapView extends StatefulWidget {
  const MapView({super.key});
  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  GoogleMapController? _controller;

  @override
  Widget build(BuildContext context) {
    final locationProv = context.watch<LocationProvider>();
    final myPos = locationProv.myPosition;
    final people = locationProv.people;

    final markers = <Marker>{};

    // Add markers for people
    for (final entry in people.entries) {
      final person = entry.value;
      if (person.lat == 0 && person.lon == 0) continue;
      markers.add(Marker(
        markerId: MarkerId(person.userId),
        position: LatLng(person.lat, person.lon),
        infoWindow: InfoWindow(title: person.userId.split('@').first),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          person.sourceType == 'native' ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueOrange,
        ),
      ));
    }

    // My position marker
    if (myPos != null) {
      markers.add(Marker(
        markerId: const MarkerId('me'),
        position: LatLng(myPos.latitude, myPos.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: 'You'),
      ));
    }

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: myPos != null ? LatLng(myPos.latitude, myPos.longitude) : const LatLng(37.7749, -122.4194),
        zoom: 14,
      ),
      markers: markers,
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      onMapCreated: (controller) => _controller = controller,
    );
  }
}
```

- [ ] **Step 5: Write people_drawer.dart**

```dart
// lib/widgets/people_drawer.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/location_provider.dart';
import 'person_row.dart';

class PeopleDrawer extends StatelessWidget {
  const PeopleDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final locationProv = context.watch<LocationProvider>();
    final people = locationProv.people.values.toList();

    // Sort: online first, then by timestamp descending
    people.sort((a, b) {
      if (a.online && !b.online) return -1;
      if (!a.online && b.online) return 1;
      return b.timestamp.compareTo(a.timestamp);
    });

    return Column(
      children: [
        // Handle
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.black.withOpacity(0.08), borderRadius: BorderRadius.circular(2))),
        ),
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
          child: Row(
            children: [
              const Text('People', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
              const Spacer(),
              Text('${people.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFCCCCCC))),
            ],
          ),
        ),
        // List
        Expanded(
          child: people.isEmpty
            ? const Center(child: Text('No one sharing yet', style: TextStyle(color: Color(0xFFCCCCCC))))
            : ListView.separated(
                itemCount: people.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: Colors.black.withOpacity(0.04), indent: 18, endIndent: 18),
                itemBuilder: (_, i) => PersonRow(person: people[i]),
              ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 6: Write home_screen.dart (full Duo layout)**

```dart
// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/location_provider.dart';
import '../providers/group_provider.dart';
import '../widgets/map_view.dart';
import '../widgets/people_drawer.dart';
import '../widgets/filter_bar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  FilterMode _filterMode = FilterMode.all;
  bool _mapExpanded = false;
  int _currentTab = 0;

  @override
  void initState() {
    super.initState();
    // Load groups on startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GroupProvider>().loadGroups();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F3EF),
      body: SafeArea(child: _buildBody()),
      bottomNavigationBar: _buildTabBar(),
    );
  }

  Widget _buildBody() {
    if (_currentTab == 0) return _buildMapTab();
    if (_currentTab == 1) return _buildInboxTab();
    return _buildProfileTab();
  }

  Widget _buildMapTab() {
    final locationProv = context.watch<LocationProvider>();

    return Column(
      children: [
        // Map area
        Expanded(
          flex: _mapExpanded ? 8 : 5,
          child: Stack(
            children: [
              const MapView(),
              // Filter bar
              Positioned(
                top: 10,
                left: 0,
                right: 0,
                child: Center(
                  child: FilterBar(selected: _filterMode, onChanged: (m) => setState(() => _filterMode = m)),
                ),
              ),
              // Expand button
              Positioned(
                bottom: 12,
                right: 12,
                child: GestureDetector(
                  onTap: () => setState(() => _mapExpanded = !_mapExpanded),
                  child: Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8)],
                    ),
                    child: Icon(_mapExpanded ? Icons.fullscreen_exit : Icons.fullscreen, size: 18, color: Colors.black45),
                  ),
                ),
              ),
              // Share location FAB
              Positioned(
                bottom: 12,
                left: 12,
                child: GestureDetector(
                  onTap: () {
                    if (locationProv.isSharing) {
                      locationProv.stopSharing();
                    } else {
                      locationProv.startSharing();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: locationProv.isSharing ? const Color(0xFF1A1A1A) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8)],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          locationProv.isSharing ? Icons.location_on : Icons.location_off_outlined,
                          size: 16,
                          color: locationProv.isSharing ? Colors.white : Colors.black45,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          locationProv.isSharing ? 'Sharing' : 'Share',
                          style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700,
                            color: locationProv.isSharing ? Colors.white : Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Drawer
        if (!_mapExpanded)
          Expanded(
            flex: 4,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                boxShadow: [BoxShadow(color: Color(0x08000000), blurRadius: 20, offset: Offset(0, -4))],
              ),
              child: const PeopleDrawer(),
            ),
          ),
      ],
    );
  }

  Widget _buildInboxTab() {
    return const Center(child: Text('Inbox', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)));
  }

  Widget _buildProfileTab() {
    final auth = context.watch<AuthProvider>();
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(auth.displayName ?? '', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(auth.userId ?? '', style: const TextStyle(color: Color(0xFF999999))),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => auth.logout(),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A1A1A), foregroundColor: Colors.white),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0x0D000000))),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              _tabItem(0, Icons.location_on_outlined, Icons.location_on, 'Map'),
              _tabItem(1, Icons.inbox_outlined, Icons.inbox, 'Inbox'),
              _tabItem(2, Icons.person_outline, Icons.person, 'Profile'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabItem(int index, IconData icon, IconData activeIcon, String label) {
    final active = _currentTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _currentTab = index),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (active) Container(width: 18, height: 2.5, decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(1))),
            const SizedBox(height: 4),
            Icon(active ? activeIcon : icon, size: 24, color: active ? const Color(0xFF1A1A1A) : const Color(0xFFCCCCCC)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: active ? const Color(0xFF1A1A1A) : const Color(0xFFCCCCCC))),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: Update main.dart with all providers**

Wire up WsService, LocationService, LocationProvider, GroupProvider in the MultiProvider. Connect WebSocket after auth. Load groups on login.

- [ ] **Step 8: Add Google Maps API key**

Add your Google Maps API key to `android/app/src/main/AndroidManifest.xml` inside `<application>`:
```xml
<meta-data android:name="com.google.android.geo.API_KEY" android:value="YOUR_API_KEY"/>
```

- [ ] **Step 9: Build and run on device**

```bash
cd /Users/parker/Developer/GlobalMap/point && flutter run -d R5CW22SH8SD
```

- [ ] **Step 10: Commit**

```bash
cd /Users/parker/Developer/GlobalMap
git add point/
git commit -m "feat: home screen with Duo layout - map, drawer, filter bar, tab navigation"
```

---

## Plan Summary

| Task | What it builds | Key outcome |
|------|---------------|-------------|
| 1 | Flutter scaffold | App runs, shows "Point" |
| 2 | Models + API service | REST client for all server endpoints |
| 3 | Auth provider + screens | Login/register with Duo aesthetic |
| 4 | WebSocket + location | Real-time location sharing and tracking |
| 5 | Home screen + map + drawer | Full Duo layout with map, people list, filter bar, tabs |

**After this plan:** The app connects to the Point server, lets you register/login, shows a map with people's locations in real-time, and has the Duo split-screen layout. Next: MLS encryption, group management UI, item management UI.
