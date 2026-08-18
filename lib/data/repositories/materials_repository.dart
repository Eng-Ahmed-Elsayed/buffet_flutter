import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_config.dart';
import '../api/api_exception.dart';
import '../models/material_models.dart';

/// The caller's own material balances, and declaring new ones.
class MaterialsRepository {
  const MaterialsRepository(this._dio);

  final Dio _dio;

  Future<List<MyMaterialDto>> fetchMine({
    required String languageCode,
    required String networkErrorFallback,
  }) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        ApiConfig.myMaterials,
        options: Options(extra: {ApiConfig.languageFlag: languageCode}),
      );
      return (response.data ?? [])
          .map((e) => MyMaterialDto.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error, networkErrorFallback);
    }
  }

  /// Declares materials handed to staff.
  ///
  /// Returns **`202 Accepted`, not `201`** — and that distinction is the whole
  /// point. **A declaration creates nothing** until an admin confirms receipt,
  /// so the caller must say "awaiting confirmation" and never "added". A user
  /// who believes they have stock they do not have will be surprised by the
  /// first order that draws on it (§7.5).
  ///
  /// Confirming is admin-only and happens on the web — there is deliberately
  /// no confirm/reject path in this client (§8.2).
  Future<void> declare({
    required DeclareMaterialRequest request,
    required String languageCode,
    required String networkErrorFallback,
  }) async {
    try {
      await _dio.post<void>(
        ApiConfig.declareMaterial,
        data: request.toJson(),
        options: Options(extra: {ApiConfig.languageFlag: languageCode}),
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error, networkErrorFallback);
    }
  }
}

final materialsRepositoryProvider = Provider<MaterialsRepository>(
  (ref) => MaterialsRepository(ref.watch(dioProvider)),
);
