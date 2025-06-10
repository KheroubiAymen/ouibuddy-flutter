import 'package:http/http.dart' as http;
import 'dart:convert';

// Service pour récupérer les évaluations (AVEC XSRF-TOKEN)
class EvaluationService {
  static const String baseUrl = 'https://ouibuddy.com/api';

  // Récupérer les évaluations à venir via WebView (XSRF-TOKEN)
  static Future<Map<String, dynamic>?> fetchEvaluationsViaWebView(
      dynamic webViewController, {
        int? userId,
        int daysAhead = 14,
        String endpoint = 'upcoming-evaluations',
      }) async {
    try {
      print('🔍 Récupération évaluations via WebView (XSRF-TOKEN)...');

      // Étape 1: Vérifier que nous sommes sur le bon site
      final currentUrl = await webViewController.runJavaScriptReturningResult(
          'window.location.href'
      );

      print('🌐 URL actuelle: $currentUrl');

      // Étape 2: Extraire le token CSRF ET XSRF-TOKEN (méthode principale)
      final authData = await webViewController.runJavaScriptReturningResult('''
        (function() {
          try {
            // Récupérer le token CSRF
            var csrfMeta = document.querySelector('meta[name="csrf-token"]');
            var csrfToken = csrfMeta ? csrfMeta.getAttribute('content') : null;
            
            // Récupérer tous les cookies
            var cookies = document.cookie;
            
            // Extraire spécifiquement XSRF-TOKEN et laravel_session
            var xsrfToken = null;
            var laravelSession = null;
            
            if (cookies) {
              var cookieArray = cookies.split(';');
              for (var i = 0; i < cookieArray.length; i++) {
                var cookie = cookieArray[i].trim().split('=');
                if (cookie[0] === 'XSRF-TOKEN') {
                  xsrfToken = decodeURIComponent(cookie[1]);
                }
                if (cookie[0] === 'laravel_session') {
                  laravelSession = cookie[1];
                }
              }
            }
            
            // L'authentification est valide si on a CSRF + XSRF OU laravel_session
            var hasAuth = !!(csrfToken && (xsrfToken || laravelSession));
            
            return JSON.stringify({
              csrf_token: csrfToken,
              xsrf_token: xsrfToken,
              laravel_session: laravelSession,
              cookies: cookies,
              has_auth: hasAuth,
              auth_method: xsrfToken ? 'xsrf' : (laravelSession ? 'session' : 'none')
            });
          } catch (error) {
            return JSON.stringify({
              error: error.message,
              has_auth: false
            });
          }
        })()
      ''');

      if (authData == null || authData.toString() == 'null') {
        print('❌ Impossible d\'extraire les données d\'authentification');
        return null;
      }

      // Parser les données d'authentification
      String cleanAuthData = authData.toString();
      if (cleanAuthData.startsWith('"') && cleanAuthData.endsWith('"')) {
        cleanAuthData = cleanAuthData.substring(1, cleanAuthData.length - 1);
      }
      cleanAuthData = cleanAuthData.replaceAll('\\"', '"');
      cleanAuthData = cleanAuthData.replaceAll('\\\\', '\\');

      final authInfo = json.decode(cleanAuthData);
      print('🔒 Auth info: ${authInfo['has_auth']}');
      print('🔑 Méthode auth: ${authInfo['auth_method']}');
      print('🍪 XSRF token: ${authInfo['xsrf_token'] != null ? "présent" : "absent"}');
      print('🍪 Laravel session: ${authInfo['laravel_session'] != null ? "présent" : "absent"}');

      if (!authInfo['has_auth']) {
        print('❌ Authentification manquante (pas de XSRF ni session)');
        return null;
      }

      // Étape 3: Faire l'appel API avec XSRF-TOKEN
      return await _makeXsrfApiCall(
          authInfo,
          userId,
          daysAhead,
          endpoint
      );

    } catch (e) {
      print('❌ Erreur WebView: $e');
      return null;
    }
  }

  // Faire l'appel API avec XSRF-TOKEN (méthode principale pour OuiBuddy)
  static Future<Map<String, dynamic>?> _makeXsrfApiCall(
      Map<String, dynamic> authInfo,
      int? userId,
      int daysAhead,
      String endpoint
      ) async {
    try {
      print('📡 Appel API avec XSRF-TOKEN...');

      // Construire l'URL
      String apiUrl = '$baseUrl/$endpoint';
      Map<String, String> params = {
        'days_ahead': daysAhead.toString(),
        'include_today': 'true',
        'per_page': '50',
      };

      if (userId != null) {
        params['user_id'] = userId.toString();
      }

      final uri = Uri.parse(apiUrl).replace(queryParameters: params);
      print('🌐 URL finale: $uri');

      // Préparer les headers avec XSRF-TOKEN
      Map<String, String> headers = {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'X-Requested-With': 'XMLHttpRequest',
        'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15',
        'Referer': 'https://ouibuddy.com/',
      };

      // Ajouter le token CSRF (obligatoire)
      if (authInfo['csrf_token'] != null) {
        headers['X-CSRF-TOKEN'] = authInfo['csrf_token'];
        print('🔒 Token CSRF ajouté');
      }

      // Ajouter les cookies complets (XSRF-TOKEN + autres)
      if (authInfo['cookies'] != null && authInfo['cookies'].toString().isNotEmpty) {
        headers['Cookie'] = authInfo['cookies'];
        print('🍪 Cookies ajoutés (avec XSRF-TOKEN)');
      }

      // Ajouter le XSRF-TOKEN aussi en header (double sécurité)
      if (authInfo['xsrf_token'] != null) {
        headers['X-XSRF-TOKEN'] = authInfo['xsrf_token'];
        print('🔑 X-XSRF-TOKEN header ajouté');
      }

      print('📋 Headers finaux: ${headers.keys.join(', ')}');

      // Faire la requête HTTP
      final response = await http.get(
        uri,
        headers: headers,
      );

      print('📊 Status HTTP: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ Données reçues: ${data['summary']?['total_evaluations'] ?? 0} évaluations');
        return data;
      } else if (response.statusCode == 401) {
        print('🔒 401 Unauthorized - XSRF token invalide ou expiré');
        print('📋 Response: ${response.body}');
        return null;
      } else if (response.statusCode == 419) {
        print('🔒 419 Token Mismatch - CSRF/XSRF token expiré');
        print('📋 Response: ${response.body}');
        return null;
      } else if (response.statusCode == 403) {
        print('🚫 403 Forbidden - Pas les permissions');
        return null;
      } else if (response.statusCode == 404) {
        print('❌ 404 Not Found - Endpoint non trouvé');
        return null;
      } else {
        print('❌ Erreur HTTP: ${response.statusCode}');
        print('❌ Body: ${response.body}');
        return null;
      }

    } catch (e) {
      print('❌ Erreur appel API: $e');
      return null;
    }
  }

  // Diagnostiquer les problèmes d'authentification (version améliorée)
  static Future<void> diagnoseAuth(dynamic webViewController) async {
    try {
      print('🔍 === DIAGNOSTIC D\'AUTHENTIFICATION XSRF ===');

      final authDiag = await webViewController.runJavaScriptReturningResult('''
        (function() {
          try {
            var csrf = document.querySelector('meta[name="csrf-token"]');
            var cookies = document.cookie;
            
            // Analyser les cookies individuellement
            var cookieAnalysis = {};
            if (cookies) {
              var cookieArray = cookies.split(';');
              cookieArray.forEach(function(cookie) {
                var parts = cookie.trim().split('=');
                if (parts.length >= 2) {
                  cookieAnalysis[parts[0]] = {
                    present: true,
                    length: parts[1].length,
                    value_preview: parts[1].substring(0, 20) + '...'
                  };
                }
              });
            }
            
            return JSON.stringify({
              csrf_present: !!csrf,
              csrf_length: csrf ? csrf.getAttribute('content').length : 0,
              csrf_preview: csrf ? csrf.getAttribute('content').substring(0, 20) + '...' : null,
              cookies_count: cookies.split(';').filter(c => c.trim()).length,
              cookie_analysis: cookieAnalysis,
              url: window.location.href,
              user_elements: !!document.querySelector('.user-info, .profile-info, [data-user]'),
              is_dashboard: window.location.href.includes('/dashboard'),
              has_user_id_in_url: /\/\d+\//.test(window.location.pathname)
            });
          } catch (e) {
            return JSON.stringify({error: e.message});
          }
        })()
      ''');

      if (authDiag != null) {
        String clean = authDiag.toString();
        if (clean.startsWith('"') && clean.endsWith('"')) {
          clean = clean.substring(1, clean.length - 1);
        }
        clean = clean.replaceAll('\\"', '"');

        final diag = json.decode(clean);
        print('🔒 CSRF présent: ${diag['csrf_present']} (longueur: ${diag['csrf_length']})');
        print('🍪 Nombre de cookies: ${diag['cookies_count']}');
        print('🌐 URL: ${diag['url']}');
        print('📍 Sur dashboard: ${diag['is_dashboard']}');
        print('👤 ID utilisateur dans URL: ${diag['has_user_id_in_url']}');

        if (diag['cookie_analysis'] != null) {
          final cookies = diag['cookie_analysis'] as Map<String, dynamic>;
          cookies.forEach((name, info) {
            print('🍪 Cookie $name: ${info['present']} (longueur: ${info['length']})');
          });
        }
      }

      print('🔍 === FIN DIAGNOSTIC ===');

    } catch (e) {
      print('❌ Erreur diagnostic auth: $e');
    }
  }

  // Récupérer les évaluations à venir sans WebView (fallback)
  static Future<Map<String, dynamic>?> fetchUpcomingEvaluations({
    int? userId,
    int daysAhead = 14,
    bool includeToday = true,
    int perPage = 20,
    String? bearerToken,
  }) async {
    try {
      print('📚 Récupération évaluations HTTP direct...');

      Map<String, String> params = {
        'days_ahead': daysAhead.toString(),
        'include_today': includeToday.toString(),
        'per_page': perPage.toString(),
      };

      if (userId != null) {
        params['user_id'] = userId.toString();
      }

      final uri = Uri.parse('$baseUrl/upcoming-evaluations').replace(
        queryParameters: params,
      );

      print('🌐 URL API directe: $uri');

      Map<String, String> headers = {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'User-Agent': 'OuiBuddy-Flutter-App/1.0',
      };

      if (bearerToken != null && bearerToken.isNotEmpty) {
        headers['Authorization'] = 'Bearer $bearerToken';
        print('🔑 Bearer token ajouté pour API directe');
      }

      final response = await http.get(uri, headers: headers);

      print('📡 Status API directe: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ Évaluations récupérées: ${data['summary']?['total_evaluations'] ?? 0}');
        return data;
      } else if (response.statusCode == 401) {
        print('🔒 401 - Authentification requise pour l\'API directe');
        return null;
      } else {
        print('❌ Erreur API directe: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('❌ Erreur récupération directe: $e');
      return null;
    }
  }

  // Parser les évaluations depuis la réponse API
  static List<Evaluation> parseEvaluations(Map<String, dynamic> apiResponse) {
    try {
      if (apiResponse['status'] == true && apiResponse['data'] != null) {
        final List<dynamic> evaluationsJson = apiResponse['data'];
        return evaluationsJson.map((json) => Evaluation.fromJson(json)).toList();
      }
      print('⚠️ Aucune évaluation dans la réponse');
      return [];
    } catch (e) {
      print('❌ Erreur parsing évaluations: $e');
      return [];
    }
  }

  // Parser le résumé depuis la réponse API
  static EvaluationSummary? parseSummary(Map<String, dynamic> apiResponse) {
    try {
      if (apiResponse['status'] == true && apiResponse['summary'] != null) {
        return EvaluationSummary.fromJson(apiResponse['summary']);
      }
      print('⚠️ Aucun résumé dans la réponse');
      return null;
    } catch (e) {
      print('❌ Erreur parsing résumé: $e');
      return null;
    }
  }
}

// MODÈLE CORRIGÉ - Conversion robuste des booléens
class Evaluation {
  final int id;
  final int profileId;
  final String? description;
  final DateTime evaluationDate;
  final int daysUntil;
  final bool isToday;
  final bool isTomorrow;
  final bool isThisWeek;
  final String evaluationDateFormatted;
  final String evaluationDayName;
  final TopicCategory? topicCategory;
  final Chapter? chapter;
  final EvaluationProfile? profile;
  final bool fromPronote;
  final bool fromSchoolhub;
  final int? groupId;
  final bool isPartOfGroup;
  final int groupMembersCount;

  Evaluation({
    required this.id,
    required this.profileId,
    this.description,
    required this.evaluationDate,
    required this.daysUntil,
    required this.isToday,
    required this.isTomorrow,
    required this.isThisWeek,
    required this.evaluationDateFormatted,
    required this.evaluationDayName,
    this.topicCategory,
    this.chapter,
    this.profile,
    required this.fromPronote,
    required this.fromSchoolhub,
    this.groupId,
    required this.isPartOfGroup,
    required this.groupMembersCount,
  });

  // FACTORY CORRIGÉ avec conversion robuste des booléens
  factory Evaluation.fromJson(Map<String, dynamic> json) {
    return Evaluation(
      id: json['id'],
      profileId: json['profile_id'],
      description: json['description'],
      evaluationDate: DateTime.parse(json['evaluation_date']),
      daysUntil: json['days_until'] ?? 0,

      // Conversion robuste pour tous les booléens
      isToday: _safeBool(json['is_today']),
      isTomorrow: _safeBool(json['is_tomorrow']),
      isThisWeek: _safeBool(json['is_this_week']),
      fromPronote: _safeBool(json['from_pronote']),
      fromSchoolhub: _safeBool(json['from_schoolhub']),
      isPartOfGroup: _safeBool(json['is_part_of_group']),

      evaluationDateFormatted: json['evaluation_date_formatted'] ?? '',
      evaluationDayName: json['evaluation_day_name'] ?? '',
      topicCategory: json['topic_category'] != null
          ? TopicCategory.fromJson(json['topic_category'])
          : null,
      chapter: json['chapter'] != null
          ? Chapter.fromJson(json['chapter'])
          : null,
      profile: json['profile'] != null
          ? EvaluationProfile.fromJson(json['profile'])
          : null,
      groupId: json['group_id'],
      groupMembersCount: json['group_members_count'] ?? 0,
    );
  }

  // MÉTHODE UTILITAIRE : Conversion robuste pour booléens
  static bool _safeBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is int) return value != 0;
    if (value is String) {
      final str = value.toLowerCase();
      return str == '1' || str == 'true' || str == 'yes';
    }
    return false;
  }

  String get urgencyLevel {
    if (isToday) return 'critical';
    if (isTomorrow) return 'high';
    if (daysUntil <= 3) return 'medium';
    if (isThisWeek) return 'low';
    return 'info';
  }

  String get urgencyText {
    if (isToday) return 'Aujourd\'hui';
    if (isTomorrow) return 'Demain';
    if (daysUntil <= 3) return 'Dans $daysUntil jours';
    if (isThisWeek) return 'Cette semaine';
    return 'Dans $daysUntil jours';
  }
}

class TopicCategory {
  final int id;
  final String name;

  TopicCategory({required this.id, required this.name});

  factory TopicCategory.fromJson(Map<String, dynamic> json) {
    return TopicCategory(
      id: json['id'],
      name: json['name'],
    );
  }
}

class Chapter {
  final int id;
  final String name;

  Chapter({required this.id, required this.name});

  factory Chapter.fromJson(Map<String, dynamic> json) {
    return Chapter(
      id: json['id'],
      name: json['name'],
    );
  }
}

class EvaluationProfile {
  final int id;
  final int userId;
  final String firstName;
  final String lastName;
  final String? email;

  EvaluationProfile({
    required this.id,
    required this.userId,
    required this.firstName,
    required this.lastName,
    this.email,
  });

  factory EvaluationProfile.fromJson(Map<String, dynamic> json) {
    return EvaluationProfile(
      id: json['id'],
      userId: json['user_id'],
      firstName: json['first_name'] ?? '',
      lastName: json['last_name'] ?? '',
      email: json['email'],
    );
  }

  String get fullName => '$firstName $lastName'.trim();
}

class EvaluationSummary {
  final int totalEvaluations;
  final int todayCount;
  final int tomorrowCount;
  final int thisWeekCount;
  final int nextWeekCount;
  final Map<String, dynamic> period;

  EvaluationSummary({
    required this.totalEvaluations,
    required this.todayCount,
    required this.tomorrowCount,
    required this.thisWeekCount,
    required this.nextWeekCount,
    required this.period,
  });

  factory EvaluationSummary.fromJson(Map<String, dynamic> json) {
    return EvaluationSummary(
      totalEvaluations: json['total_evaluations'] ?? 0,
      todayCount: json['today_count'] ?? 0,
      tomorrowCount: json['tomorrow_count'] ?? 0,
      thisWeekCount: json['this_week_count'] ?? 0,
      nextWeekCount: json['next_week_count'] ?? 0,
      period: json['period'] ?? {},
    );
  }
}