import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/accessory.dart';
import '../models/identify_result.dart';
import '../models/kind.dart';
import '../models/shop.dart';
import 'auth_service.dart';

enum ApiErrorKind { network, timeout, quota, photo, unauthorised, server }

class ApiException implements Exception {
  const ApiException(this.kind, {this.limit, this.message});
  final ApiErrorKind kind;
  final int? limit;
  final String? message;

  @override
  String toString() => 'ApiException($kind, $message)';
}

/// Everything the app asks the server. AI calls go through our edge functions only: the app
/// holds no engine keys.
class ApiService {
  ApiService(this._client, this._auth);

  final SupabaseClient _client;
  final AuthService _auth;

  static const _identifyTimeout = Duration(seconds: 25);
  static const _queryTimeout = Duration(seconds: 15);

  Future<IdentifyResult> identify({
    required Uint8List jpeg,
    required RequestCategory category,
    Map<String, dynamic>? hint,
  }) async {
    final data = await _invoke('identify', {
      'image_base64': base64Encode(jpeg),
      'category': category.name,
      if (hint != null) 'hint': hint,
    }, _identifyTimeout);
    return IdentifyResult.fromJson(data);
  }

  /// AI-written care tips for a species outside the curated list (cached on the server).
  Future<CareCard> careTips({required Kind kind, required String scientificName, required String commonName}) async {
    final data = await _invoke('care-tips', {
      'kind': kind.name,
      'scientific_name': scientificName,
      'common_name': commonName,
    }, _queryTimeout);
    return CareCard.fromJson(data['care'] as Map<String, dynamic>);
  }

  /// Curated care card for one of our taxa (used for items synced from another phone).
  Future<CareCard?> careForTaxon(int taxonId) async {
    final rows = await _guard(() => _client.rpc<List<dynamic>>('care_for', params: {'p_taxon_id': taxonId}));
    if (rows.isEmpty) return null;
    final first = rows.first as Map<String, dynamic>;
    return CareCard.fromJson({
      'status': first['status'],
      'isFallback': first['is_fallback'],
      'tips': [
        for (final r in rows.cast<Map<String, dynamic>>()) {'topic': r['topic'], 'en': r['body_en'], 'bn': r['body_bn']},
      ],
    });
  }

  Future<List<Shop>> nearbyShops({
    required double lat,
    required double lng,
    required int radiusKm,
    Kind? kind,
    int? taxonId,
    List<ShopType>? types,
  }) async {
    final rows = await _guard(() => _client.rpc<List<dynamic>>('nearby_shops', params: {
          'p_lat': lat,
          'p_lng': lng,
          'p_radius_km': radiusKm,
          'p_kind': kind?.name,
          'p_taxon_id': taxonId,
          'p_types': types?.map((t) => t.dbValue).toList(),
        }));
    final shops = rows.cast<Map<String, dynamic>>().map(Shop.fromJson).toList();
    unawaited(_logQuietly(() => _client.rpc<void>('log_shop_search', params: {
          'p_kind': kind?.name,
          'p_taxon_id': taxonId,
          'p_radius_km': radiusKm,
          'p_result_count': shops.length,
        })));
    return shops;
  }

  Future<List<Accessory>> accessories({int? taxonId, Kind? kind}) async {
    final rows = await _guard(() => _client.rpc<List<dynamic>>('accessories_for', params: {
          'p_taxon_id': taxonId,
          'p_kind': kind?.name,
        }));
    return rows.cast<Map<String, dynamic>>().map(Accessory.fromJson).toList();
  }

  /// Records a Call / WhatsApp / Directions tap for the shop reports. Never blocks the user.
  void logShopContact(String shopId, String action) {
    unawaited(_logQuietly(() => _client.rpc<void>('log_shop_contact', params: {'p_shop_id': shopId, 'p_action': action})));
  }

  Future<void> reportResult({
    required String identificationId,
    required String reason,
    String? suggestedName,
    String? note,
  }) async {
    await _guard(() => _client.from('flags').insert({
          'identification_id': identificationId,
          'reason': reason,
          if (suggestedName != null && suggestedName.trim().isNotEmpty) 'suggested_name': suggestedName.trim(),
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        }));
  }

  /// Any 2xx means the account is gone, whatever the body says.
  Future<void> deleteAccount() async {
    await _invoke('delete-account', const {}, _queryTimeout, requireBody: false);
  }

  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _invoke(
    String fn,
    Map<String, dynamic> body,
    Duration timeout, {
    bool requireBody = true,
  }) async {
    try {
      await _auth.ensureSession().timeout(_queryTimeout);
      final res = await _client.functions.invoke(fn, body: body).timeout(timeout);
      final data = res.data;
      if (data is Map<String, dynamic>) return data;
      if (!requireBody) return const <String, dynamic>{};
      throw const ApiException(ApiErrorKind.server, message: 'unexpected response'); // l10n-ok: internal
    } on FunctionException catch (e) {
      throw _fromFunction(e);
    } on TimeoutException {
      throw const ApiException(ApiErrorKind.timeout);
    } on SocketException {
      throw const ApiException(ApiErrorKind.network);
    } on AuthException catch (e) {
      throw _fromAuth(e);
    }
  }

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      await _auth.ensureSession().timeout(_queryTimeout);
      return await call().timeout(_queryTimeout);
    } on TimeoutException {
      throw const ApiException(ApiErrorKind.timeout);
    } on SocketException {
      throw const ApiException(ApiErrorKind.network);
    } on AuthException catch (e) {
      throw _fromAuth(e);
    } on PostgrestException catch (e) {
      throw ApiException(ApiErrorKind.server, message: e.message);
    }
  }

  Future<void> _logQuietly(Future<void> Function() call) async {
    try {
      await call().timeout(_queryTimeout);
    } catch (_) {
      // Analytics must never interrupt the user.
    }
  }

  ApiException _fromAuth(AuthException e) {
    if (e is AuthRetryableFetchException) return const ApiException(ApiErrorKind.network);
    return ApiException(ApiErrorKind.unauthorised, message: e.message);
  }

  ApiException _fromFunction(FunctionException e) {
    if (e is FunctionsFetchException) return const ApiException(ApiErrorKind.network);
    final details = e.details;
    final error = details is Map<String, dynamic> && details['error'] is Map<String, dynamic>
        ? details['error'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final code = error['code'] as String?;
    final message = error['message'] as String?;
    switch (e.status) {
      case 401:
        return ApiException(ApiErrorKind.unauthorised, message: message);
      case 413:
      case 415:
        return ApiException(ApiErrorKind.photo, message: message);
      case 429:
        final limit = RegExp(r'(\d+)').firstMatch(message ?? '')?.group(1);
        return ApiException(ApiErrorKind.quota, limit: limit == null ? null : int.tryParse(limit), message: message);
      case 504:
        return ApiException(ApiErrorKind.timeout, message: message);
      case 400:
        if (code != null && code.startsWith('image')) return ApiException(ApiErrorKind.photo, message: message);
        return ApiException(ApiErrorKind.server, message: message);
      default:
        return ApiException(ApiErrorKind.server, message: message);
    }
  }
}
