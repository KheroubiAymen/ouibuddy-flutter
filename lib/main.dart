import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'evaluation_service.dart';
import 'evaluation_widgets.dart';
import 'evaluation_scheduler.dart';
import 'BackgroundNotificationService.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'splash_screen.dart';
import 'dart:async';
import 'notification_service.dart';
import 'dart:io';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialiser les notifications
  await NotificationService.initialize();

  // Initialiser le service de rappels automatiques
  await BackgroundNotificationService.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OuiBuddy',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
      routes: {
        '/home': (context) => const WebViewPage(),
      },
      debugShowCheckedModeBanner: false,
    );
  }
}

// Modèle pour les données utilisateur
class UserProfile {
  final int? id;
  final String firstName;
  final String? lastName;
  final String? email;
  final int? userId;
  final bool loading;
  final bool isAuthenticated;

  UserProfile({
    this.id,
    required this.firstName,
    this.lastName,
    this.email,
    this.userId,
    this.loading = false,
    this.isAuthenticated = false,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'],
      firstName: json['first_name'] ?? 'Utilisateur',
      lastName: json['last_name'],
      email: json['email'],
      userId: json['user_id'],
      loading: false,
      isAuthenticated: true,
    );
  }

  factory UserProfile.loading() {
    return UserProfile(
      firstName: 'Chargement...',
      loading: true,
    );
  }

  factory UserProfile.defaultProfile() {
    return UserProfile(
      firstName: 'Utilisateur',
      loading: false,
      isAuthenticated: false,
    );
  }

  factory UserProfile.notAuthenticated() {
    return UserProfile(
      firstName: 'Non connecté',
      loading: false,
      isAuthenticated: false,
    );
  }
}

class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key});

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> with WidgetsBindingObserver {
  late final WebViewController controller;
  bool isLoading = true;
  bool hasError = false;
  int retryCount = 0;

  // NOUVELLES VARIABLES POUR LA GESTION DU TOKEN
  String? sessionToken;
  bool tokenRetrieved = false; // Flag pour savoir si on a déjà récupéré le token
  bool isTokenRetrieval = false; // Flag pour éviter les tentatives multiples
  int tokenRetrievalAttempts = 0; // Compteur des tentatives
  static const int maxTokenAttempts = 5; // Maximum 5 tentatives

  UserProfile userProfile = UserProfile.loading();
  bool notificationsInitialized = false;
  bool isCheckingAuth = false;
  List<Evaluation> upcomingEvaluations = [];
  EvaluationSummary? evaluationSummary;
  bool isLoadingEvaluations = false;
  String? evaluationError;
  bool showEvaluations = false;

  @override
  void initState() {
    super.initState();
    initializeNotifications();
    initController();
    WidgetsBinding.instance.addObserver(this);

    // MODIFIÉ : Démarrer la récupération du token une seule fois
    _startTokenRetrieval();
  }

  // NOUVELLE MÉTHODE : Démarrer la récupération du token
  Future<void> _startTokenRetrieval() async {
    // Attendre que la page se charge
    await Future.delayed(const Duration(seconds: 3));
    await _attemptTokenRetrieval();
  }

  // Initialisation des notifications
  Future<void> initializeNotifications() async {
    try {
      final bool enabled = await NotificationService.areNotificationsEnabled();

      setState(() {
        notificationsInitialized = enabled;
      });

      if (enabled) {
        print('✅ Notifications système activées');
      } else {
        print('⚠️ Notifications système non autorisées');
        _showNotificationPermissionDialog();
      }
    } catch (e) {
      print('❌ Erreur initialisation notifications: $e');
      setState(() {
        notificationsInitialized = false;
      });
    }
  }

  // Méthode pour demander l'autorisation des notifications
  void _showNotificationPermissionDialog() {
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('🔔 Notifications'),
          content: const Text(
              'Pour recevoir les notifications de bienvenue et autres alertes importantes, '
                  'veuillez autoriser les notifications dans les paramètres de votre appareil.'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Plus tard'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await NotificationService.openNotificationSettings();
              },
              child: const Text('Ouvrir paramètres'),
            ),
          ],
        ),
      );
    }
  }

  void initController() {
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            setState(() {
              isLoading = true;
              hasError = false;
            });
            print('🌐 Page starting: $url');
          },
          onPageFinished: (url) {
            setState(() {
              isLoading = false;
            });
            print('✅ Page finished: $url');

            // MODIFIÉ : Seulement récupérer le token si pas encore fait
            if (!tokenRetrieved && !isTokenRetrieval) {
              Future.delayed(const Duration(seconds: 2), () {
                _attemptTokenRetrieval();
              });
            }
          },
          onWebResourceError: (error) {
            print('❌ Web resource error: ${error.errorCode} - ${error.description}');

            if (error.errorCode == -1 || error.description.contains('ERR_CACHE_MISS')) {
              if (retryCount < 3) {
                retryCount++;
                print('🔄 Retry attempt $retryCount');
                reloadPage();
              } else {
                setState(() {
                  hasError = true;
                  isLoading = false;
                });
              }
            }
          },
          onNavigationRequest: (request) {
            print('🧭 Navigation vers: ${request.url}');

            // MODIFIÉ : Contrôler l'ouverture des liens externes
            if (!request.url.startsWith('https://ouibuddy.com')) {
              // Empêcher l'ouverture automatique dans Safari pour les liens de paiement
              if (request.url.contains('stripe') ||
                  request.url.contains('payment') ||
                  request.url.contains('checkout')) {
                print('🚫 Lien de paiement bloqué: ${request.url}');
                return NavigationDecision.prevent;
              }

              // Pour les autres liens externes, ouvrir dans le navigateur
              launchUrl(Uri.parse(request.url), mode: LaunchMode.externalApplication);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );

    loadDirectUrl();
  }

  void loadDirectUrl() {
    controller.loadRequest(Uri.parse('https://ouibuddy.com'));
  }

  void reloadPage() {
    setState(() {
      isLoading = true;
      hasError = false;
      // NE PAS réinitialiser le token si on l'a déjà
      if (!tokenRetrieved) {
        userProfile = UserProfile.loading();
        isCheckingAuth = false;
      }
    });
    controller.reload();
  }

  // NOUVELLE MÉTHODE : Tentative de récupération du token
  Future<void> _attemptTokenRetrieval() async {
    if (isTokenRetrieval || tokenRetrieved || tokenRetrievalAttempts >= maxTokenAttempts) {
      print('⚠️ Récupération token déjà en cours ou terminée');
      return;
    }

    setState(() {
      isTokenRetrieval = true;
    });

    tokenRetrievalAttempts++;
    print('🔍 Tentative de récupération token #$tokenRetrievalAttempts');

    try {
      // Vérifier l'URL actuelle
      final currentUrl = await controller.runJavaScriptReturningResult('window.location.href');
      final url = currentUrl?.toString().replaceAll('"', '') ?? '';

      print('🌐 URL actuelle pour token: $url');

      // Si on est sur la page de login, attendre et réessayer
      if (url.contains('/login') || url.contains('/auth')) {
        print('🔒 Sur page de login, attente de connexion...');
        setState(() {
          isTokenRetrieval = false;
        });

        // Réessayer dans 5 secondes
        Future.delayed(const Duration(seconds: 5), () {
          if (!tokenRetrieved) {
            _attemptTokenRetrieval();
          }
        });
        return;
      }

      // Récupérer les informations de session
      final sessionInfo = await extractLaravelSession();
      if (sessionInfo != null && sessionInfo['hasActiveSession'] == true) {
        print('✅ Token récupéré avec succès');

        // Récupérer le profil utilisateur
        await fetchUserProfileViaWebView();

        // Marquer comme récupéré
        setState(() {
          tokenRetrieved = true;
          isTokenRetrieval = false;
        });

        // Programmer les notifications une seule fois
        if (userProfile.id != null) {
          await _setupNotificationsOnce();
        }

      } else {
        print('❌ Échec récupération token, tentative ${tokenRetrievalAttempts}/$maxTokenAttempts');
        setState(() {
          isTokenRetrieval = false;
        });

        // Réessayer si pas encore au maximum
        if (tokenRetrievalAttempts < maxTokenAttempts) {
          Future.delayed(const Duration(seconds: 3), () {
            _attemptTokenRetrieval();
          });
        } else {
          print('🚫 Maximum de tentatives atteint pour le token');
          setState(() {
            userProfile = UserProfile.notAuthenticated();
          });
        }
      }

    } catch (e) {
      print('❌ Erreur récupération token: $e');
      setState(() {
        isTokenRetrieval = false;
      });

      // Réessayer en cas d'erreur
      if (tokenRetrievalAttempts < maxTokenAttempts) {
        Future.delayed(const Duration(seconds: 3), () {
          _attemptTokenRetrieval();
        });
      }
    }
  }

  // NOUVELLE MÉTHODE : Configuration des notifications une seule fois
  Future<void> _setupNotificationsOnce() async {
    if (userProfile.id == null || !notificationsInitialized) {
      print('⚠️ Conditions non réunies pour notifications');
      return;
    }

    try {
      print('📱 Configuration unique des notifications...');

      // Envoyer notification de bienvenue
      await NotificationService.showWelcomeNotification(
        userProfile.firstName,
        userProfile.id!,
      );

      // Récupérer les évaluations
      await fetchUserEvaluations();

      // Programmer les notifications
      await scheduleEvaluationNotifications();

      print('✅ Notifications configurées avec succès');

    } catch (e) {
      print('❌ Erreur configuration notifications: $e');
    }
  }

  // MODIFIÉE : Extraction de session sans navigation automatique
  Future<Map<String, dynamic>?> extractLaravelSession() async {
    try {
      print('🔍 Extraction session Laravel...');

      final result = await controller.runJavaScriptReturningResult('''
        (function() {
          try {
            const cookies = document.cookie;
            const sessionInfo = {
              cookies: cookies,
              laravel_session: null,
              xsrf_token: null,
              csrf_token: null,
              hasSession: false
            };
            
            const cookieArray = cookies.split(';');
            for (let cookie of cookieArray) {
              const [name, value] = cookie.trim().split('=');
              if (name === 'laravel_session') {
                sessionInfo.laravel_session = value;
                sessionInfo.hasSession = true;
              }
              if (name === 'XSRF-TOKEN') {
                sessionInfo.xsrf_token = decodeURIComponent(value);
              }
            }
            
            const csrfMeta = document.querySelector('meta[name="csrf-token"]');
            if (csrfMeta) {
              sessionInfo.csrf_token = csrfMeta.getAttribute('content');
            }
            
            sessionInfo.hasActiveSession = sessionInfo.laravel_session && 
                                          (sessionInfo.xsrf_token || sessionInfo.csrf_token);
            
            return JSON.stringify(sessionInfo);
          } catch (error) {
            return JSON.stringify({
              error: error.message,
              hasActiveSession: false
            });
          }
        })()
      ''');

      if (result != null && result.toString() != 'null') {
        String cleanResult = result.toString();

        if (cleanResult.startsWith('"') && cleanResult.endsWith('"')) {
          cleanResult = cleanResult.substring(1, cleanResult.length - 1);
        }

        cleanResult = cleanResult.replaceAll('\\"', '"');
        cleanResult = cleanResult.replaceAll('\\\\', '\\');

        final sessionData = json.decode(cleanResult);
        print('🍪 Session data: $sessionData');

        if (sessionData['hasActiveSession'] == true) {
          sessionToken = sessionData['laravel_session'];
          return sessionData;
        }
      }

      return null;
    } catch (e) {
      print('❌ Erreur extraction session: $e');
      return null;
    }
  }
  // MODIFIÉE : Récupération profil sans navigation automatique
  Future<void> fetchUserProfileViaWebView() async {
    try {
      print('🔍 Récupération profil via API...');

      final result = await controller.runJavaScriptReturningResult('''
      (function() {
        try {
          var csrfToken = document.querySelector('meta[name="csrf-token"]');
          if (!csrfToken) {
            return JSON.stringify({
              success: false,
              error: 'Token CSRF manquant'
            });
          }
          
          var tokenValue = csrfToken.getAttribute('content');
          var xhr = new XMLHttpRequest();
          
          xhr.open('GET', '/profile/connected/basic', false);
          xhr.setRequestHeader('X-CSRF-TOKEN', tokenValue);
          xhr.setRequestHeader('Accept', 'application/json');
          xhr.setRequestHeader('Content-Type', 'application/json');
          xhr.setRequestHeader('X-Requested-With', 'XMLHttpRequest');
          
          try {
            xhr.send();
            
            if (xhr.status === 200) {
              var responseData = JSON.parse(xhr.responseText);
              return JSON.stringify({
                success: true,
                data: responseData,
                status: xhr.status
              });
            } else {
              return JSON.stringify({
                success: false,
                status: xhr.status,
                error: 'Erreur HTTP ' + xhr.status
              });
            }
            
          } catch (networkError) {
            return JSON.stringify({
              success: false,
              error: 'Erreur réseau: ' + networkError.message
            });
          }
          
        } catch (globalError) {
          return JSON.stringify({
            success: false,
            error: 'Erreur globale: ' + globalError.message
          });
        }
      })()
    ''');

      if (result != null && result.toString() != 'null') {
        await handleApiResponse(result.toString());
      } else {
        print('❌ Pas de résultat API');
      }
    } catch (e) {
      print('❌ Erreur récupération profil: $e');
    }
  }

  // MODIFIÉE : Traitement réponse API sans navigation
  Future<void> handleApiResponse(String resultString) async {
    try {
      String cleanResult = resultString;

      if (cleanResult.startsWith('"') && cleanResult.endsWith('"')) {
        cleanResult = cleanResult.substring(1, cleanResult.length - 1);
      }

      cleanResult = cleanResult.replaceAll('\\"', '"');
      cleanResult = cleanResult.replaceAll('\\\\', '\\');

      final response = json.decode(cleanResult);
      print('📡 Réponse API: $response');

      if (response['success'] == true && response['data'] != null) {
        final apiData = response['data'];

        if (apiData['success'] == true && apiData['data'] != null) {
          final profileData = apiData['data'];

          setState(() {
            userProfile = UserProfile.fromJson(profileData);
          });

          print('✅ PROFIL RÉCUPÉRÉ: ${userProfile.firstName} (ID: ${userProfile.id})');

          // SUPPRIMÉ : Pas de navigation automatique

        } else {
          print('❌ Format API inattendu: $apiData');
        }
      } else {
        print('❌ Échec API: $response');
      }
    } catch (parseError) {
      print('❌ Erreur parsing API: $parseError');
    }
  }

  // MODIFIÉE : Programmation notifications simplifiée
  Future<void> scheduleEvaluationNotifications() async {
    if (!notificationsInitialized || userProfile.id == null) {
      print('⚠️ Conditions non réunies pour programmer les notifications');
      return;
    }

    try {
      print('⏰ Programmation notifications évaluations...');

      // Programmer les rappels automatiques toutes les 8 heures
      await BackgroundNotificationService.scheduleFromEvaluations(
        userProfile.firstName,
        userProfile.id!,
        upcomingEvaluations,
      );

      print('✅ Notifications programmées avec succès');

    } catch (e) {
      print('❌ Erreur programmation notifications: $e');
    }
  }

  // MODIFIÉE : Vérification rappels simplifiée
  Future<void> _checkBackgroundReminders() async {
    if (!tokenRetrieved || userProfile.id == null) {
      print('⚠️ Token non récupéré ou pas d\'utilisateur');
      return;
    }

    try {
      await BackgroundNotificationService.checkAndReschedule(
        userProfile.firstName,
        userProfile.id!,
        upcomingEvaluations,
      );
    } catch (e) {
      print('❌ Erreur vérification rappels: $e');
    }
  }

  // Méthode de test des notifications
  Future<void> testNotifications() async {
    if (!notificationsInitialized) {
      print('❌ Notifications non autorisées');

      if (Platform.isIOS) {
        // Demander les permissions iOS
        final bool granted = await NotificationService.requestPermissions();
        setState(() {
          notificationsInitialized = granted;
        });

        if (!granted) {
          _showNotificationPermissionDialog();
          return;
        }
      } else {
        _showNotificationPermissionDialog();
        return;
      }
    }

    try {
      await NotificationService.showTestNotification(userProfile.firstName);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📱 [${Platform.isIOS ? "iOS" : "Android"}] Notification de test envoyée !'),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('❌ Erreur test notifications: $e');
    }
  }

  // MODIFIÉE : Récupération des évaluations avec programmation automatique
  Future<void> fetchUserEvaluations() async {
    if (userProfile.id == null) {
      print('⚠️ Pas d\'utilisateur connecté pour récupérer les évaluations');
      return;
    }

    setState(() {
      isLoadingEvaluations = true;
      evaluationError = null;
    });

    try {
      print('📚 === DEBUG API ÉVALUATIONS ===');
      print('👤 Utilisateur: ${userProfile.firstName} (ID: ${userProfile.id})');
      print('📱 Plateforme: ${Platform.isIOS ? "iOS" : "Android"}');

      if (Platform.isIOS) {
        await fetchUserEvaluationsIOS();
      } else {
        await fetchUserEvaluationsAndroid();
      }

    } catch (e) {
      print('❌ Erreur générale: $e');
      setState(() {
        evaluationError = 'Erreur: ${e.toString()}';
        isLoadingEvaluations = false;
        upcomingEvaluations = [];
        evaluationSummary = null;
        showEvaluations = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  // Version iOS des évaluations (XMLHttpRequest synchrone)
  Future<void> fetchUserEvaluationsIOS() async {
    try {
      print('🍎 [iOS] Récupération évaluations...');

      // Version XMLHttpRequest synchrone pour iOS
      await controller.runJavaScript('''
        (function() {
          try {
            window.debugApiStatus = 'ios_attempting';
            window.debugApiData = null;
            
            var csrfMeta = document.querySelector('meta[name="csrf-token"]');
            if (!csrfMeta) {
              window.debugApiStatus = 'no_csrf';
              return;
            }
            
            var tokenValue = csrfMeta.getAttribute('content');
            var xhr = new XMLHttpRequest();
            
            xhr.open('GET', '/api/upcoming-evaluations?days_ahead=14&include_today=true&per_page=50', false);
            xhr.setRequestHeader('Accept', 'application/json');
            xhr.setRequestHeader('Content-Type', 'application/json');
            xhr.setRequestHeader('X-CSRF-TOKEN', tokenValue);
            xhr.setRequestHeader('X-Requested-With', 'XMLHttpRequest');
            
            xhr.send();
            
            if (xhr.status === 200) {
              try {
                var jsonData = JSON.parse(xhr.responseText);
                window.debugApiData = jsonData;
                window.debugApiStatus = 'ios_success';
              } catch (parseError) {
                window.debugApiData = null;
                window.debugApiStatus = 'parse_error';
                window.debugApiError = parseError.message;
              }
            } else {
              window.debugApiData = null;
              window.debugApiStatus = 'http_error';
              window.debugApiError = 'HTTP ' + xhr.status;
            }
          } catch (error) {
            window.debugApiData = null;
            window.debugApiStatus = 'js_error';
            window.debugApiError = error.message;
          }
        })();
      ''');

      await Future.delayed(const Duration(seconds: 3));
      await processEvaluationResults();

    } catch (e) {
      print('❌ [iOS] Erreur évaluations: $e');
      setState(() {
        evaluationError = '[iOS] ${e.toString()}';
        isLoadingEvaluations = false;
      });
    }
  }

  // Version Android (logique existante avec fetch)
  Future<void> fetchUserEvaluationsAndroid() async {
    await controller.runJavaScript('''
      fetch('/api/upcoming-evaluations?days_ahead=14&include_today=true&per_page=50', {
        method: 'GET',
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'X-CSRF-TOKEN': document.querySelector('meta[name="csrf-token"]')?.content || '',
          'X-Requested-With': 'XMLHttpRequest'
        },
        credentials: 'same-origin'
      })
      .then(function(response) {
        return response.text();
      })
      .then(function(rawText) {
        try {
          const jsonData = JSON.parse(rawText);
          window.debugApiData = jsonData;
          window.debugApiStatus = 'success';
        } catch (parseError) {
          window.debugApiData = null;
          window.debugApiStatus = 'parse_error';
          window.debugApiError = parseError.message;
        }
      })
      .catch(function(error) {
        window.debugApiData = null;
        window.debugApiStatus = 'fetch_error';
        window.debugApiError = error.message;
      });
    ''');

    await Future.delayed(const Duration(seconds: 3));
    await processEvaluationResults();
  }

  // Méthode commune pour traiter les résultats des évaluations
  Future<void> processEvaluationResults() async {
    final debugInfo = await controller.runJavaScriptReturningResult('''
      JSON.stringify({
        status: window.debugApiStatus || 'unknown',
        hasData: window.debugApiData !== null && window.debugApiData !== undefined,
        error: window.debugApiError || null,
        dataType: window.debugApiData ? typeof window.debugApiData : null,
        dataStatus: window.debugApiData ? window.debugApiData.status : null,
        dataCount: window.debugApiData && window.debugApiData.data ? window.debugApiData.data.length : null
      })
    ''');

    if (debugInfo != null) {
      try {
        String cleanDebugInfo = debugInfo.toString();
        if (cleanDebugInfo.startsWith('"') && cleanDebugInfo.endsWith('"')) {
          cleanDebugInfo = cleanDebugInfo.substring(1, cleanDebugInfo.length - 1);
        }
        cleanDebugInfo = cleanDebugInfo.replaceAll('\\"', '"');

        final debug = json.decode(cleanDebugInfo);
        print('🔍 [${Platform.isIOS ? "iOS" : "Android"}] Debug info: $debug');

        if ((debug['status'] == 'success' || debug['status'] == 'ios_success') && debug['hasData'] == true) {
          final fullData = await controller.runJavaScriptReturningResult('''
            window.debugApiData ? JSON.stringify(window.debugApiData) : null
          ''');

          if (fullData != null) {
            String cleanData = fullData.toString();
            if (cleanData.startsWith('"') && cleanData.endsWith('"')) {
              cleanData = cleanData.substring(1, cleanData.length - 1);
            }
            cleanData = cleanData.replaceAll('\\"', '"');
            cleanData = cleanData.replaceAll('\\\\', '\\');

            final apiData = json.decode(cleanData);

            try {
              final evaluations = EvaluationService.parseEvaluations(apiData);
              final summary = EvaluationService.parseSummary(apiData);

              setState(() {
                upcomingEvaluations = evaluations;
                evaluationSummary = summary;
                isLoadingEvaluations = false;
                showEvaluations = true;
                evaluationError = null;
              });

              // Programmer automatiquement les rappels après récupération
              if (evaluations.isNotEmpty && userProfile.id != null && notificationsInitialized) {
                await BackgroundNotificationService.scheduleFromEvaluations(
                  userProfile.firstName,
                  userProfile.id!,
                  evaluations,
                );
                print('🔄 Rappels automatiques (8h) mis à jour avec ${evaluations.length} évaluations');
              }

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✅ [${Platform.isIOS ? "iOS" : "Android"}] ${evaluations.length} évaluations trouvées !'),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 3),
                  ),
                );
              }

            } catch (parseError) {
              print('❌ Erreur parsing avec EvaluationService: $parseError');
              throw parseError;
            }
          } else {
            throw Exception('Impossible de récupérer les données complètes');
          }
        } else {
          String errorMsg = debug['error']?.toString() ?? 'Erreur de récupération des données';
          throw Exception(errorMsg);
        }
      } catch (e) {
        print('❌ Erreur traitement debug: $e');
        throw e;
      }
    } else {
      throw Exception('Aucune information de debug disponible');
    }
  }
  // Fonction pour notifier les évaluations urgentes
  Future<void> notifyUrgentEvaluations() async {
    if (!notificationsInitialized || upcomingEvaluations.isEmpty) {
      print('⚠️ Notifications non autorisées ou aucune évaluation');
      return;
    }

    try {
      final urgentEvaluations = upcomingEvaluations.where((eval) =>
      eval.isToday || eval.isTomorrow || eval.daysUntil <= 2
      ).toList();

      if (urgentEvaluations.isEmpty) {
        print('📱 Aucune évaluation urgente à notifier');
        return;
      }

      print('🚨 ${urgentEvaluations.length} évaluations urgentes trouvées');

      for (final eval in urgentEvaluations) {
        String title = '';
        bool isImportant = false;

        if (eval.isToday) {
          title = '⚠️ Évaluation AUJOURD\'HUI !';
          isImportant = true;
        } else if (eval.isTomorrow) {
          title = '📅 Évaluation DEMAIN';
          isImportant = true;
        } else {
          title = '📚 Évaluation dans ${eval.daysUntil} jours';
          isImportant = false;
        }

        String body = '';
        if (eval.topicCategory?.name != null) {
          body += '${eval.topicCategory!.name}: ';
        }
        body += eval.description ?? 'Évaluation';
        body += '\n📅 ${eval.evaluationDateFormatted}';

        await NotificationService.showNotification(
          id: 100 + eval.id,
          title: title,
          body: body,
          payload: 'evaluation_${eval.id}',
          isImportant: isImportant,
        );

        await Future.delayed(const Duration(milliseconds: 500));
      }

      if (urgentEvaluations.length > 1) {
        final todayCount = urgentEvaluations.where((e) => e.isToday).length;
        final tomorrowCount = urgentEvaluations.where((e) => e.isTomorrow).length;
        final soonCount = urgentEvaluations.where((e) => !e.isToday && !e.isTomorrow).length;

        String summaryBody = '';
        if (todayCount > 0) {
          summaryBody += '$todayCount aujourd\'hui';
        }
        if (tomorrowCount > 0) {
          if (summaryBody.isNotEmpty) summaryBody += ', ';
          summaryBody += '$tomorrowCount demain';
        }
        if (soonCount > 0) {
          if (summaryBody.isNotEmpty) summaryBody += ', ';
          summaryBody += '$soonCount bientôt';
        }

        await NotificationService.showNotification(
          id: 200,
          title: '📚 Résumé: ${urgentEvaluations.length} évaluations urgentes',
          body: summaryBody,
          payload: 'evaluations_summary',
          isImportant: todayCount > 0,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📱 [${Platform.isIOS ? "iOS" : "Android"}] ${urgentEvaluations.length} notifications envoyées pour les évaluations urgentes'),
            backgroundColor: urgentEvaluations.any((e) => e.isToday) ? Colors.red : Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
      }

    } catch (e) {
      print('❌ Erreur envoi notifications évaluations: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erreur notifications: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // Afficher les évaluations dans un bottom sheet
  void _showEvaluationsBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              height: 4,
              width: 40,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.school, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text(
                    'Mes évaluations ${Platform.isIOS ? "🍎" : "🤖"}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => fetchUserEvaluations(),
                    icon: Icon(
                      Icons.refresh,
                      color: isLoadingEvaluations ? Colors.orange : Colors.blue,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            Expanded(
              child: EvaluationsList(
                evaluations: upcomingEvaluations,
                summary: evaluationSummary,
                isLoading: isLoadingEvaluations,
                errorMessage: evaluationError,
                onRefresh: fetchUserEvaluations,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        print('📱 App reprise');
        // Seulement vérifier les rappels si token déjà récupéré
        if (tokenRetrieved) {
          _checkBackgroundReminders();
        }
        break;
      case AppLifecycleState.paused:
        print('📱 App en pause - rappels automatiques (8h) continuent');
        break;
      case AppLifecycleState.detached:
        print('📱 App fermée - rappels automatiques (8h) actifs');
        break;
      case AppLifecycleState.inactive:
        print('📱 App inactive');
        break;
      case AppLifecycleState.hidden:
        print('📱 App cachée');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // WebView principal
            WebViewWidget(controller: controller),

            // Indicateur de chargement
            if (isLoading)
              const Center(
                child: CircularProgressIndicator(),
              ),

            // Indicateur d'erreur
            if (hasError)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 50),
                    const SizedBox(height: 20),
                    const Text('Impossible de charger la page'),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () {
                        retryCount = 0;
                        loadDirectUrl();
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),

            // Petit indicateur de statut utilisateur connecté
            if (userProfile.id != null && !userProfile.loading)
              Positioned(
                top: 10,
                left: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: tokenRetrieved ? Colors.green : Colors.orange,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        tokenRetrieved ? Icons.check_circle : Icons.person,
                        color: Colors.white,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        userProfile.firstName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Indicateur de récupération du token
            if (isTokenRetrieval)
              Positioned(
                top: 10,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Token $tokenRetrievalAttempts/$maxTokenAttempts',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}